// - Calculate water normal and absorption.
// - Calculate reflection and refraction.

import aperture;
import lib.atmosphere;
import lib.gbuffer_packing;
import lib.fog;
import lib.lighting.brdf;
import lib.lighting.material;
import lib.mat_ids;
import lib.ssrt;
import lib.util.color;
import lib.util.math;
import lib.util.space_conversion;
import settings;

Texture2D<float3> tex_scene;
Texture2D<uint4> tex_gbuffer_solid;
Texture2D<uint2> tex_gbuffer_translucent;
Texture2D<float3> tex_atmosphere_sky_view;
Texture3D<float3> tex_fog_volume_integrated_extinction;

float3 calculate_reflection(
	Material material,
	float3 pos_screen,
	float3 pos_view,
	float3 dir_view,
	float3 normal_view
) {
	float3 ray_dir_view = reflect(dir_view, normal_view);
	float3 halfway_dir_view = normalize(-dir_view + ray_dir_view);

	// As there is no rough SSR yet, just fade smooth SSR with roughness.
	float fresnel_multiplier = pow2(linstep(0.5, 0.05, material.roughness));
	float3 fresnel
		= calculate_fresnel(material, dot(ray_dir_view, halfway_dir_view))
		* fresnel_multiplier;
	if (all(fresnel < float3(1e-2))) {
		return float3(0.0);
	}

	Ray ray = Ray(
		pos_screen,
		ssrt.screen_space_ray_direction(pos_screen, pos_view, ray_dir_view)
	);

	float3 reflected_radiance;
	if (let hit_pos_screen = ssrt.trace_hiz(
			ray,
			ssrt.screen_space_ray_length(ray),
			ssrt.thickness_heuristic(pos_view, ray.d)
		)) {
		reflected_radiance = tex_scene.sampleLinear(hit_pos_screen.xy);
	} else {
		reflected_radiance = atmosphere.lookup_sky_radiance(
			tex_atmosphere_sky_view,
			mul(float3x3(ap.camera.viewInv), ray_dir_view)
		);
	}

	return reflected_radiance * fresnel;
}

struct FragmentOutput {
	float3 radiance;
}

[shader("fragment")]
FragmentOutput main(float2 coord: SV_Position) {
	int2 icoord = int2(coord);
	float2 ncoord = coord / float2(ap.game.renderSize);

	float front_depth = ap.depth[icoord];
	float back_depth = ap.opaqueDepth[icoord];
	float3 radiance = tex_scene[icoord];
	uint4 gbuffer_solid = tex_gbuffer_solid[icoord];
	uint2 gbuffer_translucent = tex_gbuffer_translucent[icoord];

	if (front_depth == 0.0) {
		return FragmentOutput(radiance);
	}

	float3 front_pos_screen = float3(ncoord, front_depth);
	float3 front_pos_view = screen_to_view(front_pos_screen);
	// Lookup fog extinction to apply on top of the reflection.
	float3 fog_extinction = fog.lookup_fog(
		tex_fog_volume_integrated_extinction,
		front_pos_screen,
		front_pos_view
	);

	float3 dir_view = normalize(front_pos_view);

	// Get front surface info.
	float3 normal_world;
	float skylight;
	int mat_id;
	float2 specular_map_rg;
	float3 albedo_for_albedo_metals = float3(0.0);

	if (front_depth > back_depth) {
		// Translucent.
		TranslucentGbuffer gbuffer
			= TranslucentGbuffer.unpack(gbuffer_translucent);
		normal_world = gbuffer.normal_world;
		skylight = gbuffer.skylight;
		mat_id = gbuffer.mat_id;

		if (userSettings.LABPBR_SUPPORT_ENABLED) {
			specular_map_rg = gbuffer.specular_map_rg.get().value;
			if (let albedo = gbuffer.albedo_for_albedo_metals.get()) {
				albedo_for_albedo_metals = albedo.orElse(0.0);
			}
		}
	} else {
		// Solid.
		SolidGbuffer gbuffer = SolidGbuffer.unpack(gbuffer_solid);
		normal_world = gbuffer.detail_normal_world.get().orElse(
			gbuffer.flat_normal_world
		);
		skylight = gbuffer.lightmap.y;
		mat_id = gbuffer.mat_id;
		if (userSettings.LABPBR_SUPPORT_ENABLED) {
			specular_map_rg = gbuffer.specular_map.get().value.rg;
			albedo_for_albedo_metals = gbuffer.albedo;
		}
	}
	Material material = Material.get(albedo_for_albedo_metals, mat_id);
	if (userSettings.LABPBR_SUPPORT_ENABLED && mat_id != MAT_WATER) {
		material.apply_specular_map(float4(specular_map_rg, float2(0.0)));
	}

	radiance += calculate_reflection(
					material,
					front_pos_screen,
					front_pos_view,
					dir_view,
					mul(float3x3(ap.camera.view), normal_world)
				)
		* exp(-fog_extinction);

	return FragmentOutput(radiance);
}


