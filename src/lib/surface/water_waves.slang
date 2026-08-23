public module water_waves;

import aperture;
import lib.util.math;

internal Texture2D<float> tex_worley_noise_2d;
internal SamplerState sampler_linear_repeat;

interface IWaterWaves {
	associatedtype Params;

	static Params init_params(
		float3x3 tbn,
		float3 dir_world,
		float3 flat_normal_world,
		float skylight
	);

	static float amplitude(Params params);

	// Return a depth value on 0-1, which will be scaled by the amplitude.
	static float calculate_depth(Params params, float2 coord);

	static float3 calculate_normal(Params params, float2 coord) {
		const float DELTA = 0.1;
		float height_0 = calculate_depth(params, coord);
		float height_1 = calculate_depth(params, coord + float2(DELTA, 0.0));
		float height_2 = calculate_depth(params, coord + float2(0.0, DELTA));

		return normalize(float3(
			height_1 - height_0,
			height_2 - height_0,
			DELTA * rcp(amplitude(params))
		));
	}

	static float3
	calculate_parallax(Params params, float3 pos_tangent, float3 dir_tangent) {
		const int STEP_COUNT = 4;

		float2 ray_pos = pos_tangent.xy;
		float2 ray_step = dir_tangent.xy * rcp(-dir_tangent.z)
			* amplitude(params) * rcp(float(STEP_COUNT));

		float depth_value = calculate_depth(params, ray_pos);
		float depth_march = 0.0;
		float depth_previous;

		for (int i = 0; i < STEP_COUNT && depth_march < depth_value; ++i) {
			ray_pos += ray_step;
			depth_previous = depth_value;
			depth_value = calculate_depth(params, ray_pos);
			depth_march += rcp(float(STEP_COUNT));
		}

		// Interpolation step.

		float depth_before
			= depth_previous - depth_march + rcp(float(STEP_COUNT));
		float depth_after = depth_value - depth_march;

		ray_pos = lerp(
			ray_pos,
			ray_pos - ray_step,
			depth_after / (depth_after - depth_before)
		);

		return float3(
			ray_pos,
			pos_tangent.z
				+ dir_tangent.z
					* max_of(abs(ray_pos - pos_tangent.xy) / dir_tangent.xy)
		);
	}
}

struct GerstnerWaves : IWaterWaves {
	struct Params {
		float2 wave_dir;
		float2x2 wave_rot;
		float t;
		float distance_falloff;
		bool underside;
	}

	static Params init_params(
		float3x3 tbn,
		float3 dir_world,
		float3 flat_normal_world,
		float skylight
	) {
		const float SPEED_STILL = 0.5;
		const float SPEED_FLOWING = 0.7;
		const float ANGLE = 30.0 * DEGREE;

		Optional<float2> flow_dir = none;
		if (abs(flat_normal_world.y) < 0.99) {
			flow_dir
				= -normalize(mul(float2x3(tbn[0], tbn[1]), flat_normal_world));
		}

		Params params;
		params.t = (flow_dir.hasValue ? SPEED_FLOWING : SPEED_STILL)
			* ap.timing.timeElapsed;

		params.wave_dir = flow_dir.orElse(float2(cos(ANGLE), sin(ANGLE)));
		params.wave_rot = flow_dir.hasValue
			? float2x2(1.0)
			: float2x2(
				  cos(GOLDEN_ANGLE),
				  sin(GOLDEN_ANGLE),
				  -sin(GOLDEN_ANGLE),
				  cos(GOLDEN_ANGLE)
			  );

		params.distance_falloff
			= dampen(linstep(0.0, 0.2, abs(dot(flat_normal_world, dir_world))));
		params.underside = flat_normal_world.y < EPS;

		return params;
	}

	static float amplitude(Params params) {
		return 0.2 * params.distance_falloff;
	}

	static float calculate_depth(Params params, float2 coord) {
		// Parameters

		const int ITERATIONS = 3;

		// Gerstner waves
		const float WAVE_FREQUENCY = 0.5;
		const float PERSISTENCE = 0.5;
		const float LACUNARITY = 1.7;

		// Noise
		const float NOISE_FREQUENCY = 0.007;
		const float NOISE_STRENGTH = 2.0;

		// Reciprical of sum of amplitudes of all waves
		// This is a geometric series with initial value of 1 and common ratio
		// of `persistence`.
		const float AMPLITUDE_NORMALIZATION_FACTOR
			= (1.0 - PERSISTENCE) / (1.0 - pow(PERSISTENCE, float(ITERATIONS)));

		// Sample noise textures first (latency hiding).

		float[ITERATIONS] wave_noise;
		float2 noise_coord
			= (coord + float2(0.0, 0.25 * params.t)) * NOISE_FREQUENCY;
		for (uint i = 0u; i < ITERATIONS; ++i) {
			wave_noise[i] = tex_worley_noise_2d.Sample(
				sampler_linear_repeat,
				noise_coord
			);
			noise_coord *= 2.5;
		}

		// Calculate wave height.

		float height = 0.0;
		float amplitude_sum = 0.0;

		float wave_length = 1.0;
		float amplitude = 1.0;
		float frequency = WAVE_FREQUENCY;

		float2 wave_dir = params.wave_dir;

		for (uint i = 0u; i < ITERATIONS; ++i) {
			height += gerstner_wave(
						  coord * frequency,
						  wave_dir,
						  params.t,
						  wave_noise[i] * NOISE_STRENGTH,
						  wave_length
					  )
				* amplitude;

			amplitude *= PERSISTENCE;
			frequency *= LACUNARITY;
			wave_length *= 1.5;

			wave_dir = mul(params.wave_rot, wave_dir);
		}

		height *= AMPLITUDE_NORMALIZATION_FACTOR;
		return select(params.underside, height, 1.0 - height);
	}

	internal static float gerstner_wave(
		float2 coord,
		float2 wave_dir,
		float t,
		float noise,
		float wavelength
	) {
		// Gerstner wave function from Belmu in #snippets, modified.
		const float G = 9.8;

		float k = TAU / wavelength;
		float w = sqrt(G * k);

		float x = w * t - k * (dot(wave_dir, coord) + noise);

		return pow2(sin(x) * 0.5 + 0.5);
	}
}

typedef GerstnerWaves WaterWaves;


