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

	float3 pos_shadow_view = transform(ap.celestial.view, pos_scene);
	float3 irradiance = float3(0.0);
	float3 light_dir_shadow_view
		= mul(float3x3(ap.celestial.view), buf_global.light_dir_world);
	float3 normal_shadow_view = mul(float3x3(ap.celestial.view), normal_world);

	// Find the highest possible cascade for all samples - the cascade of the
	// furthest possible point.
	float3 most_extreme_pos = pos_shadow_view
		+ float3(userSettings.RSM_RADIUS * normalize(pos_shadow_view.xy), 0.0);
	Optional<shadow.PositionAndCascade> proj
		= shadow.project_shadow(most_extreme_pos);
	if (!proj.hasValue) {
		return float3(0.0);
	}
	int cascade = proj.value.cascade;

	for (int i = 0; i < userSettings.RSM_STEP_COUNT; ++i) {
		float2 v = r2(
			i + userSettings.RSM_STEP_COUNT * ap.timing.frameCounter,
			dither
		);
		float r = v.x;
		float theta = v.y * TAU;
		float s, c;
		sincos(theta, s, c);
		float2 offset = (userSettings.RSM_RADIUS * r) * float2(c, s);

		float3 sample_pos_shadow_view = pos_shadow_view + float3(offset, 0.0);
		float3 sample_pos_shadow_screen
			= project_ortho(
				  ap.celestial.projection[cascade],
				  sample_pos_shadow_view
			  ) * 0.5
			+ 0.5;

		int2 shadow_icoord = int2(
			sample_pos_shadow_screen.xy * userSettings.SHADOW_RESOLUTION
		);
		float reflector_depth = ap.opaqueShadow[int3(shadow_icoord, cascade)];
		float4 color_and_normal
			= tex_shadow_color[int3(shadow_icoord, cascade)];

		float3 reflector_pos_shadow_view = project_ortho_inv(
			ap.celestial.projection[cascade],
			float3(sample_pos_shadow_screen.xy * 2.0 - 1.0, reflector_depth)
		);

		// Vector from the fragment to the reflector.
		float3 reflector_vector = reflector_pos_shadow_view - pos_shadow_view;
		float dist_sq = max(EPS, length_squared(reflector_vector));

		float3 reflector_normal
			= decode_octahedral(unpack_unorm_arb(
									uint(color_and_normal.w * 255.0),
									uint4(4, 4, 0, 0)
			)
									.xy);

		reflector_normal = mul(float3x3(ap.celestial.view), reflector_normal);
		// Result is scaled by r, to account for sample density towards the edge
		// of the disc being lower.
		irradiance += r * srgb_eotf_inv(color_and_normal.xyz)
			* max0(dot(reflector_normal, light_dir_shadow_view))
			* max0(-dot(reflector_vector, reflector_normal))
			* max0(dot(reflector_vector, normal_shadow_view))
			/ (dist_sq * dist_sq * PI * PI);
	}

	return irradiance
		* (PI * PI * pow2(userSettings.RSM_RADIUS)
		   * rcp(float(userSettings.RSM_STEP_COUNT)));
}
}


