public module phase_functions;

import lib.util.math;

static const float ISOTROPIC_PHASE = 1.0 / (4.0 * PI);

float3 rayleigh_phase(float nu) {
	const float3 DEPOLARIZATION = float3(2.786, 2.842, 2.899) * 1e-2;
	const float3 GAMMA = DEPOLARIZATION / (2.0 - DEPOLARIZATION);
	const float3 K = 3.0 / (16.0 * PI * (1.0 + 2.0 * GAMMA));

	float3 phase = (1.0 + 3.0 * GAMMA) + (1.0 - GAMMA) * pow2(nu);

	return K * phase;
}

float henyey_greenstein_phase(float nu, float g) {
	float gg = g * g;

	return (ISOTROPIC_PHASE - ISOTROPIC_PHASE * gg)
		/ pow_3_over_2(1.0 + gg - 2.0 * g * nu);
}

// Far closer to an actual aerosol phase function than Henyey-Greenstein or
// Cornette-Shanks.
// Source: Jessie in shaderLABS.
float klein_nishina_phase(float nu, float e) {
	return e / (TAU * (e - e * nu + 1.0) * log(2.0 * e + 1.0));
}


