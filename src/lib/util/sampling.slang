public module sampling;

import lib.util.math;

float2 sample_vogel_disc(int step_index, int step_count, float rotation) {
	float r = sqrt(step_index + 0.5) / sqrt(float(step_count));
	float theta = step_index * GOLDEN_ANGLE + rotation;

	return r * float2(cos(theta), sin(theta));
}

float3 sample_uniform_sphere(float2 hash) {
	hash.x *= TAU;
	hash.y = 2.0 * hash.y - 1.0;
	return float3(
		float2(sin(hash.x), cos(hash.x)) * sqrt(1.0 - hash.y * hash.y),
		hash.y
	);
}

float3 sample_uniform_hemisphere(float3 vector, float2 hash) {
	float3 dir = sample_uniform_sphere(hash);
	return dot(dir, vector) < 0.0 ? -dir : dir;
}

// Source: https://amietia.com/lambertnotangent.html
float3 sample_cos_weighted_hemisphere(float3 vector, float2 hash) {
	float3 dir = normalize(sample_uniform_sphere(hash) + vector);
	return dot(dir, vector) < 0.0 ? -dir : dir;
}


