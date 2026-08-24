import aperture;
import lib.util.encoding;
import lib.util.math;
import lib.util.random;
import lib.util.sampling;
import lib.util.space_conversion;

RWTexture2D<float3> tex_rsm_output_filtered;
Texture2D<float3> tex_rsm_output_raw;
Texture2D<float4> tex_qres_temporal_data_current;
Texture2D<float> tex_blue_noise;

float3 input_curve(float3 s) { return sqrt(s); }

float3 input_curve_inv(float3 s) { return pow2(s); }

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID) {
	int w, h;
	tex_rsm_output_filtered.GetDimensions(w, h);
	float3 value_center = tex_rsm_output_raw[icoord];
	float4 data = tex_qres_temporal_data_current[icoord];

	float2 ncoord = (float2(icoord) + 0.5) / float2(w, h);

	float pixel_age = data.x;
	float depth = data.y;
	if (depth == 0.0) {
		tex_rsm_output_filtered[icoord] = float3(0.0);
		return;
	}

	float lin_z = screen_to_view_depth(depth);
	float3 normal_world = decode_octahedral(data.zw);

	float3 pos_screen = float3(ncoord, depth);
	float3 pos_scene = view_to_scene(screen_to_view(pos_screen));
	float rcp_view_dist = rlength(pos_scene);
	float3 dir_world = pos_scene * rcp_view_dist;
	float NoV = dot(dir_world, normal_world);

	float3 value_sum = input_curve(value_center);
	float weight_sum = 1.0;
	float rotation = r1(ap.timing.frameCounter) * TAU;
	float radius = max(0.05 / pow2(pixel_age), 0.01);
	const int STEP_COUNT = 8;

	[unroll]
	for (int i = 0; i < STEP_COUNT; ++i) {
		float2 offset = sample_vogel_disc(i, STEP_COUNT, rotation);
		float2 sample_ncoord = saturate(ncoord + offset * radius);
		int2 sample_icoord = int2(sample_ncoord * float2(w, h));

		float4 data = tex_qres_temporal_data_current[sample_icoord];
		float3 value = tex_rsm_output_raw[sample_icoord];

		float distance_weight = exp2(-0.1 * length(offset) * (pixel_age));

		float sample_depth = data.y;
		float3 sample_normal_world = decode_octahedral(data.zw);

		float normal_weight
			= pow16(max0(dot(normal_world, sample_normal_world)));
		float depth_weight = exp2(
			-16.0 * abs(NoV)
			* abs(
				lin_z - screen_to_view_depth(sample_depth)

			)
			* min1(rcp_view_dist)
		);

		float weight = normal_weight * depth_weight * distance_weight;
		value_sum += input_curve(value) * weight;
		weight_sum += weight;
	}

	tex_rsm_output_filtered[icoord] = input_curve_inv(value_sum / weight_sum);
}


