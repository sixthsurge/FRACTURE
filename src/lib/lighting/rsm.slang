public module rsm;

import aperture;
import lib.lighting.shadow;
import lib.util.color;
import lib.util.encoding;
import lib.util.math;
import lib.util.random;
import lib.util.sampling;
import settings;

internal Texture2DArray<float4> tex_shadow_color;

namespace rsm {
float3 calculate(float3 pos_scene, float3 normal_world, float2 dither) {
	if (!userSettings.RSM_ENABLED) {
		return float3(0.0);
	}

	const int STEP_COUNT = 8;

	float3 pos_shadow_view = transform(ap.celestial.view, pos_scene);
	float3 irradiance = float3(0.0);
	float3 light_dir_shadow_view
		= mul(float3x3(ap.celestial.view), buf_global.light_dir_world);
	float3 normal_shadow_view = mul(float3x3(ap.celestial.view), normal_world);

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
		float2 v = r2(i + STEP_COUNT * ap.timing.frameCounter, dither);
		float r = v.x;
		float theta = v.y * TAU;
		float s, c;
		sincos(theta, s, c);
		float2 offset = (userSettings.RSM_RADIUS * r) * float2(c, s);

		float3 sample_pos_shadow_view = pos_shadow_view + float3(offset, 0.0);

		Optional<shadow.PositionAndCascade> sample_pos_proj
			= shadow.project_shadow(sample_pos_shadow_view);
		if (!sample_pos_proj.hasValue) {
			continue;
		}
		float3 pos_shadow_screen = sample_pos_proj.value.pos_shadow_screen;
		int cascade = sample_pos_proj.value.cascade;

		float reflector_depth
			= ap.shadow.sampleNearest(pos_shadow_screen.xy, cascade);
		float4 color_and_normal = tex_shadow_color.Sample(
			apt_nearestSampler,
			float3(pos_shadow_screen.xy, cascade)
		);

		float3 reflector_normal
			= decode_octahedral(unpack_unorm_arb(
									uint(color_and_normal.w * 255.0),
									uint4(4, 4, 0, 0)
			)
									.xy);
		reflector_normal = mul(float3x3(ap.celestial.view), reflector_normal);

		float4 reflector_pos_shadow_view = project(
			celestial_projection_inv[cascade],
			float3(pos_shadow_screen.xy * 2.0 - 1.0, reflector_depth)
		);
		reflector_pos_shadow_view.xyz /= reflector_pos_shadow_view.w;

		// Vector from the fragment to the reflector.
		float3 reflector_vector
			= reflector_pos_shadow_view.xyz - pos_shadow_view;
		float dist_sq = max(0.01, length_squared(reflector_vector));

		// Result is scaled by r, to account for sample density towards the edge
		// of the disc being lower.
		irradiance += r * srgb_eotf_inv(color_and_normal.xyz)
			* max0(dot(reflector_normal, light_dir_shadow_view))
			* max0(-dot(reflector_vector, reflector_normal))
			* max0(dot(reflector_vector, normal_shadow_view))
			/ (dist_sq * dist_sq * PI * PI);
	}

	return irradiance
		* (PI * PI * pow2(userSettings.RSM_RADIUS) * rcp(float(STEP_COUNT)));
}
}


