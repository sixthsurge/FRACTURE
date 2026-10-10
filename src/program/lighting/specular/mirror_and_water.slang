// Mirror specular, upscale+combine rough specular, water rendering.

import aperture;
import lib.atmospherics.atmosphere;
import lib.atmospherics.fog;
import lib.atmospherics.sky;
import lib.atmospherics.water_medium;
import lib.buffer.sky_sh;
import lib.lighting.brdf;
import lib.lighting.specular;
import lib.surface.gbuffer_packing;
import lib.surface.material;
import lib.surface.mat_ids;
import lib.surface.water_waves;
import lib.toggles;
import lib.util.color;
import lib.util.encoding;
import lib.util.math;
import lib.util.space_conversion;
import settings;

import lib.util.debug;

RWTexture2D<float3> tex_scene_write;

Texture2D<float3> tex_scene;
Texture2D<float4> tex_specular_temporal_1;
Texture2D<float4> tex_specular_temporal_2;
Texture2D<uint4> tex_gbuffer_opaque;
Texture2D<uint2> tex_gbuffer_translucent;
Texture2D<float4> tex_sky_map;
Texture3D<float3> tex_fog_volume_integrated_light;
Texture3D<float3> tex_fog_volume_integrated_extinction;

ConstantBuffer<SkyShBuffer> buf_sky_sh;

namespace rough_specular_upscaling {
static float depth_weight(float center_depth_view, float NoV, float4 data) {
	const float STRENGTH = 10.0;
	return exp2(
		-STRENGTH
		* abs((screen_to_view_depth(data.z) - center_depth_view) * NoV)
	);
}

static float normal_weight(float3 center_normal_world, float4 data) {
	return pow16(max0(dot(center_normal_world, decode_octahedral(data.xy))));
}

float3 upscale(float2 pos, float3 normal_world, float depth_view, float NoV) {
	float2 floored_pos, frac_pos = modf(pos, floored_pos);
	int2 int_pos = int2(floored_pos);

	int w, h;
	tex_specular_temporal_1.GetDimensions(w, h);

	int2 p10 = clamp(int_pos + int2(1, 0), int2(0), int2(w, h) - 1);
	int2 p01 = clamp(int_pos + int2(0, 1), int2(0), int2(w, h) - 1);
	int2 p11 = clamp(int_pos + int2(1, 1), int2(0), int2(w, h) - 1);

	float3 output_00 = tex_specular_temporal_1[int_pos].rgb;
	float3 output_01 = tex_specular_temporal_1[p01].rgb;
	float3 output_10 = tex_specular_temporal_1[p10].rgb;
	float3 output_11 = tex_specular_temporal_1[p11].rgb;
	float4 data_00 = tex_specular_temporal_2[int_pos];
	float4 data_01 = tex_specular_temporal_2[p01];
	float4 data_10 = tex_specular_temporal_2[p10];
	float4 data_11 = tex_specular_temporal_2[p11];

	float w00 = depth_weight(depth_view, NoV, data_00)
		* normal_weight(normal_world, data_00) * (1.0 - frac_pos.x)
		* (1.0 - frac_pos.y);
	float w10 = depth_weight(depth_view, NoV, data_10)
		* normal_weight(normal_world, data_10)
		* (frac_pos.x - frac_pos.x * frac_pos.y);
	float w01 = depth_weight(depth_view, NoV, data_01)
		* normal_weight(normal_world, data_01)
		* (frac_pos.y - frac_pos.x * frac_pos.y);
	float w11 = depth_weight(depth_view, NoV, data_11)
		* normal_weight(normal_world, data_11) * (frac_pos.x * frac_pos.y);
	float w_sum = w00 + w10 + w01 + w11;
	float rcp_w_sum = rcp(w_sum);

	if (w_sum > EPS) {
		return (output_00 * w00 + output_01 * w01 + output_10 * w10
				+ output_11 * w11)
			* rcp_w_sum;
	} else {
		return output_00;
	}
}
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
		if (TOGGLE_ROUGH_SPECULAR) {
			specular.TemporalData.empty().store(icoord);
		}
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

		specular_map_rg = gbuffer.specular_map_rg;
		if (let albedo_val = gbuffer.albedo) {
			albedo = albedo_val;
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
		float3 dir_world
			= normalize(front_pos_scene - translation_part(ap.camera.viewInv));
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
				* min(layer_distance, 16.0) * 0.05;

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

		if (userSettings.MIRROR_WATER) {
			// Turn water into a perfect mirror, for debugging the raytracer.
			normal_world = tbn[2];
			material.f0 = float3(1.0);
			radiance = float3(0.0);
		}

		// Sun specular reflection.
		float NoL = dot(normal_world, buf_global.light_dir_world);
		if (NoL > EPS) {
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

	if (userSettings.SPECULAR_ENABLED) {
		float3 dir_world
			= normalize(front_pos_scene - translation_part(ap.camera.viewInv));
		if (material.roughness <= specular.ROUGH_REFLECTION_ROUGHNESS_CUTOFF) {
			if (userSettings.SPECULAR_TRACER == 0) {
				specular.HiZScreenSpaceTracer tracer;
				tracer.init(
					front_pos_screen,
					front_pos_view,
					front_pos_scene + ap.camera.position,
					normal_world,
				);
				radiance += specular.calculate_mirror_reflection(
					tracer,
					material,
					dir_world,
					normal_world,
					pow2(skylight),
				);
			} else {
				specular.HardwareRtTracer tracer;
				tracer.init(
					front_pos_screen,
					front_pos_view,
					front_pos_scene + ap.camera.position,
					normal_world,
				);
				radiance += specular.calculate_mirror_reflection(
					tracer,
					material,
					dir_world,
					normal_world,
					pow2(skylight),
				);
			}
		} else {
			float2 pos = float2(icoord)
				* (ceil(
					   float2(ap.game.renderSize)
					   * userSettings.SPECULAR_ROUGH_RENDER_SCALE
				   )
				   / float2(ap.game.renderSize));
			float NoV = dot(dir_world, normal_world);
			radiance += rough_specular_upscaling.upscale(
							pos,
							normal_world,
							screen_to_view_depth(front_depth),
							NoV,
						)
				* calculate_fresnel(material, -NoV);
		}
	}

	tex_scene_write[icoord] = radiance;
}


