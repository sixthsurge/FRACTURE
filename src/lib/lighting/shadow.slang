public module shadow;

import aperture;
import lib.util.math;
import lib.util.sampling;
import settings;

internal Texture2DArray<float3> tex_shadow_color;

namespace shadow {
internal static const float BLOCKER_SEARCH_RADIUS = 0.25;

struct Result {
	float3 visibility;
	float sss_depth;

	static Result no_hit() { return Result(float3(1.0), 0.0); }
}

float2 calculate_blocker_depth_and_sss_depth(
	float3 pos_shadow_screen,
	int cascade,
	float dither,
	bool has_sss
) {
	const int STEP_COUNT = 12;

	float radius = BLOCKER_SEARCH_RADIUS
		* ap.celestial.projection[cascade][0][0]
		* (0.5 + 0.5 * linstep(0.2, 0.4, buf_global.light_dir_world.y));

	float weight_sum = 0.0;
	float blocker_depth = 0.0;
	float sss_depth = 0.0;

	for (int i = 0; i < STEP_COUNT; ++i) {
		float2 offset = sample_vogel_disc(i, STEP_COUNT, dither * TAU) * radius;
		float2 uv = pos_shadow_screen.xy + offset;

		float depth = ap.shadow.sampleNearest(uv, cascade);
		float weight = step(depth, pos_shadow_screen.z);

		blocker_depth += weight * depth;
		weight_sum += weight;
		sss_depth += max0(pos_shadow_screen.z - depth);
	}

	blocker_depth = weight_sum == 0.0 ? 0.0 : blocker_depth / weight_sum;
	sss_depth /= abs(ap.celestial.projection[cascade][2].z) * float(STEP_COUNT);

	return float2(blocker_depth, sss_depth);
}

float3
pcf(float3 pos_shadow_screen, int cascade, float penumbra_size, float dither) {
	// penumbra_size > max_filter_radius: blur
	// penumbra_size < min_filter_radius: anti-alias (blur then sharpen)
	const int STEP_COUNT = 12;
	const float MIN_FILTER_RADIUS = 1.0 / userSettings.SHADOW_RESOLUTION;

	float filter_radius = max(penumbra_size, MIN_FILTER_RADIUS);

	float shadow = 0.0;

	float3 color = float3(0.0);

	// Perform the first 4 iterations and filter shadow color.
	for (int i = 0; i < 4; ++i) {
		float2 offset
			= sample_vogel_disc(i, STEP_COUNT, dither * TAU) * filter_radius;

		float2 uv = pos_shadow_screen.xy + offset;

		shadow += ap.opaqueShadow.compare(uv, cascade, pos_shadow_screen.z);

		float translucent_depth = ap.shadow.sampleNearest(uv, cascade);
		float3 translucent_color
			= tex_shadow_color.Sample(apt_nearestSampler, float3(uv, cascade));
		color += lerp(
			float3(1.0),
			translucent_color,
			step(translucent_depth, pos_shadow_screen.z)
		);
	}

	// Exit early if we are not on a penumbra.
	if (shadow > 4.0 - EPS) {
		return color * 0.25;
	} else if (shadow < EPS) {
		return float3(0.0);
	}

	// Perform remaining iterations on shadow colour only.
	for (int i = 4; i < STEP_COUNT; ++i) {
		float2 offset
			= sample_vogel_disc(i, STEP_COUNT, dither * TAU) * filter_radius;

		shadow += ap.opaqueShadow.compare(
			pos_shadow_screen.xy + offset,
			cascade,
			pos_shadow_screen.z
		);
	}

	shadow /= STEP_COUNT;

	// Sharpen shadow for small penumbra sizes.
	float sharpening_threshold
		= 0.4 * max0((MIN_FILTER_RADIUS - penumbra_size) / MIN_FILTER_RADIUS);
	shadow = linstep(sharpening_threshold, 1.0 - sharpening_threshold, shadow);

	return shadow * color * 0.25;
}

struct PositionAndCascade {
	float3 pos_shadow_screen;
	int cascade;
}

// Get cascade and shadow screen space position from shadow view space position.
Optional<PositionAndCascade> project_shadow(float3 pos_shadow_view) {
	for (int cascade = 0; cascade < userSettings.SHADOW_CASCADE_COUNT;
		 ++cascade) {
		float4 pos_shadow_clip
			= project(ap.celestial.projection[cascade], pos_shadow_view);

		if (!isfinite(pos_shadow_clip.w) || abs(pos_shadow_clip.w) < EPS) {
			continue;
		}

		float3 pos_shadow_screen = pos_shadow_clip.xyz / pos_shadow_clip.w;
		pos_shadow_screen.xy = pos_shadow_screen.xy * 0.5 + 0.5;

		if (all(pos_shadow_screen >= float3(0.0)
				&& pos_shadow_screen <= float3(1.0))) {
			return PositionAndCascade(pos_shadow_screen, cascade);
		}
	}

	return none;
}

Result calculate(
	float3 pos_scene,
	float3 flat_normal_world,
	float2 dither,
	bool has_sss
) {
	Result result = Result.no_hit();
	if (!userSettings.SHADOW_ENABLED) {
		return result;
	}

	// Immediate early exit if facing away from the sun and the material has no
	// SSS. If the material has SSS, we still need to run the blocker search to
	// get the SSS depth, then we can early exit.
	bool faces_sun = dot(flat_normal_world, buf_global.light_dir_world) > EPS;
	if (!faces_sun && !has_sss) {
		result.visibility = float3(0.0);
		return result;
	}

	pos_scene += 0.08 * flat_normal_world;

	float3 pos_shadow_view = transform(ap.celestial.view, pos_scene);

	int cascade;
	float3 pos_shadow_screen;
	if (let result = project_shadow(pos_shadow_view)) {
		cascade = result.cascade;
		pos_shadow_screen = result.pos_shadow_screen;
	} else {
		return result;
	}

	float2 blocker_search_result = calculate_blocker_depth_and_sss_depth(
		pos_shadow_screen,
		cascade,
		dither.x,
		true
	);
	result.sss_depth = blocker_search_result.y;

	// Now we can early exit for objects with SSS facing away from the sun.
	if (!faces_sun) {
		result.visibility = float3(0.0);
		return result;
	}

	float penumbra_size = 4.0 * (pos_shadow_screen.z - blocker_search_result.x)
		/ blocker_search_result.x;
	penumbra_size = min(penumbra_size, BLOCKER_SEARCH_RADIUS);
	penumbra_size
		*= ap.celestial.projection[cascade][0][0]; // Meters -> shadow unit.

	result.visibility
		= pcf(pos_shadow_screen, cascade, penumbra_size, dither.y);

	return result;
}
} // namespace shadow


