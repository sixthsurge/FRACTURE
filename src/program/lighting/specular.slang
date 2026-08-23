// Specular reflections, water rendering.

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
import lib.volumetrics.sky;
import settings;

RWTexture2D<float3> tex_scene_write;

Texture2D<float3> tex_scene;
Texture2D<uint4> tex_gbuffer_opaque;
Texture2D<uint2> tex_gbuffer_translucent;
Texture2D<float3> tex_atmosphere_sky_view;
Texture3D<float3> tex_fog_volume_integrated_light;
Texture3D<float3> tex_fog_volume_integrated_extinction;

ConstantBuffer<SkyShBuffer> buf_sky_sh;

float3 calculate_reflection(
	Material material,
	float3 pos_screen,
	float3 pos_view,
	float3 dir_view,
	float3 normal_view,
	float skylight,
	float celestial_light_visibility,
	bool reflect_space
) {
	// As there is no rough SSR yet, just fade smooth SSR with roughness.
	float fresnel_multiplier = pow2(linstep(0.5, 0.05, material.roughness));
	float3 fresnel = calculate_fresnel(material, -dot(dir_view, normal_view))
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
		float3 ray_dir_world = mul(float3x3(ap.camera.viewInv), ray_dir_view);

		atmosphere.AtmosphereParticipation atmosphere_participation
			= calculate_atmosphere_participation(ray_dir_world);

		float3 space_radiance = float3(0.0);
		if (reflect_space) {
			space_radiance = calculate_space_radiance(
				ray_dir_world,
				0.0,
				select(
					buf_global.sun_angle > 0.5,
					celestial_light_visibility,
					0.0
				)
			);
		}

		return atmosphere_participation.apply(space_radiance) * fresnel;
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
	uint4 gbuffer_solid = tex_gbuffer_opaque[icoord];
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

	float3 dir_view = normalize(front_pos_view);
	float view_distance = length(front_pos_view);

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
		OpaqueGbuffer gbuffer = OpaqueGbuffer.unpack(gbuffer_solid);
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

	float water_shadow_visibility = 0.0;
	[branch]
	if (mat_id == MAT_WATER) {
		// Water waves.
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

		// Refraction.
		float3 back_pos_view = screen_to_view(float3(ncoord, back_depth));
		float layer_distance = distance(front_pos_view, back_pos_view);

		float2 refracted_ncoord = ncoord
			+ normal_tangent.xy * rcp(view_distance + 1.0)
				* min(layer_distance, 16.0) * 0.1;

		[flatten]
		if (all(refracted_ncoord == saturate(refracted_ncoord))) {
			float refracted_depth
				= ap.opaqueDepth.sampleLinear(refracted_ncoord);

			// Make sure the refracted pixel is behind the water.
			refracted_ncoord = select(
				refracted_depth < front_depth,
				refracted_ncoord,
				ncoord
			);
			refracted_depth = select(
				refracted_depth < front_depth,
				refracted_depth,
				back_depth
			);

			radiance = tex_scene.sampleLinear(refracted_ncoord);
			back_pos_view
				= screen_to_view(float3(refracted_ncoord, refracted_depth));
		}

		WaterShadow shadow = calculate_water_shadow(front_pos_scene);
		water_shadow_visibility = shadow.visibility;

		// Water medium participation.
		float LoV = dot(-dir_view, buf_global.light_dir_view);
		if (ap.camera.fluid != 1) {
			float3 absorption_coeff = calculate_water_absorption_coeff(albedo);

			WaterMedium water_medium = calculate_water_medium_participation(
				shadow,
				front_pos_scene,
				buf_global.celestial_light_irradiance
					* max0(buf_global.light_dir_world.y)
					* linstep(0.0, 0.25, skylight),
				buf_sky_sh.irradiance_up * pow3(skylight),
				absorption_coeff,
				distance(front_pos_view, back_pos_view),
				-LoV,
			);

			radiance = water_medium.apply(radiance);
		}

		// Water surface transmission.
		float NoV = -dot(normal_world, dir_world);
		float fresnel = fresnel_dielectric_n(
			NoV,
			select(
				ap.camera.fluid == 1,
				AIR_IOR / WATER_IOR,
				WATER_IOR / AIR_IOR,
			)
		);
		radiance *= 1.0 - fresnel;

		// Sun specular reflection.
		float NoL = dot(normal_world, buf_global.light_dir_world);
		if (buf_global.sun_angle < 0.5 && NoL > EPS) {
			float NoV = saturate(dot(normal_world, -dir_world));
			float halfway_norm = rsqrt(2.0 * LoV + 2.0);
			float NoH = (NoL + NoV) * halfway_norm;
			float LoH = LoV * halfway_norm + halfway_norm;

			radiance += specular_smith_ggx(
							material,
							buf_global.celestial_light_angular_radius,
							NoL,
							NoV,
							NoH,
							LoV,
							LoH
						)
				* NoL * buf_global.celestial_light_irradiance
				* shadow.visibility;
		}
	}

	// Lookup fog participation to apply on top of water and reflections.
	fog.FogParticipation fog = fog.lookup_fog_participation(
		tex_fog_volume_integrated_light,
		tex_fog_volume_integrated_extinction,
		front_pos_screen,
		front_pos_view
	);

	// Apply fog on top of water.
	if (mat_id == MAT_WATER) {
		radiance = fog.apply(radiance);
	}

	radiance
		+= calculate_reflection(
			   material,
			   front_pos_screen,
			   front_pos_view,
			   dir_view,
			   mul(float3x3(ap.camera.view), normal_world),
			   skylight,
			   water_shadow_visibility,
			   mat_id == MAT_WATER,
		   )
		* exp(-fog.extinction);

	tex_scene_write[icoord] = radiance;
}


