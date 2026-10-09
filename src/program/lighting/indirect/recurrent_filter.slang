import aperture;
import lib.surface.gbuffer_packing;
import lib.util.encoding;
import lib.util.math;
import lib.util.random;
import lib.util.sampling;
import lib.util.space_conversion;

import lib.util.debug;

RWTexture2D<float4> tex_indirect_output_blurred;
Texture2D<uint4> tex_gbuffer_opaque;
Texture2D<float4> tex_indirect_output_accumulated;
Texture2D<float4> tex_indirect_temporal_data_current;
Texture2D<float> tex_noise_blue;

float4 input_curve(float4 s) { return sqrt(s); }

float4 input_curve_inv(float4 s) { return pow2(s); }

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID) {
	int w, h;
	tex_indirect_output_blurred.GetDimensions(w, h);
	float2 output_pixel_size = rcp(float2(w, h));

	int2 fullres_icoord = int2(
		float2(icoord) * (float2(ap.game.renderSize) * output_pixel_size)
	);

	float4 value_center = tex_indirect_output_accumulated[icoord];
	float4 data = tex_indirect_temporal_data_current[icoord];
	uint4 gbuffer_packed = tex_gbuffer_opaque[fullres_icoord];

	float2 ncoord = (float2(icoord) + 0.5) / float2(w, h);

	float pixel_age = data.x;
	float depth = data.y;
	if (depth == 0.0) {
		tex_indirect_output_blurred[icoord] = float4(0.0);
		return;
	}

	float lin_z = screen_to_view_depth(depth);
	float3 normal_world = decode_octahedral(data.zw);

	float3 pos_screen = float3(ncoord, depth);
	float3 pos_scene = view_to_scene(screen_to_view(pos_screen));
	float rcp_view_dist = min1(rlength(pos_scene));
	float3 dir_world = pos_scene * rcp_view_dist;

	float4 value_sum = input_curve(value_center);
	float weight_sum = 1.0;
	float rotation = r1(ap.timing.frameCounter) * TAU;
	float radius = max(0.2 * rcp_view_dist / pow2(pixel_age), 0.005);
	const int STEP_COUNT = 32;

	OpaqueGbuffer gbuffer = OpaqueGbuffer.unpack(gbuffer_packed);
	float NoV = dot(dir_world, gbuffer.flat_normal_world);

	[unroll]
	for (int i = 0; i < STEP_COUNT; ++i) {
		float2 offset = sample_vogel_disc(i, STEP_COUNT, rotation);
		float2 sample_ncoord = saturate(ncoord + offset * radius);
		int2 sample_icoord = int2(sample_ncoord * float2(w, h));

		float4 data = tex_indirect_temporal_data_current[sample_icoord];
		float4 value = tex_indirect_output_accumulated[sample_icoord];

		float distance_weight = exp2(-0.1 * length(offset) * (pixel_age));

		float sample_depth = data.y;
		float3 sample_normal_world = decode_octahedral(data.zw);

		float normal_weight = exp2(
			-256.0 * (1.0 - max0(dot(normal_world, sample_normal_world)))
			* abs(NoV) * (sqrt(rcp_view_dist) * 0.5 + 0.5)
		);
		float depth_weight = exp2(
			-16.0 * abs(NoV) * abs(lin_z - screen_to_view_depth(sample_depth))
			* rcp_view_dist
		);

		float weight = normal_weight * depth_weight * distance_weight;
		value_sum += input_curve(value) * weight;
		weight_sum += weight;
	}

	tex_indirect_output_blurred[icoord]
		= input_curve_inv(value_sum / weight_sum);
}


