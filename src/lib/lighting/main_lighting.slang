public module main_lighting;

import lib.buffer.sky_sh;
import lib.lighting.brdf;
import lib.lighting.material;
import lib.lighting.shadow;
import lib.util.math;
import lib.util.spherical_harmonics;
import settings;

ConstantBuffer<SkyShBuffer> buf_sky_sh;

float3 calculate_outgoing_radiance(
	Material material,
	float3 pos_scene,
	float3 dir_world,
	float3 flat_normal_world,
	float3 detail_normal_world,
	float2 lightmap
) {
	float3 radiance = float3(0.0);

	// Celestial light.

	if (dot(flat_normal_world, buf_global.light_dir_world) >= EPS) {
		ShadowResult shadow = calculate_shadow(pos_scene);

		float NoL = dot(detail_normal_world, buf_global.light_dir_world);
		float NoV = saturate(dot(detail_normal_world, -dir_world));
		float LoV = dot(buf_global.light_dir_world, -dir_world);
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

		radiance += (diffuse + specular) * max0(NoL) * shadow.visibility
			* buf_global.celestial_light_irradiance;
	}

	// Skylight

	float3 ambient_irradiance
		= sh_evaluate_irradiance(buf_sky_sh.coeff, flat_normal_world, 1.0)
		* pow2(lightmap.y);

	radiance += ambient_irradiance * material.albedo / PI;

	return radiance;
}


