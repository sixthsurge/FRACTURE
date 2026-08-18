public module rsm;

import aperture;
import lib.lighting.shadow;
import lib.util.color;
import lib.util.encoding;
import lib.util.math;
import lib.util.sampling;
import settings;

internal Texture2DArray<float4> tex_shadow_color;

namespace rsm {
float3 calculate(float3 pos_scene, float3 normal_world, float2 dither) {
	if (!userSettings.RSM_ENABLED) {
		return float3(0.0);
	}

	const int STEP_COUNT = 12;

	float3 pos_shadow_view = transform(ap.celestial.view, pos_scene);
	float3 irradiance = float3(0.0);

	// From Kneemund.
	float4x4 celestial_projection_inv[userSettings.SHADOW_CASCADE_COUNT];
	for (uint cascade = 0; cascade < userSettings.SHADOW_CASCADE_COUNT;
		 cascade++) {
		float4x4 p = ap.celestial.projection[cascade];

		float rcp_xx = rcp(p[0].x);
		float rcp_yy = rcp(p[1].y);
		float rcp_zz = rcp(p[2].z);

		float4x4 inv;
		inv[0] = float4(rcp_xx, 0.0, 0.0, -p[0].w * rcp_xx);
		inv[1] = float4(0.0, rcp_yy, 0.0, -p[1].w * rcp_yy);
		inv[2] = float4(0.0, 0.0, rcp_zz, -p[2].w * rcp_zz);
		inv[3] = float4(0.0, 0.0, 0.0, 1.0);
		celestial_projection_inv[cascade] = inv;
	}

	for (int i = 0; i < STEP_COUNT; ++i) {
		float2 offset
			= sample_vogel_disc(i, STEP_COUNT, dither.x * TAU, dither.y)
			* userSettings.RSM_RADIUS;

		float3 sample_pos_shadow_view = pos_shadow_view + float3(offset, 0.0);

		Optional<shadow.PositionAndCascade> sample_pos_proj
			= shadow.project_shadow(sample_pos_shadow_view);
		if (!sample_pos_proj.hasValue) {
			continue;
		}
		float3 pos_shadow_screen = sample_pos_proj.value.pos_shadow_screen;
		int cascade = sample_pos_proj.value.cascade;

		float depth = ap.shadow.sampleNearest(pos_shadow_screen.xy, cascade);
		float4 color_and_normal = tex_shadow_color.Sample(
			apt_nearestSampler,
			float3(pos_shadow_screen.xy, cascade)
		);

		float3 normal = decode_octahedral(unpack_unorm_arb(
											  uint(color_and_normal.w * 255.0),
											  uint4(4, 4, 0, 0)
		)
											  .xy);
		normal = mul(float3x3(ap.celestial.view), normal);

		float4 depth_pos_shadow_view = project(
			celestial_projection_inv[cascade],
			float3(pos_shadow_screen.xy * 2.0 - 1.0, depth)
		);
		depth_pos_shadow_view.xyz /= depth_pos_shadow_view.w;

		float3 light_dir
			= normalize(depth_pos_shadow_view.xyz - pos_shadow_view);
		float NoL = max0(-dot(normal, light_dir));

		irradiance += srgb_eotf_inv(color_and_normal.xyz)
			* float(depth_pos_shadow_view.z < pos_shadow_view.z) * NoL
			/ (1.0
			   + userSettings.RSM_DISTANCE_FALLOFF
				   * length_squared(
					   depth_pos_shadow_view.xyz - pos_shadow_view.xyz
				   ));
	}

	return irradiance * rcp(float(STEP_COUNT));
}
}


