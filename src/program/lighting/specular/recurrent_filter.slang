import aperture;
import lib.lighting.specular;
import lib.surface.gbuffer_packing;
import lib.util.encoding;
import lib.util.math;
import lib.util.random;
import lib.util.sampling;
import lib.util.space_conversion;

import lib.util.debug;

RWTexture2D<float4> tex_specular_output_blurred;
Texture2D<uint4> tex_gbuffer_opaque;
Texture2D<float4> tex_specular_output_raw;
Texture2D<float4> tex_specular_temporal_data;
Texture2D<float> tex_noise_blue;

float3 input_curve(float3 s) { return sqrt(sqrt(s)); }

float3 input_curve_inv(float3 s) { return pow4(s); }

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID) {
	int w, h;
	tex_specular_output_blurred.GetDimensions(w, h);
	if (any(icoord >= int2(w, h))) {
		return;
	}

	float2 output_pixel_size = rcp(float2(w, h));
	int2 fullres_icoord = int2(
		float2(icoord) * (float2(ap.game.renderSize) * output_pixel_size)
	);

	let center = specular.TemporalData.load_current(icoord);
	let depth = ap.depth[fullres_icoord];

	float2 ncoord = (float2(icoord) + 0.5) / float2(w, h);

	if (center.depth == 0.0) {
		tex_specular_output_blurred[icoord] = float4(0.0);
		return;
	}

	float lin_z = screen_to_view_depth(center.depth);
	float3 normal_world = decode_octahedral(center.normal_enc);

	float3 pos_screen
		= float3((fullres_icoord + 0.5) / ap.game.renderSize, depth);
	float3 pos_scene = view_to_scene(screen_to_view(pos_screen));
	float rcp_view_dist = min1(rlength(pos_scene));
	float3 dir_world = pos_scene * rcp_view_dist;

	float3 value_sum = input_curve(center.reflection_over_fresnel);
	float weight_sum = 1.0;
	float rotation = r1(ap.timing.frameCounter) * TAU;
	float radius = clamp(
		2.0 * sqrt(rcp_view_dist) * pow2(center.roughness)
			/ (center.pixel_age + 1.0),
		0.005,
		0.25,
	);
	const int STEP_COUNT = 32;

	float3 flat_normal = normalize(cross(ddx(pos_scene), ddy(pos_scene)));
	float NoV = dot(dir_world, flat_normal);

	[unroll]
	for (int i = 0; i < STEP_COUNT; ++i) {
		float2 offset = sample_vogel_disc(i, STEP_COUNT, rotation);
		float2 sample_ncoord = saturate(ncoord + offset * radius);
		int2 sample_icoord = int2(sample_ncoord * float2(w, h));
		if (any(clamp(sample_icoord, int2(0), int2(w, h) - 1)
				!= sample_icoord)) {
			continue;
		}

		let sample = specular.TemporalData.load_current(sample_icoord);

		float distance_weight = exp2(-0.1 * length(offset));

		float normal_weight = exp2(
			-256.0
			* (1.0
			   - max0(dot(normal_world, decode_octahedral(sample.normal_enc))))
			* abs(NoV) * (sqrt(rcp_view_dist) * 0.5 + 0.5)
		);
		float depth_weight = exp2(
			-16.0 * abs(NoV) * abs(lin_z - screen_to_view_depth(sample.depth))
			* rcp_view_dist
		);
		float roughness_weight
			= exp2(-16.0 * abs(center.roughness - sample.roughness));

		float weight = max0(
			normal_weight * depth_weight * distance_weight * roughness_weight
		);
		value_sum += input_curve(max0(sample.reflection_over_fresnel)) * weight;
		weight_sum += weight;
	}

	tex_specular_output_blurred[icoord]
		= float4(input_curve_inv(value_sum / weight_sum), center.pixel_age);
}


