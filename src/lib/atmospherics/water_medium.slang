public module water_medium;

import aperture;
import lib.lighting.shadow;
import lib.util.math;
import lib.util.phase_functions;

static const float3 BASE_WATER_ABSORPTION_COEFF = float3(0.39, 0.11, 0.07);
static const float WATER_SCATTERING_COEFF = 0.01;
static const bool BIOME_WATER_COLOR = true;

float3 calculate_water_absorption_coeff(float3 biome_water_color) {
	const float density_scale = 0.15;
	const float biome_color_contribution = 0.33;

	const float3 FOREST_WATER_ABSORPTION_COEFF
		= -density_scale * log(float3(0.1245, 0.1797, 0.7108));

	if (BIOME_WATER_COLOR) {
		float3 biome_absorption_coeff
			= -density_scale * log(biome_water_color + EPS)
			- FOREST_WATER_ABSORPTION_COEFF;

		return max0(
			BASE_WATER_ABSORPTION_COEFF
			+ biome_absorption_coeff * biome_color_contribution
		);
	} else {
		return BASE_WATER_ABSORPTION_COEFF;
	}
}

struct WaterMedium {
	float3 scattering;
	float3 transmittance;

	float3 apply(float3 radiance) {
		return radiance * transmittance + scattering;
	}
}

struct WaterShadow {
	float visibility; // Visibility from opaque shadow map.
	float depth; // Depth through the water.
}

WaterShadow calculate_water_shadow(float3 pos_scene) {
	float3 pos_shadow_view = transform(ap.celestial.view, pos_scene);

	int cascade;
	float3 pos_shadow_screen;
	if (let result = shadow.project_shadow(pos_shadow_view)) {
		cascade = result.cascade;
		pos_shadow_screen = result.pos_shadow_screen;
	} else {
		return WaterShadow(1.0, 0.0);
	}

	float opaque_shadow = ap.opaqueShadow.compare(
		pos_shadow_screen.xy,
		cascade,
		pos_shadow_screen.z
	);
	float translucent_depth
		= ap.shadow.sampleLinear(pos_shadow_screen.xy, cascade);

	return WaterShadow(
		opaque_shadow,
		max0(pos_shadow_screen.z - translucent_depth)
			/ abs(ap.celestial.projection[cascade][2].z)
	);
}

// Simple water fog applied behind water or when volumetric fog is disabled
WaterMedium calculate_water_medium_participation(
	WaterShadow shadow,
	float3 pos_scene,
	float3 direct_irradiance,
	float3 ambient_irradiance,
	float3 absorption_coeff,
	float dist,
	float LoV
) {
	float3 scattering_coeff = float3(WATER_SCATTERING_COEFF);
	float3 extinction_coeff = scattering_coeff + absorption_coeff;

	// Multiple scattering approximation from Jessie.
	float3 scattering_albedo = scattering_coeff / extinction_coeff;
	float3 multiple_scattering_factor = 0.84 * scattering_albedo;
	float3 multiple_scattering_energy
		= multiple_scattering_factor / (1.0 - multiple_scattering_factor);

	float3 transmittance = exp(-extinction_coeff * dist);

	// Direct lighting.
	float3 scattering = direct_irradiance * shadow.visibility
		* exp(-extinction_coeff * shadow.depth);
	// Phase function for direct lighting.
	scattering
		*= 0.7 * henyey_greenstein_phase(LoV, 0.4) + 0.3 * ISOTROPIC_PHASE;
	// Ambient lighting.
	scattering += ambient_irradiance * ISOTROPIC_PHASE;
	// Scattering integral.
	scattering *= (1.0 - transmittance) * scattering_coeff / extinction_coeff;
	// Multiple scattering.
	scattering *= 1.0 + multiple_scattering_energy;

	return WaterMedium(scattering, transmittance);
}


