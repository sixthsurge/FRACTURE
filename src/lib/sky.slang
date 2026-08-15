public module sky;

import aperture;
import lib.atmosphere;
import lib.util.color;
import lib.util.math;
import lib.util.random;
import lib.util.ray_sphere_intersection;
import settings;

internal Texture2D<float3> tex_atmosphere_sky_view;
internal Texture2D<float3> tex_atmosphere_multiscatter_lut;
internal Texture2D<float3> tex_atmosphere_transmittance_lut;
internal Texture2D<float3> tex_galaxy;

float3 calculate_sun_radiance(float3 dir) {
	float nu = dot(dir, buf_global.sun_dir_world);
	float sun_angular_radius = userSettings.SUN_ANGULAR_RADIUS * (TAU / 360.0f);

	// Limb darkening model from
	// http://www.physics.hmc.edu/faculty/esin/a101/limbdarkening.pdf.
	const float3 alpha = float3(0.429, 0.522, 0.614);
	float center_to_edge = max0(sun_angular_radius - fast_acos(nu));
	float3 limb_darkening
		= pow(float3(1.0 - pow2(1.0 - center_to_edge)), 0.5 * alpha);

	return buf_global.sun_radiosity
		/ cone_angle_to_solid_angle(sun_angular_radius)
		* step(0.0, center_to_edge) * limb_darkening;
}

float4 calculate_moon_radiance_and_opacity(float3 dir) {
	const float MOON_PHASE = 3; // FIXME change when Ap adds moon phase.

	float moon_angular_radius
		= userSettings.MOON_ANGULAR_RADIUS * (TAU / 360.0f);

	const float angle = 0.7;
	const float2x2 rot
		= float2x2(cos(angle), sin(angle), -sin(angle), cos(angle));

	// Cut out the moon disc.
	float MoV = dot(dir, buf_global.moon_dir_world);
	if (MoV < cos(moon_angular_radius)) {
		return float4(0.0);
	}

	// Find distance from center to edge.
	float dist = saturate(fast_acos(MoV) / moon_angular_radius);

	// Transform the coordinate space such that z is parallel to moon_dir
	float3 tangent = buf_global.moon_dir_world.y == 1.0
		? float3(1.0, 0.0, 0.0)
		: normalize(cross(float3(0.0, 1.0, 0.0), buf_global.moon_dir_world));
	float3 bitangent = normalize(cross(tangent, buf_global.moon_dir_world));
	float3x3 tbn = float3x3(tangent, bitangent, buf_global.moon_dir_world);

	// Vector from ray dir to moon dir.
	float2 offset = mul(tbn, dir - buf_global.sun_dir_world).xy;
	offset = fract(offset + 0.5);

	float moon_texture = 1.0; // TODO

	// Find the distance to the moon if it were 1 unit away, and its normal.
	float moon_dist
		= intersect_sphere(-buf_global.moon_dir_world, dir, moon_angular_radius)
			  .x;
	float3 moon_normal = normalize(dir * moon_dist - buf_global.moon_dir_world);

	// Get light direction which orbits around moon
	float light_angle = 0.125 * TAU * float(MOON_PHASE);
	float3 left_dir = normalize(cross(float3(0.0, 1.0, 0.0), dir));
	float3 light_dir = cos(light_angle) * -dir + sin(light_angle) * left_dir;
	float moon_shadow = dampen(max0(dot(moon_normal, light_dir)));

	float edge_glow = pow2(pow2(pow2(dist)));

	float3 color = max(moon_shadow * (1.0 + 4.0 * edge_glow),
					   0.5 * (0.01 + 0.02 * edge_glow))
		* moon_texture;
	color = buf_global.moon_radiosity
		/ cone_angle_to_solid_angle(moon_angular_radius) * pow2(color);
	return float4(color, 1.0);
}

// The method for the stars is based on https://www.shadertoy.com/view/Md2SR3,
// but the code is not based on it.

float3 unstable_star_field(float2 coord, float star_threshold) {
	const float min_temp = 4500.0;
	const float max_temp = 8500.0;

	float4 noise = hash4(coord);

	float star = linstep(star_threshold, 1.0, noise.x);
	star = pow16(star);

	float temp = lerp(min_temp, max_temp, noise.y);
	float3 color = blackbody(temp);

	const float twinkle_speed = 2.0;
	float twinkle_amount = noise.z;
	float twinkle_offset = TAU * noise.w;
	star *= 1.0
		- twinkle_amount
			* cos(ap.timing.timeElapsed * twinkle_speed + twinkle_offset);

	return 0.0025 * star * color;
}

// Stabilizes the star field by sampling at the four neighboring integer
// coordinates and interpolating
float3 stable_star_field(float2 coord, float star_threshold) {
	coord = abs(coord) + 33.3 * step(0.0, coord);
	float2 i, f = modf(coord, i);

	f.x = cubic_smooth(f.x);
	f.y = cubic_smooth(f.y);

	return unstable_star_field(i + float2(0.0, 0.0), star_threshold)
		* (1.0 - f.x) * (1.0 - f.y)
		+ unstable_star_field(i + float2(1.0, 0.0), star_threshold) * f.x
		* (1.0 - f.y)
		+ unstable_star_field(i + float2(0.0, 1.0), star_threshold) * f.y
		* (1.0 - f.x)
		+ unstable_star_field(i + float2(1.0, 1.0), star_threshold) * f.x * f.y;
}

float3 calculate_star_radiance(float3 dir, float galaxy_luminance) {
	// Adjust star threshold so that brightest stars appear first
	float star_threshold = 0.99 - 0.08 * linstep(0.1, 0.8, galaxy_luminance);

	// Project ray direction onto the plane
	float2 coord
		= dir.xy * rcp(abs(dir.z) + length(dir.xy)) + 41.21 * sign(dir.z);
	coord *= 900.0;

	return stable_star_field(coord, star_threshold);
}

float3 lookup_galaxy_texture(float3 dir) {
	float lon = atan2(dir.x, dir.z);
	float lat = fast_acos(-dir.y);

	return tex_galaxy.sampleLinear(float2(lon / TAU + 0.5, lat / PI));
}

atmosphere.AtmosphereParticipation
calculate_atmosphere_participation(float3 dir) {
	// Raymarch atmosphere if outside atmosphere boundary; otherwise lookup in
	// sky map.

	if (atmosphere.camera_pos().y
		< atmosphere.EARTH_PARAMS.atmosphere_radius()) {
		atmosphere.AtmosphereParticipation participation;
		participation.scattering
			= atmosphere.lookup_sky_radiance(tex_atmosphere_sky_view, dir);
		participation.transmittance = atmosphere.lookup_transmittance(
			atmosphere.EARTH_PARAMS,
			tex_atmosphere_transmittance_lut,
			atmosphere.camera_pos(),
			dir
		);
		participation.hit_planet
			= false; // Not needed as included in transmittance.
		return participation;
	}

	return atmosphere.calculate_scattering(
		atmosphere.EARTH_PARAMS,
		tex_atmosphere_transmittance_lut,
		tex_atmosphere_multiscatter_lut,
		atmosphere.camera_pos(),
		dir,
		none,
		atmosphere.light_sources()
	);
}

float3 calculate_sky_radiance(float3 dir) {
	float3 radiance = float3(0.0);
	// Use shadow view matrix to orient ray direction with the sun and moon.
	float3 space_dir = mul(float3x3(ap.celestial.view), dir);
	float3 galaxy = lookup_galaxy_texture(
		space_dir.zyx
	); // Swizzle to get a look I like at midnight.

	atmosphere.AtmosphereParticipation atmosphere_participation
		= calculate_atmosphere_participation(dir);

	// Space.
	radiance += calculate_sun_radiance(dir);
	radiance += srgb_eotf_inv(galaxy) * 0.0015;
	radiance += calculate_star_radiance(
		space_dir,
		dot(galaxy, LUMINANCE_WEIGHTS_REC709)
	);
	float4 moon = calculate_moon_radiance_and_opacity(dir);
	radiance = radiance * (1.0 - moon.a) + moon.rgb;
	radiance
		= select(atmosphere_participation.hit_planet, float3(0.0), radiance);

	// Atmosphere.
	radiance = atmosphere_participation.apply(radiance);

	return radiance;
}


