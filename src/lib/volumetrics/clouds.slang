module clouds;

import aperture;
import lib.buffer.sky_sh;
import lib.util.math;
import lib.util.random;
import lib.util.phase_functions;
import lib.util.ray_sphere_intersection;
import lib.util.sampling;
import lib.volumetrics.atmosphere;
import settings;

namespace clouds {
Texture2D<float3> tex_atmosphere_transmittance;
Texture2D<half> tex_noise_perlin_worley_2d;
Texture3D<half> tex_noise_worley_bubbly_3d;
Texture3D<half> tex_noise_worley_swirley_3d;
SamplerState sampler_linear_repeat;
ConstantBuffer<SkyShBuffer> buf_sky_sh;

static const float EARTH_RADIUS = 6371000.0;
static const float VOLUME_ALTITUDE = 1000.0;
static const float VOLUME_THICKNESS = 2400.0;

static const float VOLUME_INNER_RADIUS = EARTH_RADIUS + VOLUME_ALTITUDE;
static const float VOLUME_OUTER_RADIUS = VOLUME_INNER_RADIUS + VOLUME_THICKNESS;
static const float DENSITY_SCALE = 0.2;
static const float MAX_RAY_LENGTH = 50000.0;

public struct CloudsRenderParams {
	public int primary_step_count;
	public int lighting_step_count;
	public int ambient_step_count;
	public bool dither_secondary_ray;
}

public static const CloudsRenderParams RENDER_PARAMS_MAIN = {
	32,
	6,
	2,
	true,
};

public static const CloudsRenderParams RENDER_PARAMS_SKY_VIEW = {
	16,
	4,
	2,
	false,
};

float powder_effect(float density, float nu) {
	float powder = PI * density / (density + 0.15);
	powder = lerp(powder, 1.0, 0.8 * pow2(nu * 0.5 + 0.5));

	return powder;
}

float calculate_density(float3 pos) {
	float altitude_fraction
		= linstep(VOLUME_INNER_RADIUS, VOLUME_OUTER_RADIUS, length(pos));
	half altitude_fraction_h = half(altitude_fraction);

	const float2 wind_vel = 10.0 * float2(cos(0.3), sin(0.3));
	float2 wind = wind_vel * buf_global.world_age;

	pos.xz += 0.01 * wind_vel * pos.y;
	half density = tex_noise_perlin_worley_2d.Sample(
		sampler_linear_repeat,
		0.00001 * (pos.xz + wind)
	);
	half coverage = tex_noise_perlin_worley_2d.Sample(
		sampler_linear_repeat,
		0.0000009 * (pos.xz + wind)
	);

	density = pow4(
		linstep(pow2(cubic_smooth(1.0h - 0.9h * coverage)), 1.0h, density)
	);

	density *= 1.0h - altitude_fraction_h;

	density -= pow4(tex_noise_worley_bubbly_3d.Sample(
				   sampler_linear_repeat,
				   (pos + 2.0 * float3(wind, 0.0).xzy) * 0.00019
			   ))
		* (dampen(saturate(1.0h - density)))
		* lerp(0.25h, 8.0h, pow4(altitude_fraction_h));

	density -= pow4(tex_noise_worley_bubbly_3d.Sample(
				   sampler_linear_repeat,
				   (pos + 4.0 * float3(wind, 0.0).xzy) * 0.0012
			   ))
		* 0.2h * clamp(0.0h, 0.2h, pow2(altitude_fraction_h))
		* dampen(max0(1.0h - density));

	density = max0(density);
	density = lift(density, lerp(8.0h, 40.0h, pow2(altitude_fraction_h)));

	return density * altitude_fraction;
}

float calculate_optical_depth(Ray ray, int step_count, float dither) {
	float optical_depth = 0.0;

	float2 dists = intersect_spherical_shell(
		ray.o,
		ray.d,
		VOLUME_INNER_RADIUS,
		VOLUME_OUTER_RADIUS
	);
	if (dists.y < 0.0) {
		return 1.0;
	}

	float ray_length = min(dists.y - dists.x, 5000.0);
	float step_length = ray_length / float(step_count);
	float t = dists.x + step_length * dither;
	for (int i = 0; i < step_count; ++i) {
		optical_depth
			+= calculate_density(ray.at(t)) * step_length * DENSITY_SCALE;
		t += step_length;
	}

	return optical_depth;
}

public struct RenderResult {
	public float3 scattering;
	public float transmittance;
	public float apparent_distance;

	public static RenderResult no_hit() {
		return RenderResult(float3(0.0), 1.0, MAX_RAY_LENGTH);
	}
}

public RenderResult
render(CloudsRenderParams params, Ray ray, float3 sky_radiance, float dither) {
	float2 dists = intersect_spherical_shell(
		ray.o,
		ray.d,
		VOLUME_INNER_RADIUS,
		VOLUME_OUTER_RADIUS
	);
	float planet = intersect_sphere(ray.o, ray.d, EARTH_RADIUS).x;
	if (planet > 0.0 && planet < dists.x) {
		return RenderResult.no_hit();
	}
	if (dists.y < 0.0) {
		return RenderResult.no_hit();
	}

	float step_length = min(dists.y - dists.x, MAX_RAY_LENGTH)
		/ float(params.primary_step_count);
	float t = dists.x + step_length * dither;

	float transmittance = 1.0;

	float3 pos_sum = float3(0.0);
	float w_sum = 0.0;

	bool moonlit = buf_global.sun_dir_world.y < -0.05;
	float3 light_dir
		= select(moonlit, buf_global.moon_dir_world, buf_global.sun_dir_world);
	float nu = dot(light_dir, ray.d);

	float3 direct_light = float3(0.0);
	float3 ambient_light = float3(0.0);

	for (int i = 0; i < params.primary_step_count; ++i) {
		float3 pos = ray.at(t);
		float density = calculate_density(pos);

		t += step_length;
		if (density < EPS) {
			continue;
		}

		float extinction = density * DENSITY_SCALE * step_length;

		float step_transmittance = exp(-extinction);
		float step_transmitted_fraction
			= (1.0 - step_transmittance) / max(extinction, EPS);

		float dither = select(params.dither_secondary_ray, hash1(pos), 0.5);
		float light_optical_depth = calculate_optical_depth(
			Ray(pos, light_dir),
			params.primary_step_count,
			dither,
		);
		float sky_optical_depth = calculate_optical_depth(
			Ray(pos,
				select(
					params.dither_secondary_ray,
					sample_cos_weighted_hemisphere(normalize(pos), hash2(pos)),
					float3(0.0, 1.0, 0.0)
				)),
			params.lighting_step_count,
			dither,
		);
		// Guess optical depth to the ground using altitude fraction and density
		// from this sample
		float altitude_fraction
			= linstep(VOLUME_INNER_RADIUS, VOLUME_OUTER_RADIUS, length(pos));
		float ground_optical_depth
			= lerp(density, 1.0, saturate(altitude_fraction * 2.0 - 1.0))
			* altitude_fraction * VOLUME_THICKNESS;

		float scatter_scale = 1.0;
		float anisotropy = 1.0;
		float powder = powder_effect(dampen(density), nu);

		float extinction_scale = 1.0;
		for (int so = 0; so < 4; ++so) {
			direct_light += scatter_scale * extinction
				* step_transmitted_fraction * transmittance
				* (exp(-extinction_scale * light_optical_depth)
				   * henyey_greenstein_phase(nu, 0.6 * anisotropy));
			ambient_light += scatter_scale * extinction
				* step_transmitted_fraction * transmittance
				* (ISOTROPIC_PHASE * buf_sky_sh.irradiance_up
					   * exp(-extinction_scale * sky_optical_depth)
				   + buf_global.celestial_light_irradiance
					   * float3(0.1, 0.1, 0.1) * ISOTROPIC_PHASE
					   * exp(-extinction_scale * ground_optical_depth)
					   * max0(buf_global.light_dir_world.y));
			scatter_scale *= 0.8 * powder;
			powder = lerp(powder, sqrt(powder), 0.5);
			extinction_scale *= 0.4;
			anisotropy *= 0.8;
		}
		pos_sum += pos * density;
		w_sum += density;

		transmittance *= step_transmittance;
	}

	float3 scattering = float3(0.0);
	float apparent_distance = MAX_RAY_LENGTH;
	if (w_sum > EPS) {
		float3 avg_pos = pos_sum / w_sum;
		float light_fade
			= linstep(0.0, 0.025, abs(buf_global.light_dir_world.y + 0.05));
		scattering = direct_light * light_fade
				* select(moonlit,
						 buf_global.moon_radiosity,
						 buf_global.sun_radiosity)
				* atmosphere.lookup_transmittance(
					atmosphere.EARTH_PARAMS,
					tex_atmosphere_transmittance,
					avg_pos,
					light_dir
				)
			+ ambient_light;
		float3 atmosphere_transmittance
			= atmosphere.calculate_transmittance_between_points_approx(
				atmosphere.EARTH_PARAMS,
				ray.o,
				avg_pos
			);
		scattering = lerp(
			sky_radiance * (1.0 - transmittance),
			scattering,
			atmosphere_transmittance
		);
		apparent_distance = distance(ray.o, avg_pos);
	}
	return RenderResult(scattering, transmittance, apparent_distance);
}

public float3 camera_pos() {
	return ap.camera.position + float3(0.0, EARTH_RADIUS, 0.0);
}
}


