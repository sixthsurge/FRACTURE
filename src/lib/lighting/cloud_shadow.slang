module cloud_shadow;

import aperture;
import lib.atmospherics.atmosphere;
import lib.atmospherics.clouds;
import lib.toggles;
import lib.util.filtering;
import lib.util.math;
import settings;

namespace cloud_shadow {
public static const float EXTENT = 256.0;

public float2 shadow_view_to_cloud_shadow_space(float3 shadow_view_pos) {
	float2 cloud_shadow_pos = shadow_view_pos.xy / EXTENT;
	cloud_shadow_pos /= 1.0 + length(cloud_shadow_pos);
	cloud_shadow_pos = cloud_shadow_pos * 0.5 + 0.5;

	return cloud_shadow_pos;
}

public float2 project(float3 scene_pos) {
	return shadow_view_to_cloud_shadow_space(
		transform(ap.celestial.view, scene_pos)
	);
}

public float3 unproject(float2 cloud_shadow_pos) {
	cloud_shadow_pos = cloud_shadow_pos * 2.0 - 1.0;
	cloud_shadow_pos /= 1.0 - length(cloud_shadow_pos);

	float3 shadow_view_pos = float3(cloud_shadow_pos * EXTENT, 1.0);

	return transform(ap.celestial.viewInv, shadow_view_pos);
}

public float sample(Texture2D<float> cloud_shadow_map, float3 pos_scene) {
	float2 cloud_shadow_pos = project(pos_scene);
	if (any(saturate(cloud_shadow_pos) != cloud_shadow_pos)) {
		return 1.0;
	}

	// Fade out cloud shadows when:
	//  - The fragment is above the cloud layer.
	//  - The sun is near the horizon.
	float r = (clouds.EARTH_RADIUS - atmosphere.SEA_LEVEL) + pos_scene.y
		+ ap.camera.position.y;
	float altitude_fraction
		= linstep(clouds.VOLUME_INNER_RADIUS, clouds.VOLUME_OUTER_RADIUS, r);
	float cloud_shadow_fade = userSettings.CLOUD_SHADOW_INTENSITY
		* smoothstep(0.05, 0.15, buf_global.light_dir_world.y)
		* saturate(1.0 - altitude_fraction);

	return cloud_shadow_map.sample_bicubic(cloud_shadow_pos, 0).x
		* cloud_shadow_fade
		+ (1.0 - cloud_shadow_fade);
}
}


