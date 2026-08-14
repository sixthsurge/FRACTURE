// Implementation of "A Scalable and Production Ready Sky and Atmosphere
// Rendering Technique", Sébastien Hillaire.

public module atmosphere;

import aperture;
import lib.util.math;
import lib.util.phase_functions;
import lib.util.ray_sphere_intersection;
import lib.util.sampling;
import lib.util.space_conversion;

namespace atmosphere {
struct AtmosphereParameters {
	float planet_radius;
	float thickness;
	float mie_albedo;
	float mie_kn_energy;
	float2 scale_heights;
	float3 rayleigh_coeff;
	float3 mie_coeff;
	float3 ozone_coeff;
	float3 planet_albedo;

	float atmosphere_radius() { return planet_radius + thickness; }

	float2x3 scattering_coeff() {
		return float2x3(rayleigh_coeff, mie_coeff * mie_albedo);
	}

	float3x3 extinction_coeff() {
		return float3x3(rayleigh_coeff, mie_coeff, ozone_coeff);
	}
};

static const AtmosphereParameters EARTH_PARAMS = {
	6371e3, // Planet radius (m)
	110e3, // Atmosphere thickness (m)
	0.9, // Mie albedo
	1000.0, // Mie Klein-Nishina energy parameter
	float2(8.4e3, 1.25e3), // Rayleigh/mie scale height (m)
	float3(5.8, 13.6, 33.1) * 1e-6, // Rayleigh extinction coefficient (m^-1)
	float3(4.4) * 1e-6, // Mie extinction coefficient (m^-1)
	float3(0.65, 1.88, 0.085) * 1e-6, // Ozone extinction coefficient (m^-1)
	float3(0.015, 0.02, 0.05), // Planet albedo
};

static const float AERIAL_PERSPECTIVE_DEPTH_SCALE
	= 1e5; // meters divided by terrain scale.
static const float AERIAL_PERSPECTIVE_TERRAIN_SCALE = 3.0;

// Camera position in planet space.
float3 camera_pos() {
	return float3(
		0.0,
		EARTH_PARAMS.planet_radius
			+ ap.camera.position.y * AERIAL_PERSPECTIVE_TERRAIN_SCALE + 10.0,
		0.0
	);
}

struct LightSource {
	float3 irradiance;
	float3 direction;
};

float3 calculate_density(AtmosphereParameters params, float r) {
	float altitude = max0(r - params.planet_radius);
	float2 rm = exp(-altitude / params.scale_heights);

	// Source for ozone density curve: Jessie in shaderLABS.
	float altitude_km = altitude * 1e-3;
	float o1 = 12.5 * exp((1.0 / 8.0) * (0.0 - altitude_km));
	float o2 = 30.0
		* exp((1.0 / 80.0) * (18.0 - altitude_km) * (altitude_km - 18.0));
	float o3 = 75.0
		* exp((1.0 / 50.0) * (23.5 - altitude_km) * (altitude_km - 23.5));
	float o4 = 50.0
		* exp((1.0 / 150.0) * (30.0 - altitude_km) * (altitude_km - 30.0));
	float o = 7.428e-3 * (o1 + o2 + o3 + o4);

	return float3(rm, o);
}

float3 calculate_transmittance(
	AtmosphereParameters params,
	float3 ray_origin,
	float3 ray_dir
) {
	const int step_count = 32;

	float planet_dist
		= intersect_sphere(
			  ray_origin,
			  ray_dir,
			  params.planet_radius * (1.0 - EPS)
		)
			  .x;
	if (planet_dist >= 0.0) return float3(0.0);
	float ray_length
		= intersect_sphere(ray_origin, ray_dir, params.atmosphere_radius()).y;

	float3 ray_step = ray_dir * ray_length / float(step_count - 1);
	float3 ray_pos = ray_origin;

	// Integrating extinction using trapezium rule.
	float3 airmass = float3(0.0);
	for (int i = 0; i < step_count; ++i) {
		float w = (i == 0 || i == step_count - 1) ? 0.5 : 1.0;
		airmass += w * calculate_density(params, length(ray_pos));
		ray_pos += ray_step;
	}
	airmass *= ray_length / float(step_count - 1);

	return exp(-mul(airmass, params.extinction_coeff()));
}

float3 lookup_transmittance(
	AtmosphereParameters params,
	Texture2D<float3> transmittance_lut,
	float3 ray_origin,
	float3 ray_dir
) {
	int w, h;
	transmittance_lut.GetDimensions(w, h);

	float r = length(ray_origin);
	if (r > params.atmosphere_radius()) {
		return intersect_sphere(ray_origin, ray_dir, params.atmosphere_radius())
					.x
				< 0
			? 1.0
			: 0.0;
	}

	float cos_zenith_angle = dot(ray_origin, ray_dir) / r;
	float2 uv = float2(
		cos_zenith_angle * 0.5 + 0.5,
		linstep(params.planet_radius, params.atmosphere_radius(), r)
	);
	uv = get_uv_from_unit_range(uv, float2(w, h));
	return transmittance_lut.sampleLinear(uv);
}

float3 calculate_transmittance_between_points(
	AtmosphereParameters params,
	Texture2D<float3> transmittance_lut,
	float3 a,
	float3 b
) {
	// Imagine the line between A and B. One end of this line will always go
	// into space.

	float3 p1; // point further from space.
	float3 p2; // point closer to space.
	if (dot(b, b) > dot(a, a)) {
		// A -> B -> space
		p1 = a;
		p2 = b;
	} else {
		// B -> A -> space
		p1 = b;
		p2 = a;
	}

	float3 dir_p1_to_p2 = normalize(p2 - p1);
	float3 transmittance_p1_to_space = lookup_transmittance(
		EARTH_PARAMS,
		transmittance_lut,
		p1,
		dir_p1_to_p2
	);
	float3 transmittance_p2_to_space = lookup_transmittance(
		EARTH_PARAMS,
		transmittance_lut,
		p2,
		dir_p1_to_p2
	);
	return transmittance_p1_to_space / transmittance_p2_to_space;
}

float3 calculate_planet_radiance<int LightSourceCount>(
	AtmosphereParameters params,
	float3 ray_origin,
	float3 ray_dir,
	LightSource lights[LightSourceCount]
) {
	// Treat planet as uniform lambertian sphere, only considering direct light.
	float planet_dist
		= intersect_sphere(
			  ray_origin,
			  ray_dir,
			  params.planet_radius * (1.0 - EPS)
		)
			  .x;
	if (planet_dist < 0.0) {
		return float3(0.0);
	}

	float3 surface_pos = ray_origin + ray_dir * planet_dist;
	float3 surface_normal = normalize(surface_pos);

	float3 irradiance = float3(0.0);
	for (int i = 0; i < LightSourceCount; ++i) {
		irradiance += lights[i].irradiance
			* saturate(dot(surface_normal, lights[i].direction));
	}
	return irradiance * params.planet_albedo / PI;
}

float2x3 calculate_2nd_order_scattering_and_f_ms(
	AtmosphereParameters params,
	Texture2D<float3> transmittance_lut,
	float3 ray_origin,
	float3 ray_dir,
	float3 light_dir
) {
	const int step_count = 8;

	float2 dists = intersect_spherical_shell(
		ray_origin,
		ray_dir,
		params.planet_radius * (1.0 - EPS),
		params.atmosphere_radius()
	);
	float ray_length = dists.y - dists.x;
	float step_length = ray_length / float(step_count);

	float3 ray_step = ray_dir * step_length;
	float3 ray_pos = ray_origin + ray_dir * dists.x + ray_step * 0.5;

	float2x3 scattering_coeff = params.scattering_coeff();
	float3x3 extinction_coeff = params.extinction_coeff();

	float3 transmittance = float3(1.0);
	float2x3 scattering = float2x3(0.0);
	float3 f_ms = float3(0.0);

	for (int i = 0; i < step_count; ++i) {
		float3 airmass
			= calculate_density(params, length(ray_pos)) * step_length;
		float3 step_optical_depth = mul(airmass, extinction_coeff);
		float3 step_transmittance = exp(-step_optical_depth);
		float3 visible_scattering = transmittance * (1.0 - step_transmittance)
			/ max(step_optical_depth, EPS);

		float3 light_transmittance = lookup_transmittance(
			params,
			transmittance_lut,
			ray_pos,
			light_dir
		);

		scattering[0] += airmass.x * visible_scattering * light_transmittance;
		scattering[1] += airmass.y * visible_scattering * light_transmittance;

		f_ms += mul(airmass.xy, scattering_coeff) * visible_scattering;

		ray_pos += ray_step;
		transmittance *= step_transmittance;
	}

	float3 radiance = float3(0.0);

	float3 inscattered_light = scattering[0] * scattering_coeff[0]
		+ scattering[1] * scattering_coeff[1];
	radiance += inscattered_light * ISOTROPIC_PHASE;

	radiance += transmittance
		* calculate_planet_radiance<1>(
					params,
					ray_origin,
					ray_dir,
					{ LightSource(float3(1.0), light_dir) }
		);

	return float2x3(radiance, f_ms);
}

float3 calculate_multiscatter_energy(
	AtmosphereParameters params,
	Texture2D<float3> transmittance_lut,
	float r,
	float cos_light_zenith_angle
) {
	const int sqrt_direction_samples = 5;

	float3 ray_origin = float3(0.0, r, 0.0);
	float3 light_dir = float3(
		0.0,
		cos_light_zenith_angle,
		sqrt(saturate(1.0 - pow2(cos_light_zenith_angle)))
	);

	// Integrating L_(2nd order) and f_ms.
	float3 L_2nd_order = float3(0.0);
	float3 f_ms = float3(0.0);
	for (int u = 0; u < sqrt_direction_samples; ++u) {
		for (int v = 0; v < sqrt_direction_samples; ++v) {
			float2 uv = (float2(u, v) + 0.5) / float(sqrt_direction_samples);
			float3 ray_dir = sample_uniform_sphere(uv);

			float2x3 pair = calculate_2nd_order_scattering_and_f_ms(
				params,
				transmittance_lut,
				ray_origin,
				ray_dir,
				light_dir
			);
			L_2nd_order += pair[0];
			f_ms += pair[1];
		}
	}
	L_2nd_order /= pow2(sqrt_direction_samples);
	f_ms /= pow2(sqrt_direction_samples);

	float3 F_ms = 1.0 / max(1.0 - f_ms, EPS);

	return L_2nd_order * F_ms;
}

float3 lookup_multiscatter_energy(
	AtmosphereParameters params,
	Texture2D<float3> multiscatter_lut,
	float3 ray_origin,
	float3 ray_dir
) {
	int w, h;
	multiscatter_lut.GetDimensions(w, h);

	float r = length(ray_origin);
	float cos_zenith_angle = dot(ray_origin, ray_dir) / r;
	float2 uv = float2(
		cos_zenith_angle * 0.5 + 0.5,
		linstep(params.planet_radius, params.atmosphere_radius(), r)
	);
	uv = get_uv_from_unit_range(uv, float2(w, h));
	return multiscatter_lut.sampleLinear(uv);
}

float3 calculate_scattering<int LightSourceCount>(
	AtmosphereParameters params,
	Texture2D<float3> transmittance_lut,
	Texture2D<float3> multiscatter_lut,
	float3 ray_origin,
	float3 ray_dir,
	Optional<float> max_distance,
	LightSource lights[LightSourceCount]
) {
	const int step_count = 20;

	float2 dists = intersect_spherical_shell(
		ray_origin,
		ray_dir,
		params.planet_radius,
		params.atmosphere_radius()
	);

	float ray_length = dists.y - dists.x;
	if (let d = max_distance) {
		// Limit the total raymarch distance, for aerial perspective
		// calculation.
		ray_length = min(ray_length, d);
	}
	float step_length = ray_length / float(step_count);

	float3 ray_step = ray_dir * step_length;
	float3 ray_pos = ray_origin + ray_dir * dists.x + ray_step * 0.5;

	float2x3 scattering_coeff = params.scattering_coeff();
	float3x3 extinction_coeff = params.extinction_coeff();

	float3 phase_rayleigh[LightSourceCount];
	float phase_mie[LightSourceCount];
	for (int light_index = 0; light_index < LightSourceCount; ++light_index) {
		LightSource light = lights[light_index];
		float cos_light_angle = dot(ray_dir, light.direction);
		phase_rayleigh[light_index] = rayleigh_phase(cos_light_angle);
		phase_mie[light_index]
			= klein_nishina_phase(cos_light_angle, params.mie_kn_energy);
	}

	float3 transmittance = float3(1.0);

	float2x3 scattering[LightSourceCount];
	for (int i = 0; i < LightSourceCount; ++i) {
		scattering[i] = float2x3(0.0);
	}

	for (int i = 0; i < step_count; ++i) {
		float3 airmass
			= calculate_density(params, length(ray_pos)) * step_length;
		float3 step_optical_depth = mul(airmass, extinction_coeff);
		float3 step_transmittance = exp(-step_optical_depth);
		float3 visible_scattering = transmittance * (1.0 - step_transmittance)
			/ max(step_optical_depth, EPS);

		for (int light_index = 0; light_index < LightSourceCount;
			 ++light_index) {
			LightSource light = lights[light_index];

			float3 light_transmittance = lookup_transmittance(
				params,
				transmittance_lut,
				ray_pos,
				light.direction
			);

			float3 multiscatter_energy = lookup_multiscatter_energy(
				params,
				multiscatter_lut,
				ray_pos,
				light.direction
			);

			scattering[light_index][0] += airmass.x * visible_scattering
				* (phase_rayleigh[light_index] * light_transmittance
				   + multiscatter_energy);

			scattering[light_index][1] += airmass.y * visible_scattering
				* (phase_mie[light_index] * light_transmittance
				   + multiscatter_energy);
		}

		ray_pos += ray_step;
		transmittance *= step_transmittance;
	}

	float3 radiance = float3(0.0);
	for (int light_index = 0; light_index < LightSourceCount; ++light_index) {
		LightSource light = lights[light_index];

		float3 inscattered_light
			= scattering[light_index][0] * scattering_coeff[0]
			+ scattering[light_index][1] * scattering_coeff[1];

		radiance += light.irradiance * inscattered_light;
	}
	if (!max_distance.hasValue) {
		// Don't render the planet when there is a max distance imposed, as this
		// means we are rendering aerial perspective.
		radiance += transmittance
			* calculate_planet_radiance(params, ray_origin, ray_dir, lights);
	}

	return radiance;
}

float3 lookup_aerial_perspective_scattering(
	Texture3D<float3> aerial_perspective_lut,
	float3 pos_screen
) {
	int w, h, d;
	aerial_perspective_lut.GetDimensions(w, h, d);

	pos_screen.z = saturate(
		screen_to_view_depth(pos_screen.z) / AERIAL_PERSPECTIVE_DEPTH_SCALE
	);
	pos_screen.z
		= sqrt(sqrt(pos_screen.z)); // Focus precision towards the view.
	pos_screen.z = get_uv_from_unit_range(pos_screen.z, d);
	return aerial_perspective_lut.Sample(apt_linearSampler, pos_screen);
}

float3 apply_aerial_perspective(
	Texture3D<float3> aerial_perspective_lut,
	Texture2D<float3> transmittance_lut,
	float3 pos_screen,
	float3 pos_scene,
	float3 radiance
) {
	float3 scattering = lookup_aerial_perspective_scattering(
		aerial_perspective_lut,
		pos_screen
	);

	float3 pos_planet
		= camera_pos() + pos_scene * AERIAL_PERSPECTIVE_TERRAIN_SCALE;
	float3 transmittance = calculate_transmittance_between_points(
		EARTH_PARAMS,
		transmittance_lut,
		pos_planet,
		camera_pos()
	);

	return radiance * transmittance + scattering;
}

float2 project_sky_view(float3 direction) {
	float2 projected_dir = normalize(direction.xz);

	float azimuth_angle = PI + atan2(projected_dir.x, -projected_dir.y);
	float altitude_angle = 0.5 * PI - fast_acos(direction.y);

	float2 coord;
	coord.x = azimuth_angle / TAU;
	coord.y = 0.5
		+ 0.5 * sign(altitude_angle)
			* sqrt((2.0 / PI) * abs(altitude_angle)); // Section 5.3

	return coord;
}

float3 unproject_sky_view(float2 coord) {
	// Non-linear mapping of altitude angle (See section 5.3 of the paper)
	coord.y = (coord.y < 0.5) ? -pow2(1.0 - 2.0 * coord.y)
							  : pow2(2.0 * coord.y - 1.0);

	float azimuth_angle = coord.x * TAU - PI;
	float altitude_angle = coord.y * (0.5 * PI);

	float altitude_sin, altitude_cos, azimuth_sin, azimuth_cos;
	sincos(altitude_angle, altitude_sin, altitude_cos);
	sincos(azimuth_angle, azimuth_sin, azimuth_cos);

	return float3(
		altitude_cos * azimuth_sin,
		altitude_sin,
		-altitude_cos * azimuth_cos
	);
}

float3 lookup_sky_radiance(Texture2D<float3> tex_sky_view, float3 ray_dir) {
	int w, h;
	tex_sky_view.GetDimensions(w, h);

	float2 uv = get_uv_from_unit_range(project_sky_view(ray_dir), float2(w, h));
	return tex_sky_view.sampleLinearLevel(uv, 0);
}
} // namespace atmosphere


