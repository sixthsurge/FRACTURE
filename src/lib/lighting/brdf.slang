public module brdf;

import lib.lighting.material;
import lib.util.math;

float f0_to_ior(float f0) {
	float sqrt_f0 = sqrt(f0) * 0.99999;
	return (1.0 + sqrt_f0) / (1.0 - sqrt_f0);
}

// I honestly can't remember the original source for the D, V and dielectric
// fresnel functions; they are quite standard though.

float distribution_ggx(float NoH_sq, float alpha_sq) {
	return alpha_sq / (PI * pow2(1.0 - NoH_sq + NoH_sq * alpha_sq));
}

float v1_smith_ggx(float cos_theta, float alpha_sq) {
	return 1.0
		/ (cos_theta
		   + sqrt((-cos_theta * alpha_sq + cos_theta) * cos_theta + alpha_sq));
}

float v2_smith_ggx(float NoL, float NoV, float alpha_sq) {
	float ggx_l = NoV * sqrt((-NoL * alpha_sq + NoL) * NoL + alpha_sq);
	float ggx_v = NoL * sqrt((-NoV * alpha_sq + NoV) * NoV + alpha_sq);
	return 0.5 / (ggx_l + ggx_v);
}

float3 fresnel_schlick(float cos_theta, float3 f0) {
	float f = pow5(1.0 - cos_theta);
	return f + f0 * (1.0 - f);
}

float3 fresnel_dielectric_n(float cos_theta, float n) {
	float g_sq = pow2(n) + pow2(cos_theta) - 1.0;

	if (g_sq < 0.0) {
		return float3(1.0); // Imaginary g => TIR
	}

	float g = sqrt(g_sq);
	float a = g - cos_theta;
	float b = g + cos_theta;

	return float3(
		0.5 * pow2(a / b)
		* (1.0 + pow2((b * cos_theta - 1.0) / (a * cos_theta + 1.0)))
	);
}

float3 fresnel_dielectric(float cos_theta, float f0) {
	float n = f0_to_ior(f0);
	return fresnel_dielectric_n(cos_theta, n);
}

// Source: Jessie in sLABS.
float3 fresnel_lazanyi_2019(float cos_theta, float3 f0, float3 f82) {
	float3 a = 17.6513846 * (f0 - f82) + 8.16666667 * (1.0 - f0);
	float m = pow5(1.0 - cos_theta);
	return saturate(f0 + (1.0 - f0) * m - a * cos_theta * (m - m * cos_theta));
}

// GGX spherical area light approximation from Horizon: Zero Dawn
// https://www.guerrilla-games.com/read/decima-engine-advances-in-lighting-and-aa
float get_NoH_squared(float NoL, float NoV, float LoV, float light_radius) {
	float radius_cos = cos(light_radius);
	float radius_tan = tan(light_radius);

	// Early out if R falls within the disc​
	float RoL = 2.0 * NoL * NoV - LoV;
	if (RoL >= radius_cos) {
		return 1.0;
	}

	float r_over_length_t = radius_cos * radius_tan * rsqrt(1.0 - RoL * RoL);
	float not_r = r_over_length_t * (NoV - RoL * NoL);
	float vot_r = r_over_length_t * (2.0 * NoV * NoV - 1.0 - RoL * LoV);

	// Calculate dot(cross(N, L), V). This could already be calculated and
	// available.​
	float triple = sqrt(saturate(
		1.0 - NoL * NoL - NoV * NoV - LoV * LoV + 2.0 * NoL * NoV * LoV
	));

	// Do one Newton iteration to improve the bent light Direction​
	float NoB_r = r_over_length_t * triple,
		  VoB_r = r_over_length_t * (2.0 * triple * NoV);
	float NoL_vt_r = NoL * radius_cos + NoV + not_r,
		  LoV_vt_r = LoV * radius_cos + 1.0 + vot_r;
	float p = NoB_r * LoV_vt_r, q = NoL_vt_r * LoV_vt_r, s = VoB_r * NoL_vt_r;
	float x_num = q * (-0.5 * p + 0.25 * VoB_r * NoL_vt_r);
	float x_denom = p * p + s * (s - 2.0 * p)
		+ NoL_vt_r
			* ((NoL * radius_cos + NoV) * LoV_vt_r * LoV_vt_r
			   + q * (-0.5 * (LoV_vt_r + LoV * radius_cos) - 0.5));
	float two_x_1 = 2.0 * x_num / (x_denom * x_denom + x_num * x_num);
	float sin_theta = two_x_1 * x_denom;
	float cos_theta = 1.0 - two_x_1 * x_num;
	not_r
		= cos_theta * not_r + sin_theta * NoB_r; // use new T to update not_r​
	vot_r
		= cos_theta * vot_r + sin_theta * VoB_r; // use new T to update vot_r​

	// Calculate (N.H)^2 based on the bent light direction​
	float new_NoL = NoL * radius_cos + not_r;
	float new_LoV = LoV * radius_cos + vot_r;
	float NoH = NoV + new_NoL;
	float HoH = 2.0 * new_LoV + 2.0;

	return saturate(NoH * NoH / HoH);
}

float3 specular_smith_ggx(
	Material material,
	float light_radius,
	float NoL,
	float NoV,
	float NoH,
	float LoV,
	float LoH
) {
	if (NoL <= EPS) {
		return float3(0.0);
	}

	float3 fresnel;
	if (material.is_hardcoded_metal) {
		fresnel = fresnel_lazanyi_2019(LoH, material.f0, material.f82);
	} else if (material.is_metal) {
		fresnel = fresnel_schlick(LoH, material.albedo);
	} else {
		fresnel = fresnel_dielectric(LoH, material.f0.x);
	}
	if (all(fresnel < float3(1e-2))) {
		return float3(0.0);
	}

	float3 albedo_tint = lerp(
		float3(1.0),
		material.albedo,
		float(material.is_hardcoded_metal)
	);

	float NoH_squared = get_NoH_squared(NoL, NoV, LoV, light_radius);
	float alpha_squared = material.roughness * material.roughness;

	float d = distribution_ggx(NoH_squared, alpha_squared);
	float v = v2_smith_ggx(max(NoL, 1e-2), max(NoV, 1e-2), alpha_squared);

	return d * v * fresnel * albedo_tint;
}

// https://www.gdcvault.com/play/1024478/PBR-Diffuse-Lighting-for-GGX
// Modified by Jessie to correctly account for fresnel.
float3 diffuse_hammon(
	float3 albedo,
	float roughness,
	float f0,
	float NoL,
	float NoV,
	float NoH,
	float LoV
) {
	if (NoL <= 0.0) {
		return float3(0.0);
	}

	float facing = 0.5 * LoV + 0.5;

	float fresnel_nl = fresnel_dielectric(max(NoL, 1e-2), f0).x;
	float fresnel_nv = fresnel_dielectric(max(NoV, 1e-2), f0).x;
	float energy_conservation_factor
		= 1.0 - (4.0 * sqrt(f0) + 5.0 * f0 * f0) * (1.0 / 9.0);

	float single_rough
		= max0(facing) * (-0.2 * facing + 0.45) * (1.0 / NoH + 2.0);
	float single_smooth
		= (1.0 - fresnel_nl) * (1.0 - fresnel_nv) / energy_conservation_factor;

	float single = lerp(single_smooth, single_rough, roughness) / PI;
	float multi = 0.1159 * roughness;

	return albedo * multi + single;
}


