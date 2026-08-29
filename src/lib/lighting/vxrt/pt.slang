public module pt;

import aperture;
import lib.lighting.brdf;
import lib.lighting.celestial;
import lib.lighting.emission;
import lib.lighting.vxrt.trace;
import lib.surface.material;
import lib.util.math;
import lib.util.random;
import lib.util.sampling;
import lib.volumetrics.atmosphere;

internal Texture2D<float3> tex_atmosphere_sky_view;

namespace vxrt {
float3 pt<Random, int RAY_COUNT, int BOUNCE_COUNT>(
	Random random,
	Material material,
	float3 ray_origin_world,
	float3 ray_dir,
	float3 flat_normal_world,
	float3 detail_normal_world,
)
	where Random : IRandom {
	const int INTERSECTION_STEPS = 50;

	float3 radiance = float3(0.0);

	for (int ray = 0; ray < RAY_COUNT; ++ray) {
		float3 current_pos = ray_origin_world;
		Material current_material = material;
		float3 current_flat_normal = flat_normal_world;
		float3 current_detail_normal = detail_normal_world;
		float3 last_dir = ray_dir;
		float3 throughput = 1.0;

		for (int bounce = 0; bounce < BOUNCE_COUNT; ++bounce) {
			float3x3 tbn = make_tbn_matrix(current_flat_normal);
			float3 tangent_dir = mul(tbn, last_dir);
			float3 microfacet_normal = mul(
				sample_ggx_vndf(
					-tangent_dir,
					material.roughness,
					random.next_float2()
				),
				tbn
			);
			float3 fresnel = calculate_fresnel(
				material,
				dot(microfacet_normal, -last_dir)
			);
			float fresnel_choice = dot(fresnel, float3(rcp(3.0)));

			float3 ray_dir, brdf_over_pdf;
			if (fresnel_choice < random.next_float()) {
				// Diffuse.
				ray_dir = sample_cos_weighted_hemisphere(
					current_detail_normal,
					random.next_float2()
				);
				if (dot(ray_dir, current_flat_normal) < EPS) {
					ray_dir = -ray_dir;
				}

				brdf_over_pdf = material.albedo * (fresnel_choice / fresnel);
			} else {
				// FIXME account for G terms.
				ray_dir = reflect(last_dir, microfacet_normal);
				brdf_over_pdf = fresnel / fresnel_choice;
			}

			bool hit_sky = false;
			float3 bounce_radiance;
			float3 tint;
			if (let hit
				= trace(Ray(current_pos, ray_dir), INTERSECTION_STEPS, tint)) {
				bounce_radiance
					= calculate_celestial_light(
						  hit.material,
						  hit.pos_world - ap.camera.position,
						  ray_dir,
						  hit.normal,
						  hit.normal,
						  random.next_float()
					  )
					+ calculate_emission(hit.material.emission);
				current_pos = hit.pos_world;
				current_flat_normal = hit.normal;
				current_detail_normal = hit.normal;
				current_material = hit.material;
			} else {
				bounce_radiance = atmosphere.lookup_sky_radiance(
					tex_atmosphere_sky_view,
					ray_dir
				);
			}

			tint = sqrt(sqrt(tint));
			radiance += bounce_radiance * throughput * brdf_over_pdf * tint;
			throughput *= brdf_over_pdf * tint;
			last_dir = ray_dir;
			if (hit_sky) {
				break;
			}
		}

		return max0(radiance);
	}
}
} // namespace vxrt


