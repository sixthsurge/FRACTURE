public module celestial;

import lib.lighting.brdf;
import lib.surface.material;
import lib.lighting.shadow;
import lib.util.color;
import lib.util.phase_functions;
import lib.util.math;
import settings;

internal float3 calculate_sss(
	float3 albedo,
	float sss_amount,
	float sheen_amount,
	float sss_depth,
	float LoV
) {
	const float DENSITY = 4.0;
	const float SCALE = 5.0;

	if (sss_amount < EPS) {
		return float3(0.0);
	}

	float3 coeff = albedo * rsqrt(dot(albedo, LUMINANCE_WEIGHTS_REC709) + EPS);
	coeff = 0.75 * saturate(coeff);
	coeff = (1.0 - coeff) * DENSITY / sss_amount;

	float phase
		= lerp(ISOTROPIC_PHASE, henyey_greenstein_phase(-LoV, 0.7), 0.33);

	float3 sss = phase * exp2(-coeff * sss_depth) * dampen(sss_amount);

	float3 sheen = 0.8 / (albedo + EPS) * exp2(-1.0 * coeff * sss_depth)
		* henyey_greenstein_phase(-LoV, 0.5) * linstep(-0.8, -0.2, -LoV);
	sss += sheen * sheen_amount * 0.1;

	return max0(sss) * albedo * SCALE;
}

float3 calculate_celestial_light<bool SIMPLE = false>(
	Material material,
	float3 pos_scene,
	float3 dir_world,
	float3 flat_normal_world,
	float3 detail_normal_world,
	float2 dither
) {
	float3 light = float3(0.0);
	shadow.Result shadow_result;
	if (SIMPLE) {
		shadow_result = shadow.calculate_simple(pos_scene, flat_normal_world);
	} else {
		shadow_result
			= shadow.calculate(pos_scene, flat_normal_world, dither, true);
	}

	float LoV = dot(buf_global.light_dir_world, -dir_world);

	if (!SIMPLE) {
		light += calculate_sss(
			material.albedo,
			material.sss_amount,
			material.sss_amount,
			shadow_result.sss_depth,
			LoV
		);
	}

	if (max_of(shadow_result.visibility) > EPS) {
		float NoL = dot(detail_normal_world, buf_global.light_dir_world);
		float NoV = saturate(dot(detail_normal_world, -dir_world));
		float halfway_norm = rsqrt(2.0 * LoV + 2.0);
		float NoH = (NoL + NoV) * halfway_norm;
		float LoH = LoV * halfway_norm + halfway_norm;

		float3 diffuse
			= diffuse_hammon(
				  material.albedo,
				  material.roughness,
				  material.f0.x,
				  NoL,
				  NoV,
				  NoH,
				  LoV
			  )
			* material.albedo;
		float3 specular = specular_smith_ggx(
			material,
			buf_global.celestial_light_angular_radius,
			NoL,
			NoV,
			NoH,
			LoV,
			LoH
		);

		light += (diffuse + specular) * max0(NoL) * shadow_result.visibility;
	}
	return light * buf_global.celestial_light_irradiance;
}


