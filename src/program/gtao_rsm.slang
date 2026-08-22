import aperture;
import lib.gbuffer_packing;
import lib.lighting.gtao;
import lib.lighting.rsm;
import lib.util.filtering;
import lib.util.math;
import lib.util.random;
import lib.util.space_conversion;
import settings;

RWTexture2D<float4> tex_gtao_output_current;
RWTexture2D<float3> tex_rsm_output_current;
RWTexture2D<float2> tex_qres_temporal_data_current;

Texture2D<float4> tex_gtao_output_prev;
Texture2D<float3> tex_rsm_output_prev;
Texture2D<float2> tex_qres_temporal_data_prev;
Texture2D<uint4> tex_gbuffer_solid;
Texture2D<float> tex_blue_noise;

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID) {
	int w, h;
	tex_gtao_output_current.GetDimensions(w, h);
	float2 output_pixel_size = rcp(float2(w, h));

	int2 fullres_icoord = int2(
		float2(icoord) * (float2(ap.game.renderSize) * output_pixel_size)
	);
	if (any(fullres_icoord >= ap.game.renderSize)) {
		return;
	}

	float depth = ap.depth[fullres_icoord];
	uint4 gbuffer_packed = tex_gbuffer_solid[fullres_icoord];
	float2 dither = float2(
		tex_blue_noise[icoord & 511],
		tex_blue_noise[(icoord + int2(93, 41)) & 511]
	);

	if (depth == 0.0) {
		tex_gtao_output_current[icoord] = float4(1.0, 0.0, 0.0, 0.0);
		tex_rsm_output_current[icoord] = float3(0.0);
		tex_qres_temporal_data_current[icoord] = float2(0.0);
		return;
	}
	float3 pos_screen = float3((icoord + 0.5) * output_pixel_size, depth);
	float3 pos_view = screen_to_view(pos_screen);
	float3 pos_scene = view_to_scene(pos_view);
	float3 pos_prev_view = scene_to_view(
		pos_scene + ap.camera.position - ap.temporal.position,
		ap.temporal.view
	);
	float3 pos_prev_screen
		= view_to_screen(pos_prev_view, ap.temporal.projection);

	float4 gtao_output_prev = tex_gtao_output_prev.sample_catmull_rom_fast(
		pos_prev_screen.xy,
		0,
		0.65
	);
	float3 rsm_output_prev = tex_rsm_output_prev.sample_catmull_rom_fast(
		pos_prev_screen.xy,
		0,
		0.65
	);
	float2 temporal_data_prev
		= tex_qres_temporal_data_prev.sampleLinear(pos_prev_screen.xy);

	SolidGbuffer gbuffer = SolidGbuffer.unpack(gbuffer_packed);
	float3 normal_world
		= gbuffer.detail_normal_world.get().orElse(gbuffer.flat_normal_world);
	float3 normal_view = mul(float3x3(ap.camera.view), normal_world);

	dither = r2(ap.timing.frameCounter, dither);

	gtao.Result gtao_result
		= gtao.calculate(pos_screen, pos_view, normal_view, dither);

	float3 rsm = rsm.calculate(pos_scene, normal_world, dither);

	// Accumulation.
	float pixel_age = 0.0;
	float depth_prev = 0.0;
	if (all(saturate(pos_prev_screen.xy) == pos_prev_screen.xy)
		&& ap.timing.frameCounter > 1 && all(isfinite(temporal_data_prev))) {
		const float MAX_ACCUMULATED_FRAMES = 10.0;
		const float DEPTH_REJECTION_STRENGTH = 128.0;
		const float OFFCENTER_REJECTION_STRENGTH = 0.25;

		pixel_age = temporal_data_prev.x;
		depth_prev = temporal_data_prev.y;

		float3 bent_normal_prev;
		bent_normal_prev.xy = gtao_output_prev.zw;
		bent_normal_prev.z
			= sqrt(saturate(1.0 - length_squared(bent_normal_prev.xy)));

		// Reproject bent normal
		bent_normal_prev = mul(float3x3(ap.temporal.viewInv), bent_normal_prev);
		bent_normal_prev = mul(float3x3(ap.camera.view), bent_normal_prev);

		// Depth rejection
		float view_norm = rlength(pos_view);
		float NoV = abs(dot(normal_view, pos_view))
			* view_norm; // NoV / sqrt(length(view_pos))
		float z0 = screen_to_view_depth(depth);
		float z1 = screen_to_view_depth(depth_prev);
		float depth_weight
			= exp2(-abs(z0 - z1) * DEPTH_REJECTION_STRENGTH * NoV * view_norm);

		// Offcenter rejection from Jessie, which is originally by Zombye
		// Reduces blur in motion
		float2 pixel_offset = 1.0
			- abs(2.0
					  * frac(
						  floor(0.5 * ap.game.renderSize) * pos_prev_screen.xy
					  )
				  - 1.0);
		float offcenter_rejection = sqrt(pixel_offset.x * pixel_offset.y)
				* OFFCENTER_REJECTION_STRENGTH
			+ (1.0 - OFFCENTER_REJECTION_STRENGTH);

		pixel_age
			*= depth_weight * offcenter_rejection * float(depth_prev != 0.0);

		pixel_age = min(pixel_age, MAX_ACCUMULATED_FRAMES);
		float history_weight = pixel_age / (pixel_age + 1.0);

		// Blend with history.
		if (all(isfinite(gtao_output_prev))) {
			gtao_result.ao = lerp(
				gtao_result.ao,
				max0(gtao_output_prev.x),
				history_weight
			);
			gtao_result.ambient_sss = lerp(
				gtao_result.ambient_sss,
				max0(gtao_output_prev.y),
				history_weight
			);
			gtao_result.bent_normal = slerp(
				gtao_result.bent_normal,
				normalize(bent_normal_prev),
				history_weight
			);
		}
		if (all(isfinite(rsm_output_prev))) {
			rsm = lerp(rsm, max0(rsm_output_prev), history_weight);
		}
	}

	tex_gtao_output_current[icoord] = float4(
		gtao_result.ao,
		gtao_result.ambient_sss,
		gtao_result.bent_normal.xy
	);
	if (userSettings.RSM_ENABLED) {
		tex_rsm_output_current[icoord] = rsm;
	}
	tex_qres_temporal_data_current[icoord] = float2(pixel_age + 1.0, depth);
}


