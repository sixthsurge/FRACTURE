// Calculate + accumulate GTAO, RSM.

import aperture;
import lib.surface.gbuffer_packing;
import lib.lighting.gtao;
import lib.lighting.restir_gi;
import lib.lighting.rsm;
import lib.lighting.simple;
import lib.toggles;
import lib.util.encoding;
import lib.util.filtering;
import lib.util.math;
import lib.util.random;
import lib.util.space_conversion;
import settings;

import lib.util.debug;

RWTexture2D<float4> tex_indirect_output_accumulated;
RWTexture2D<float4> tex_indirect_temporal_data_current;

Texture2D<float4> tex_indirect_output_blurred;
Texture2D<float4> tex_indirect_temporal_data_prev;
Texture2D<uint4> tex_gbuffer_opaque;
Texture2D<float> tex_noise_blue;

Texture2D tex_reserviour_spatial_1;
Texture2D tex_reserviour_spatial_2;
Texture2D tex_reserviour_spatial_3;
Texture2D tex_reserviour_spatial_4;

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID) {
	int w, h;
	tex_indirect_output_accumulated.GetDimensions(w, h);
	float2 output_pixel_size = rcp(float2(w, h));

	int2 fullres_icoord = int2(
		float2(icoord) * (float2(ap.game.renderSize) * output_pixel_size)
	);
	if (any(fullres_icoord >= ap.game.renderSize)) {
		return;
	}

	float depth = ap.depth[fullres_icoord];
	uint4 gbuffer_packed = tex_gbuffer_opaque[fullres_icoord];
	float2 dither = float2(
		tex_noise_blue[icoord & 511],
		tex_noise_blue[(icoord + int2(93, 41)) & 511]
	);

	if (depth == 0.0) {
		tex_indirect_output_accumulated[icoord] = float4(0.0, 0.0, 0.0, 1.0);
		tex_indirect_temporal_data_current[icoord] = float4(0.0);
		return;
	}
	float3 pos_screen = float3((icoord + 0.5) * output_pixel_size, depth);
	float3 pos_view = screen_to_view(pos_screen);
	float3 pos_scene = view_to_scene(pos_view);

	OpaqueGbuffer gbuffer = OpaqueGbuffer.unpack(gbuffer_packed);
	float3 normal_world
		= gbuffer.detail_normal_world.get().orElse(gbuffer.flat_normal_world);
	float3 normal_view = mul(float3x3(ap.camera.view), normal_world);

	float4 indirect;
	float frame_weight = 1.0;
	if (userSettings.RESTIR_GI_ENABLED) {
		restir_gi.Reserviour r;
		r.load(
			tex_reserviour_spatial_1,
			tex_reserviour_spatial_2,
			tex_reserviour_spatial_3,
			tex_reserviour_spatial_4,
			icoord
		);
		indirect.rgb = PI * max0(r.sample.radiance * r.W);
		frame_weight = saturate(r.M * 0.1) * 5.0;
		indirect.a = 1.0;
	} else {
		gtao.Result gtao_result
			= gtao.calculate(pos_screen, pos_view, normal_view, dither);

		float3 rsm = rsm.calculate(
			pos_scene,
			normal_world,
			dither,
			gbuffer.lightmap.y
		);

		indirect = max0(float4(
			rsm * buf_global.celestial_light_irradiance
				+ calculate_lightmap_skylight(
					float3(1.0),
					gbuffer.lightmap,
					gtao_result.bent_normal,
					gtao_result.ao
				),
			gtao_result.ao
		));
	}

	float3 pos_prev_view = scene_to_view(
		pos_scene + ap.camera.position - ap.temporal.position,
		ap.temporal.view
	);
	float3 pos_prev_screen
		= view_to_screen(pos_prev_view, ap.temporal.projection);

	float4 indirect_output_prev
		= tex_indirect_output_blurred
			  .sample_catmull_rom_fast(pos_prev_screen.xy, 0, 0.65);
	float4 temporal_data_prev
		= tex_indirect_temporal_data_prev.sampleNearest(pos_prev_screen.xy);

	// Accumulation.
	float pixel_age = 0.0;
	float depth_prev = 0.0;
	if (all(saturate(pos_prev_screen.xy) == pos_prev_screen.xy)
		&& ap.timing.frameCounter > 1 && all(isfinite(indirect_output_prev))
		&& all(isfinite(temporal_data_prev))) {
		const float MAX_ACCUMULATED_FRAMES = 10.0;
		const float DEPTH_REJECTION_STRENGTH = 80.0;

		pixel_age = temporal_data_prev.x;
		depth_prev = temporal_data_prev.y;
		float3 normal_prev = decode_octahedral(temporal_data_prev.zw);

		// Depth rejection
		float view_norm = rlength(pos_view);
		float NoV = abs(dot(normal_view, pos_view))
			* view_norm; // NoV / sqrt(length(view_pos))
		float z0 = screen_to_view_depth(depth);
		float z1 = screen_to_view_depth(depth_prev, ap.temporal.projectionInv);
		float3 pos_world_prev
			= view_to_scene(
				  screen_to_view(
					  float3(pos_prev_screen.xy, depth_prev),
					  ap.temporal.projectionInv
				  ),
				  ap.temporal.viewInv
			  )
			+ ap.temporal.position;
		float depth_weight = exp2(
			-distance(pos_scene + ap.camera.position, pos_world_prev)
			* DEPTH_REJECTION_STRENGTH * NoV * view_norm
		);

		// Normal rejection
		float normal_weight = exp2(
			-16.0 * (1.0 - max0(dot(normal_prev, normal_world))) * view_norm
		);

		pixel_age *= depth_weight * normal_weight * float(depth_prev != 0.0);

		pixel_age = min(pixel_age, MAX_ACCUMULATED_FRAMES);
		float history_weight = pixel_age / (pixel_age + frame_weight);

		// Blend with history.
		indirect = lerp(indirect, max0(indirect_output_prev), history_weight);
	}

	tex_indirect_output_accumulated[icoord] = indirect;
	tex_indirect_temporal_data_current[icoord] = float4(
		pixel_age + frame_weight,
		depth,
		encode_octahedral(normal_world)
	);
}


