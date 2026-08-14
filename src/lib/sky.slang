public module sky;

import lib.atmosphere;
import lib.util.math;
import settings;

internal Texture2D<float3> tex_atmosphere_sky_view;
internal Texture2D<float3> tex_atmosphere_transmittance_lut;

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

float3 calculate_sky_radiance(float3 dir) {
	float3 radiance = float3(0.0);
	float3 atmosphere_scattering
		= atmosphere.lookup_sky_radiance(tex_atmosphere_sky_view, dir);
	float3 atmosphere_transmittance = atmosphere.lookup_transmittance(
		atmosphere.EARTH_PARAMS,
		tex_atmosphere_transmittance_lut,
		atmosphere.camera_pos(),
		dir
	);

	// Space.
	radiance += calculate_sun_radiance(dir);

	// Atmosphere.
	radiance = radiance * atmosphere_transmittance + atmosphere_scattering;

	return radiance;
}


