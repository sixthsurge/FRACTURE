public module celestial_shadow;

import aperture;

import lib.util.math;

extern static const bool SHADOWS_ENABLED;
extern static const int CASCADE_COUNT;

static const float shadow_depth_bias = 0.0005;

struct ShadowResult {
	float3 visibility;

	static ShadowResult no_hit() { return ShadowResult(float3(1.0)); }
}

// Get cascade and shadow screen space position from shadow view space position.
Optional<Tuple<int, float3>> project_shadow(float3 pos_shadow_view) {
	for (int cascade = 0; cascade < CASCADE_COUNT; ++cascade) {
		float4 pos_shadow_clip
			= project(ap.celestial.projection[cascade], pos_shadow_view);

		if (!isfinite(pos_shadow_clip.w) || abs(pos_shadow_clip.w) < EPS) {
			continue;
		}

		float3 pos_shadow_screen = pos_shadow_clip.xyz / pos_shadow_clip.w;
		pos_shadow_screen.xy = pos_shadow_screen.xy * 0.5 + 0.5;

		if (all(pos_shadow_screen >= float3(0.0)
				&& pos_shadow_screen <= float3(1.0))) {
			return makeTuple(cascade, pos_shadow_screen);
		}
	}

	return none;
}

ShadowResult get_celestial_shadow(float3 pos_scene) {
	float3 pos_shadow_view = transform(ap.celestial.view, pos_scene);

	int cascade;
	float3 pos_shadow_screen;
	if (let result = project_shadow(pos_shadow_view)) {
		cascade = result._0;
		pos_shadow_screen = result._1;
	} else {
		return ShadowResult.no_hit();
	}

	return ShadowResult(float3(ap.opaqueShadow.compare(
		pos_shadow_screen.xy,
		cascade,
		pos_shadow_screen.z - shadow_depth_bias
	)));
}


