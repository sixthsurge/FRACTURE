public module material;

import lib.mat_ids;
import lib.util.math;

static const float AIR_IOR = 1.000293; // for 0°C and 1 atm
static const float WATER_IOR = 1.333; // for 20°C

struct Material {
	float3 albedo;
	float3 emission;
	float3 f0;
	float3 f82; // hardcoded metals only
	float roughness;
	float sss_amount;
	float porosity;
	bool is_metal;
	bool is_hardcoded_metal;

	// Create material with default values.
	static Material get(float3 albedo, int mat_id) {
		if (mat_id == MAT_WATER) {
			return WATER_MATERIAL;
		}

		Material material;
		material.albedo = albedo;
		material.emission = float3(0.0);
		material.f0 = float3(0.02);
		material.f82 = float3(0.0);
		material.roughness = 1.0;
		material.sss_amount = 0.0;
		material.porosity = 0.0;
		material.is_metal = false;
		material.is_hardcoded_metal = false;

		if (mat_id == MAT_PLANTS) {
			material.sss_amount = 0.5;
		} else if (mat_id == MAT_LEAVES) {
			material.sss_amount = 1.0;
		}

		return material;
	}

	[mutating]
	void apply_specular_map(float4 specular_map) {
		// f0 and f82 values for hardcoded metals from Jessie LC
		// (https://github.com/Jessie-LC)
		const float3[] metal_f0 = {
			float3(0.78, 0.77, 0.74), // Iron
			float3(1.0, 0.9, 0.61), // Gold
			float3(1.0, 0.98, 1.0), // Aluminum
			float3(0.77, 0.8, 0.79), // Chrome
			float3(1.0, 0.89, 0.73), // Copper
			float3(0.79, 0.87, 0.85), // Lead
			float3(0.92, 0.9, 0.83), // Platinum
			float3(1.0, 1.0, 0.91) // Silver
		};
		const float3[] metal_f82
			= { float3(0.74, 0.76, 0.76),
				float3(1.0, 0.93, 0.73),
				float3(0.96, 0.97, 0.98),
				float3(0.74, 0.79, 0.78),
				float3(1.0, 0.9, 0.8),
				float3(0.83, 0.8, 0.83),
				float3(0.89, 0.87, 0.81),
				float3(1.0, 1.0, 0.95) };

		roughness = pow2(1.0 - specular_map.r);
		emission = max(
			emission,
			albedo * specular_map.a * float(specular_map.a != 1.0)
		);

		if (specular_map.g < 229.5 / 255.0) {
			// Dielectrics
			f0 = max(f0, specular_map.g);

			float has_sss = step(64.5 / 255.0, specular_map.b);
			sss_amount = max(
				sss_amount,
				linstep(64.0 / 255.0, 1.0, specular_map.b * has_sss)
			);
			porosity = linstep(
				0.0,
				64.0 / 255.0,
				max0(specular_map.b - specular_map.b * has_sss)
			);
		} else if (specular_map.g < 237.5 / 255.0) {
			// Hardcoded metals
			int metal_id = clamp(int(255.0 * specular_map.g) - 230u, 0u, 7u);

			f0 = metal_f0[metal_id];
			f82 = metal_f82[metal_id];
			is_metal = true;
			is_hardcoded_metal = true;
		} else {
			// Albedo metal
			f0 = albedo;
			is_metal = true;
		}
	}
}

static const Material WATER_MATERIAL = Material(
	float3(0.0),
	float3(0.0),
	float3(0.02),
	float3(0.0),
	0.002,
	1.0,
	0.0,
	false,
	false,
);

struct NormalMapData {
	float3 normal_tangent;
	float texture_ao;
	float heightmap;

	// Unpack labPBR normal map.
	static NormalMapData unpack(float4 normal_map) {
		NormalMapData data;
		data.normal_tangent.xy = normal_map.xy * 2.0 - 1.0;
		data.normal_tangent.z = sqrt(
			saturate(1.0 - dot(data.normal_tangent.xy, data.normal_tangent.xy))
		);
		data.texture_ao = normal_map.z;
		data.heightmap = normal_map.w;
		return data;
	}
}


