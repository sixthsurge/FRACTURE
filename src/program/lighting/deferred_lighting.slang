// Deferred shading for opaque layer, draw sky.

import aperture;
import lib.lighting.celestial;
import lib.lighting.emission;
import lib.lighting.lightmap;
import lib.lighting.shadow;
import lib.lighting.restir_gi;
import lib.lighting.vxrt.reference_pt;
import lib.surface.gbuffer_packing;
import lib.surface.material;
import lib.util.color;
import lib.util.encoding;
import lib.util.math;
import lib.util.random;
import lib.util.space_conversion;
import lib.volumetrics.atmosphere;
import lib.volumetrics.fog;
import lib.volumetrics.sky;
import settings;
import lib.util.debug;

RWTexture2D<float3> tex_scene_write;
Texture2D<uint4> tex_gbuffer_opaque;
Texture3D<float3> tex_atmosphere_aerial_perspective;
Texture2D<float3> tex_atmosphere_transmittance;
Texture3D<float3> tex_fog_volume_integrated_light;
Texture3D<float3> tex_fog_volume_integrated_extinction;
Texture2D<float4> tex_qres_temporal_data_current;
Texture2D<float4> tex_gtao_output_current;
Texture2D<float3> tex_rsm_output_filtered;
Texture2D<float> tex_blue_noise;

Texture2D tex_reserviour_spatial_1;
Texture2D tex_reserviour_spatial_2;
Texture2D tex_reserviour_spatial_3;
Texture2D tex_reserviour_spatial_4;

struct QuarterResLighting {
	struct Upscaled {
		float4 gtao_output;
		float3 rsm_output;
	}

	float4 gtao_output_00;
	float4 gtao_output_01;
	float4 gtao_output_10;
	float4 gtao_output_11;
	float3 rsm_output_00;
	float3 rsm_output_01;
	float3 rsm_output_10;
	float3 rsm_output_11;
	float4 qres_data_00;
	float4 qres_data_01;
	float4 qres_data_10;
	float4 qres_data_11;

	static QuarterResLighting load(int2 qres_pos) {
		// FIXME Try using shared memory for this.

		int w, h;
		tex_qres_temporal_data_current.GetDimensions(w, h);

		int2 p10 = clamp(qres_pos + int2(1, 0), int2(0), int2(w, h) - 1);
		int2 p01 = clamp(qres_pos + int2(0, 1), int2(0), int2(w, h) - 1);
		int2 p11 = clamp(qres_pos + int2(1, 1), int2(0), int2(w, h) - 1);

		QuarterResLighting qres;
		if (userSettings.GTAO_ENABLED) {
			qres.gtao_output_00 = tex_gtao_output_current[qres_pos];
			qres.gtao_output_01 = tex_gtao_output_current[p01];
			qres.gtao_output_10 = tex_gtao_output_current[p10];
			qres.gtao_output_11 = tex_gtao_output_current[p11];
		}
		if (userSettings.RSM_ENABLED) {
			qres.rsm_output_00 = tex_rsm_output_filtered[qres_pos];
			qres.rsm_output_01 = tex_rsm_output_filtered[p01];
			qres.rsm_output_10 = tex_rsm_output_filtered[p10];
			qres.rsm_output_11 = tex_rsm_output_filtered[p11];
		}
		qres.qres_data_00 = tex_qres_temporal_data_current[qres_pos];
		qres.qres_data_01 = tex_qres_temporal_data_current[p01];
		qres.qres_data_10 = tex_qres_temporal_data_current[p10];
		qres.qres_data_11 = tex_qres_temporal_data_current[p11];

		return qres;
	}

	private static float
	depth_weight(float center_depth_view, float NoV, float4 data) {
		const float STRENGTH = 10.0;
		return exp2(
			-STRENGTH
			* abs((screen_to_view_depth(data.y) - center_depth_view) * NoV)
		);
	}

	private static float
	normal_weight(float3 center_normal_world, float4 data) {
		return pow16(
			max0(dot(center_normal_world, decode_octahedral(data.zw)))
		);
	}

	Upscaled
	upscale(float3 normal_world, float depth_view, float NoV, float2 frac_pos) {
		float w00 = depth_weight(depth_view, NoV, qres_data_00)
			* normal_weight(normal_world, qres_data_00) * (1.0 - frac_pos.x)
			* (1.0 - frac_pos.y);
		float w10 = depth_weight(depth_view, NoV, qres_data_10)
			* normal_weight(normal_world, qres_data_10)
			* (frac_pos.x - frac_pos.x * frac_pos.y);
		float w01 = depth_weight(depth_view, NoV, qres_data_01)
			* normal_weight(normal_world, qres_data_01)
			* (frac_pos.y - frac_pos.x * frac_pos.y);
		float w11 = depth_weight(depth_view, NoV, qres_data_11)
			* normal_weight(normal_world, qres_data_11)
			* (frac_pos.x * frac_pos.y);
		float w_sum = w00 + w10 + w01 + w11;
		float rcp_w_sum = rcp(w_sum);

		if (w_sum > EPS) {
			float4 gtao_output = gtao_output_00 * w00 + gtao_output_01 * w01
				+ gtao_output_10 * w10 + gtao_output_11 * w11;
			float3 rsm_output = rsm_output_00 * w00 + rsm_output_01 * w01
				+ rsm_output_10 * w10 + rsm_output_11 * w11;

			return Upscaled(gtao_output * rcp_w_sum, rsm_output * rcp_w_sum);
		} else {
			return Upscaled(gtao_output_00, rsm_output_00);
		}
	}
}

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID) {
	float2 coord = float2(icoord) + 0.5;
	float2 ncoord = coord / float2(ap.game.renderSize);

	float depth = ap.opaqueDepth[icoord];
	uint4 packed_gbuffer = tex_gbuffer_opaque[icoord];
	float2 dither = float2(
		tex_blue_noise[icoord & 511],
		tex_blue_noise[(icoord + int2(93, 41)) & 511]
	);

	float3 pos_screen = float3(ncoord, depth);
	float3 pos_view = screen_to_view(pos_screen);

	// Lookup fog participation a while before using it (latency hiding).
	fog.FogParticipation fog_participation = fog.lookup_fog_participation(
		tex_fog_volume_integrated_light,
		tex_fog_volume_integrated_extinction,
		pos_screen,
		pos_view
	);

	float3 pos_scene = view_to_scene(pos_view);
	float3 dir_world = normalize(pos_scene);

	if (depth == 0.0) {
		float3 radiance = calculate_sky_radiance(dir_world);
		radiance = fog_participation.apply(radiance);
		tex_scene_write[icoord] = radiance;
		return;
	}

	// Sampling half-res lighting to upscale a while before using it
	// (latency hiding).
	float2 qres_pos = float2(icoord)
		* (ceil(float2(ap.game.renderSize) * 0.5) / float2(ap.game.renderSize));
	int2 qres_pos_i = int2(qres_pos);
	float2 qres_pos_f = frac(qres_pos);
	QuarterResLighting qres = QuarterResLighting.load(qres_pos_i);

	OpaqueGbuffer gbuffer = OpaqueGbuffer.unpack(packed_gbuffer);

	float3 albedo = srgb_eotf_inv(gbuffer.albedo);

	Material material = Material.get(albedo, gbuffer.mat_id);
	if (userSettings.LABPBR_SUPPORT_ENABLED) {
		material.apply_specular_map(gbuffer.specular_map.get().value);
	}

	QuarterResLighting.Upscaled upscaled = qres.upscale(
		gbuffer.flat_normal_world,
		screen_to_view_depth(depth),
		dot(gbuffer.flat_normal_world, dir_world),
		qres_pos_f
	);
	float ao, ambient_sss;
	float3 bent_normal_world;
	if (userSettings.GTAO_ENABLED) {
		ao = upscaled.gtao_output.x;
		ambient_sss = upscaled.gtao_output.y;
		bent_normal_world = mul(
			float3x3(ap.camera.viewInv),
			normalize(float3(
				upscaled.gtao_output.zw,
				sqrt(saturate(1.0 - length_squared(upscaled.gtao_output.zw)))
			))
		);
	} else {
		ao = 1.0;
		ambient_sss = 0.0;
		bent_normal_world = gbuffer.flat_normal_world;
	}

	if (userSettings.LABPBR_SUPPORT_ENABLED) {
		ao *= gbuffer.texture_ao.get().value;
	}

	if (userSettings.TAA_ENABLED) {
		// Animate dither when TAA is enabled so it can help a little with
		// the noise.
		dither = r2(ap.timing.frameCounter, dither);
	}

	float3 detail_normal_world
		= gbuffer.detail_normal_world.get().orElse(gbuffer.flat_normal_world);

	shadow.Result shadow_result = shadow.calculate(
		pos_scene,
		gbuffer.flat_normal_world,
		dither,
		material.sss_amount > EPS
	);
	shadow_result.visibility
		*= select(gbuffer.parallax_self_shadow.get().orElse(false), 0.0, 1.0);

	float3 ambient_brdf
		= material.albedo / PI * (1.0 + ambient_sss * material.sss_amount);
	float3 radiance
		= calculate_celestial_light(
			  material,
			  shadow_result,
			  pos_scene,
			  dir_world,
			  gbuffer.flat_normal_world,
			  detail_normal_world
		  )
		+ calculate_emission(material.emission);

	if (!userSettings.REFERENCE_PT_ENABLED && !userSettings.RESTIR_GI_ENABLED) {
		radiance += calculate_lightmap_skylight(
			ambient_brdf,
			gbuffer.lightmap,
			bent_normal_world,
			ao,
		);
		radiance += calculate_lightmap_blocklight(
			ambient_brdf,
			gbuffer.lightmap,
			ao
		);

		if (userSettings.RSM_ENABLED) {
			radiance += ambient_brdf * upscaled.rsm_output * PI
				* buf_global.celestial_light_irradiance;
		}
	}

	if (userSettings.ATMOSPHERE_AP_LUT_ENABLED) {
		radiance = atmosphere.apply_aerial_perspective(
			tex_atmosphere_aerial_perspective,
			tex_atmosphere_transmittance,
			pos_screen,
			pos_scene,
			radiance
		);
	}

	radiance = fog_participation.apply(radiance);

	if (userSettings.REFERENCE_PT_ENABLED) {
		uint seed = (ap.timing.frameCounter * ap.game.renderSize.x + icoord.y)
				* ap.game.renderSize.y
			+ icoord.x;
		radiance += vxrt.reference_pt<PcgRandom, 1, 3>(
			PcgRandom(seed),
			material,
			pos_scene + ap.camera.position,
			dir_world,
			gbuffer.flat_normal_world,
			detail_normal_world
		);
	} else if (userSettings.RESTIR_GI_ENABLED) {
		restir_gi.Reserviour r;
		r.load(
			tex_reserviour_spatial_1,
			tex_reserviour_spatial_2,
			tex_reserviour_spatial_3,
			tex_reserviour_spatial_4,
			icoord
		);
		radiance += max0(r.sample.radiance * r.W) * material.albedo;
	}

	tex_scene_write[icoord] = radiance;
}


