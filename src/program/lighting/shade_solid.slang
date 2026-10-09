// Deferred shading for opaque layer, draw sky.

import aperture;
import lib.atmospherics.atmosphere;
import lib.atmospherics.fog;
import lib.atmospherics.sky;
import lib.lighting.celestial;
import lib.lighting.cloud_shadow;
import lib.lighting.emission;
import lib.lighting.simple;
import lib.lighting.shadow;
import lib.lighting.restir_gi;
import lib.lighting.vxrt.reference_pt;
import lib.surface.gbuffer_packing;
import lib.surface.material;
import lib.toggles;
import lib.util.color;
import lib.util.encoding;
import lib.util.math;
import lib.util.random;
import lib.util.space_conversion;
import settings;

import rt_pipeline;
import lib.util.debug;

RWTexture2D<float3> tex_scene_write;
Texture2D<uint4> tex_gbuffer_opaque;
Texture3D<float3> tex_atmosphere_aerial_perspective;
Texture2D<float3> tex_atmosphere_transmittance;
Texture2D<float4> tex_clouds_temporal_current;
Texture3D<float3> tex_fog_volume_integrated_light;
Texture3D<float3> tex_fog_volume_integrated_extinction;
Texture2D<float4> tex_indirect_output_blurred;
Texture2D<float4> tex_indirect_temporal_data_current;
Texture2D<float> tex_cloud_shadow;
Texture2D<float> tex_noise_blue;

namespace indirect_upscaling {
static float depth_weight(float center_depth_view, float NoV, float4 data) {
	const float STRENGTH = 10.0;
	return exp2(
		-STRENGTH
		* abs((screen_to_view_depth(data.y) - center_depth_view) * NoV)
	);
}

static float normal_weight(float3 center_normal_world, float4 data) {
	return pow16(max0(dot(center_normal_world, decode_octahedral(data.zw))));
}

float4 upscale(float2 pos, float3 normal_world, float depth_view, float NoV) {
	float2 floored_pos, frac_pos = modf(pos, floored_pos);
	int2 int_pos = int2(floored_pos);

	int w, h;
	tex_indirect_output_blurred.GetDimensions(w, h);

	int2 p10 = clamp(int_pos + int2(1, 0), int2(0), int2(w, h) - 1);
	int2 p01 = clamp(int_pos + int2(0, 1), int2(0), int2(w, h) - 1);
	int2 p11 = clamp(int_pos + int2(1, 1), int2(0), int2(w, h) - 1);

	float4 output_00 = tex_indirect_output_blurred[int_pos];
	float4 output_01 = tex_indirect_output_blurred[p01];
	float4 output_10 = tex_indirect_output_blurred[p10];
	float4 output_11 = tex_indirect_output_blurred[p11];
	float4 data_00 = tex_indirect_temporal_data_current[int_pos];
	float4 data_01 = tex_indirect_temporal_data_current[p01];
	float4 data_10 = tex_indirect_temporal_data_current[p10];
	float4 data_11 = tex_indirect_temporal_data_current[p11];

	float w00 = depth_weight(depth_view, NoV, data_00)
		* normal_weight(normal_world, data_00) * (1.0 - frac_pos.x)
		* (1.0 - frac_pos.y);
	float w10 = depth_weight(depth_view, NoV, data_10)
		* normal_weight(normal_world, data_10)
		* (frac_pos.x - frac_pos.x * frac_pos.y);
	float w01 = depth_weight(depth_view, NoV, data_01)
		* normal_weight(normal_world, data_01)
		* (frac_pos.y - frac_pos.x * frac_pos.y);
	float w11 = depth_weight(depth_view, NoV, data_11)
		* normal_weight(normal_world, data_11) * (frac_pos.x * frac_pos.y);
	float w_sum = w00 + w10 + w01 + w11;
	float rcp_w_sum = rcp(w_sum);

	if (w_sum > EPS) {
		return (output_00 * w00 + output_01 * w01 + output_10 * w10
				+ output_11 * w11)
			* rcp_w_sum;
	} else {
		return output_00;
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
		tex_noise_blue[icoord & 511],
		tex_noise_blue[(icoord + int2(93, 41)) & 511]
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
	float3 dir_world
		= normalize(pos_scene - translation_part(ap.camera.viewInv));

	if (depth == 0.0) {
		float3 radiance
			= sky.DimensionSky.render<sky.RenderPurpose.MainImage>(dir_world);

		if (TOGGLE_CLOUDS) {
			float4 clouds = tex_clouds_temporal_current[icoord];
			radiance = radiance * clouds.w + clouds.xyz;
		}

		radiance = fog_participation.apply(radiance);

		tex_scene_write[icoord] = radiance;
		return;
	}

	OpaqueGbuffer gbuffer = OpaqueGbuffer.unpack(packed_gbuffer);

	float3 albedo = srgb_eotf_inv(gbuffer.albedo);

	Material material = Material.get(albedo, gbuffer.mat_id);
	if (userSettings.LABPBR_SUPPORT_ENABLED) {
		material.apply_specular_map(gbuffer.specular_map.get().value);
	}

	float3 detail_normal_world
		= gbuffer.detail_normal_world.get().orElse(gbuffer.flat_normal_world);

	float2 indirect_pos = float2(icoord)
		* (ceil(float2(ap.game.renderSize) * userSettings.INDIRECT_RENDER_SCALE)
		   / float2(ap.game.renderSize));
	float4 indirect = indirect_upscaling.upscale(
		indirect_pos,
		detail_normal_world,
		screen_to_view_depth(depth),
		dot(gbuffer.flat_normal_world, dir_world),
	);

	if (userSettings.LABPBR_SUPPORT_ENABLED) {
		indirect.rgb *= gbuffer.texture_ao.get().value;
	}

	if (userSettings.TAA_ENABLED) {
		// Animate dither when TAA is enabled so it can help a little with
		// the noise.
		dither = r2(ap.timing.frameCounter, dither);
	}

	float cloud_shadow = 1.0;
	if (TOGGLE_CLOUD_SHADOW) {
		cloud_shadow = ::cloud_shadow::sample(tex_cloud_shadow, pos_scene);
	}

	shadow.Result shadow_result = shadow.calculate(
		pos_scene,
		gbuffer.flat_normal_world,
		dither,
		material.sss_amount > EPS,
		cloud_shadow
	);
	shadow_result.visibility
		*= select(gbuffer.parallax_self_shadow.get().orElse(false), 0.0, 1.0);

	float3 ambient_brdf = material.albedo / PI;

	float3 radiance
		= calculate_celestial_light(
			  material,
			  shadow_result,
			  pos_scene,
			  dir_world,
			  gbuffer.flat_normal_world,
			  detail_normal_world,
			  cloud_shadow
		  )
		+ calculate_ambient_light(
			  ambient_brdf,
			  gbuffer.flat_normal_world,
			  indirect.w
		)
		+ calculate_emission(material.emission) + indirect.rgb * ambient_brdf;

	if (!userSettings.REFERENCE_PT_ENABLED && !userSettings.RESTIR_GI_ENABLED) {
		radiance += calculate_lightmap_blocklight(
			ambient_brdf,
			gbuffer.lightmap,
			indirect.w,
		);
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
			pos_scene,
			dir_world,
			gbuffer.flat_normal_world,
			detail_normal_world
		);
	}

	tex_scene_write[icoord] = radiance;
}


