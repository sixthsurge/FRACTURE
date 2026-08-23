// - Calculate water normal and absorption.
// - Calculate reflection and refraction.

import aperture;
import lib.buffer.sky_sh;
import lib.lighting.brdf;
import lib.lighting.ssrt;
import lib.surface.gbuffer_packing;
import lib.surface.material;
import lib.surface.mat_ids;
import lib.surface.water_waves;
import lib.volumetrics.water_medium;
import lib.util.color;
import lib.util.math;
import lib.util.space_conversion;
import lib.volumetrics.atmosphere;
import lib.volumetrics.fog;
import settings;

RWTexture2D<float3> tex_scene_write;

Texture2D<float3> tex_scene;
Texture2D<uint4> tex_gbuffer_solid;
Texture2D<uint2> tex_gbuffer_translucent;
Texture2D<float3> tex_atmosphere_sky_view;
Texture3D<float3> tex_fog_volume_integrated_extinction;

ConstantBuffer<SkyShBuffer> buf_sky_sh;

float3 calculate_reflection(
	Material material,
	float3 pos_screen,
	float3 pos_view,
	float3 dir_view,
	float3 normal_view,
	float skylight
) {
	// As there is no rough SSR yet, just fade smooth SSR with roughness.
	float fresnel_multiplier = pow2(linstep(0.5, 0.05, material.roughness));
	float3 fresnel
		= fresnel_dielectric_n(-dot(dir_view, normal_view), WATER_IOR / AIR_IOR)
		* fresnel_multiplier;
	if (all(fresnel < 1e-2)) {
		return float3(0.0);
	}

	float3 ray_dir_view = reflect(dir_view, normal_view);

	Ray ray = Ray(
		pos_screen,
		ssrt.screen_space_ray_direction(pos_screen, pos_view, ray_dir_view)
	);

	if (let hit_pos_screen = ssrt.trace_hiz(
			ray,
			ssrt.screen_space_ray_length(ray),
			ssrt.thickness_heuristic(pos_view, ray.d)
		)) {
		return tex_scene.sampleLinear(hit_pos_screen.xy) * fresnel;
	} else {
		return atmosphere.lookup_sky_radiance(
				   tex_atmosphere_sky_view,
				   mul(float3x3(ap.camera.viewInv), ray_dir_view)
			   )
			* fresnel * pow4(skylight);
	}
}

struct FragmentOutput {
	float3 radiance;
}

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID) {
	if (any(icoord >= ap.game.renderSize)) {
		return;
	}

	float2 coord = float2(icoord) + 0.5;
	float2 ncoord = coord / float2(ap.game.renderSize);

	float front_depth = ap.depth[icoord];
	float hand_depth = ap.handDepth[icoord];
	float back_depth = ap.opaqueDepth[icoord];
	float3 radiance = tex_scene[icoord];
	uint4 gbuffer_solid = tex_gbuffer_solid[icoord];
	uint2 gbuffer_translucent = tex_gbuffer_translucent[icoord];

	front_depth = max(front_depth, hand_depth);
	if (front_depth == 0.0) {
		// FIXME work out if we need to write here.
		tex_scene_write[icoord] = radiance;
		return;
	}

	float3 front_pos_screen = float3(ncoord, front_depth);
	float3 front_pos_view = screen_to_view(front_pos_screen);
	float3 front_pos_scene = view_to_scene(front_pos_view);
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
	float3 albedo = float3(0.0);

	if (front_depth > back_depth) {
		// Translucent.
		TranslucentGbuffer gbuffer
			= TranslucentGbuffer.unpack(gbuffer_translucent);
		normal_world = gbuffer.normal_world;
		skylight = gbuffer.skylight;
		mat_id = gbuffer.mat_id;

		if (userSettings.LABPBR_SUPPORT_ENABLED) {
			specular_map_rg = gbuffer.specular_map_rg;
			if (let albedo_val = gbuffer.albedo) {
				albedo = albedo_val;
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
			albedo = gbuffer.albedo;
		}
	}
	albedo = srgb_eotf_inv(albedo);
	Material material = Material.get(albedo, mat_id);
	if (userSettings.LABPBR_SUPPORT_ENABLED && mat_id != MAT_WATER) {
		material.apply_specular_map(float4(specular_map_rg, float2(0.0)));
	}

	// Water waves.
	if (mat_id == MAT_WATER) {
		float3x3 tbn = make_tbn_matrix(normal_world);

		float3 pos_tangent = mul(tbn, front_pos_scene + ap.camera.position);
		float3 dir_world = normalize(front_pos_scene);
		float3 dir_tangent = mul(tbn, dir_world);

		WaterWaves.Params wave_params
			= WaterWaves.init_params(tbn, dir_world, normal_world, skylight);

		pos_tangent = WaterWaves.calculate_parallax(
			wave_params,
			pos_tangent,
			dir_tangent
		);

		float3 normal_tangent
			= WaterWaves.calculate_normal(wave_params, pos_tangent.xy);

		normal_world = mul(normal_tangent, tbn);
	}

	// Water medium participation.
	if (mat_id == MAT_WATER && ap.camera.fluid != 1) {
		float3 back_pos_view = screen_to_view(float3(ncoord, back_depth));

		float3 absorption_coeff = calculate_water_absorption_coeff(albedo);

		WaterMedium water_medium = calculate_water_medium_participation(
			front_pos_scene,
			buf_global.celestial_light_irradiance
				* max0(buf_global.light_dir_world.y)
				* linstep(0.0, 0.25, skylight),
			buf_sky_sh.irradiance_up * pow3(skylight),
			absorption_coeff,
			distance(front_pos_view, back_pos_view),
			dot(dir_view, buf_global.light_dir_view)
		);

		radiance = water_medium.apply(radiance);
	}

	float3 normal_view = mul(float3x3(ap.camera.view), normal_world);

	// Water surface transmission.
	if (mat_id == MAT_WATER) {
		float NoV = -dot(normal_view, dir_view);
		radiance *= 1.0
			- fresnel_dielectric_n(
						NoV,
						select(
							ap.camera.fluid == 1,
							AIR_IOR / WATER_IOR,
							WATER_IOR / AIR_IOR
						)
			);
	}

	radiance += calculate_reflection(
					material,
					front_pos_screen,
					front_pos_view,
					dir_view,
					normal_view,
					skylight
				)
		* exp(-fog_extinction);

	tex_scene_write[icoord] = radiance;
}


