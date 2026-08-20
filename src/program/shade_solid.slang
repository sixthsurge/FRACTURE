import aperture;
import lib.atmospherics.atmosphere;
import lib.atmospherics.fog;
import lib.atmospherics.sky;
import lib.gbuffer_packing;
import lib.lighting.main_lighting;
import lib.lighting.material;
import lib.util.color;
import lib.util.math;
import lib.util.random;
import lib.util.space_conversion;
import settings;

RWTexture2D<float3> tex_scene_write;
Texture2D<uint4> tex_gbuffer_solid;
Texture3D<float3> tex_atmosphere_aerial_perspective;
Texture2D<float3> tex_atmosphere_transmittance;
Texture3D<float3> tex_fog_volume_integrated_light;
Texture3D<float3> tex_fog_volume_integrated_extinction;
Texture2D<float2> tex_qres_temporal_data_current;
Texture2D<float4> tex_gtao_output_current;
Texture2D<float3> tex_rsm_output_current;
Texture2D<float> tex_blue_noise;

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
	float qres_depth_00;
	float qres_depth_01;
	float qres_depth_10;
	float qres_depth_11;

	static QuarterResLighting load(int2 qres_pos) {
		// FIXME Try using shared memory for this.

		int2 p10 = qres_pos + int2(1, 0);
		int2 p01 = qres_pos + int2(0, 1);
		int2 p11 = qres_pos + int2(1, 1);

		QuarterResLighting qres;
		if (userSettings.GTAO_ENABLED) {
			qres.gtao_output_00 = tex_gtao_output_current[qres_pos];
			qres.gtao_output_01 = tex_gtao_output_current[p01];
			qres.gtao_output_10 = tex_gtao_output_current[p10];
			qres.gtao_output_11 = tex_gtao_output_current[p11];
		}
		if (userSettings.RSM_ENABLED) {
			qres.rsm_output_00 = tex_rsm_output_current[qres_pos];
			qres.rsm_output_01 = tex_rsm_output_current[p01];
			qres.rsm_output_10 = tex_rsm_output_current[p10];
			qres.rsm_output_11 = tex_rsm_output_current[p11];
		}
		qres.qres_depth_00 = tex_qres_temporal_data_current[qres_pos].y;
		qres.qres_depth_01 = tex_qres_temporal_data_current[p01].y;
		qres.qres_depth_10 = tex_qres_temporal_data_current[p10].y;
		qres.qres_depth_11 = tex_qres_temporal_data_current[p11].y;

		return qres;
	}

	private static float
	depth_weight(float center_depth_view, float depth_screen) {
		const float STRENGTH = 10.0;
		return exp2(
			-STRENGTH
			* abs(screen_to_view_depth(depth_screen) - center_depth_view)
		);
	}

	Upscaled upscale(float depth_view, float2 frac_pos) {
		float w00 = depth_weight(depth_view, qres_depth_00) * (1.0 - frac_pos.x)
			* (1.0 - frac_pos.y);
		float w10 = depth_weight(depth_view, qres_depth_10)
			* (frac_pos.x - frac_pos.x * frac_pos.y);
		float w01 = depth_weight(depth_view, qres_depth_01)
			* (frac_pos.y - frac_pos.x * frac_pos.y);
		float w11 = depth_weight(depth_view, qres_depth_11)
			* (frac_pos.x * frac_pos.y);
		float w_sum = w00 + w10 + w01 + w11;
		float rcp_w_sum = rcp(w_sum);

		[flatten]
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
	uint4 packed_gbuffer = tex_gbuffer_solid[icoord];
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
	float2 qres_pos = float2(icoord) * 0.5;
	int2 qres_pos_i = int2(qres_pos);
	float2 qres_pos_f = frac(qres_pos);
	QuarterResLighting qres = QuarterResLighting.load(qres_pos_i);

	SolidGbuffer gbuffer = SolidGbuffer.unpack(packed_gbuffer);

	float3 albedo = srgb_eotf_inv(gbuffer.albedo);

	Material material = Material.get(albedo, gbuffer.mat_id);
	if (userSettings.LABPBR_SUPPORT_ENABLED) {
		material.apply_specular_map(gbuffer.specular_map.get().value);
	}

	QuarterResLighting.Upscaled upscaled
		= qres.upscale(screen_to_view_depth(depth), qres_pos_f);
	float3 bent_normal_world = mul(
		float3x3(ap.camera.viewInv),
		float3(
			upscaled.gtao_output.zw,
			sqrt(saturate(1.0 - length_squared(upscaled.gtao_output.zw)))
		)
	);

	if (userSettings.TAA_ENABLED) {
		// Animate dither when TAA is enabled so it can help a little with
		// the noise.
		dither = r2(ap.timing.frameCounter, dither);
	}

	float3 radiance = calculate_outgoing_radiance(
		material,
		pos_scene,
		dir_world,
		gbuffer.flat_normal_world,
		gbuffer.detail_normal_world.get().orElse(gbuffer.flat_normal_world),
		gbuffer.lightmap,
		upscaled.gtao_output.x,
		upscaled.gtao_output.y,
		bent_normal_world,
		dither
	);

	radiance += material.albedo * upscaled.rsm_output
		* buf_global.celestial_light_irradiance;

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

	tex_scene_write[icoord] = radiance;
}


