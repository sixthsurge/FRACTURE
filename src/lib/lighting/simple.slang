public module lightmap;

// Simple block/sky lighting from the lightmap.

import lib.buffer.sky_sh;
import lib.util.math;
import lib.util.spherical_harmonics;
import settings;

ConstantBuffer<SkyShBuffer> buf_sky_sh;

float3 calculate_lightmap_blocklight(float3 brdf, float2 lightmap, float ao) {
	return pow3(lightmap.x) * float3(0.1, 0.06, 0.05) * ao * brdf;
}

float3 calculate_lightmap_skylight(
	float3 brdf,
	float2 lightmap,
	float3 bent_normal,
	float ao
) {
	float light_sq = pow2(lightmap.y);
	return brdf
		* (sh_evaluate_irradiance(buf_sky_sh.coeff, bent_normal, ao)
			   * pow2(light_sq)
		   + 0.1 * buf_sky_sh.irradiance_up * light_sq * ao
			   * ao); // Bounced skylight.
}

float3 calculate_ambient_light(float3 brdf, float3 flat_normal, float ao) {
	// Arbitrary directional shading to make faces easier to distinguish
	float directional_shading
		= (0.9 + 0.1 * flat_normal.x) * (0.8 + 0.2 * abs(flat_normal.y));

	return brdf * buf_global.ambient_irradiance * ao * directional_shading;
}


