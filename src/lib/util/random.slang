public module random;

// http://extremelearning.com.au/unreasonable-effectiveness-of-quasirandom-sequences/

static const float PHI_1
	= 1.6180339887; // Golden ratio, solution to x^2 = x + 1
static const float PHI_2
	= 1.3247179572; // Plastic constant, solution to x^3 = x + 1
static const float PHI_3 = 1.2207440846; // Solution to x^4 = x + 1

float r1(int n, float seed) {
	const float alpha = 1.0 / PHI_1;
	return frac(seed + n * alpha);
}

float r1(int n) { return r1(n, 0.5); }

float r1_next(float u) {
	const float alpha = 1.0 / PHI_1;
	return frac(u + alpha);
}

float2 r2(int n, float2 seed) {
	const float2 alpha = 1.0 / float2(PHI_2, PHI_2 * PHI_2);
	return frac(seed + n * alpha);
}

float2 r2(int n) { return r2(n, float2(0.5)); }

float2 r2_next(float2 u) {
	const float2 alpha = 1.0 / float2(PHI_2, PHI_2 * PHI_2);
	return frac(u + alpha);
}

float3 r3(int n, float3 seed) {
	const float3 alpha
		= 1.0 / float3(PHI_3, PHI_3 * PHI_3, PHI_3 * PHI_3 * PHI_3);
	return frac(seed + n * alpha);
}

float3 r3(int n) { return r3(n, float3(0.5)); }

float3 r3_next(float3 u) {
	const float3 alpha
		= 1.0 / float3(PHI_3, PHI_3 * PHI_3, PHI_3 * PHI_3 * PHI_3);
	return frac(u + alpha);
}


