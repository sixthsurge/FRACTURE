public module phase_functions;

import lib.util.math;

static const float isotropic_phase = 1.0 / (4.0 * PI);

float3 rayleigh_phase(float nu) {
	const float3 depolarization = float3(2.786, 2.842, 2.899) * 1e-2;
	const float3 gamma = depolarization / (2.0 - depolarization);
	const float3 k = 3.0 / (16.0 * PI * (1.0 + 2.0 * gamma));

	float3 phase = (1.0 + 3.0 * gamma) + (1.0 - gamma) * pow2(nu);

	return k * phase;
}

// Far closer to an actual aerosol phase function than Henyey-Greenstein or
// Cornette-Shanks.
// Source: Jessie in shaderLABS.
float klein_nishina_phase(float nu, float e) {
	return e / (TAU * (e - e * nu + 1.0) * log(2.0 * e + 1.0));
}


