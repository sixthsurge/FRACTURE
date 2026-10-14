// Rough specular tracing and accumulation.

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
import lib.util.math;
import lib.util.space_conversion;
import settings;

import lib.util.debug;

RWTexture2D<float3> tex_scene_write;

Texture2D<uint4> tex_gbuffer_opaque;
Texture2D<uint2> tex_gbuffer_translucent;
Texture2D<float4> tex_specular_output_blurred;

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID) {
	int w, h;
	tex_specular_output_blurred.GetDimensions(w, h);
	float2 output_pixel_size = rcp(float2(w, h));

	int2 fullres_icoord = int2(
		float2(icoord) * (float2(ap.game.renderSize) * output_pixel_size)
	);
	if (any(icoord >= int2(w, h))
		|| any(fullres_icoord >= ap.game.renderSize)) {
		return;
	}

	float2 coord = float2(icoord) + 0.5;
	float2 ncoord = coord / float2(w, h);

	float front_depth = ap.depth[fullres_icoord];
	float hand_depth = ap.handDepth[fullres_icoord];
	float back_depth = ap.opaqueDepth[fullres_icoord];
	uint4 gbuffer_solid = tex_gbuffer_opaque[fullres_icoord];
	uint2 gbuffer_translucent = tex_gbuffer_translucent[fullres_icoord];

	front_depth = max(front_depth, hand_depth);
	if (front_depth == 0.0) {
		specular.TemporalData.empty().store(icoord);
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
	if (material.roughness <= specular.ROUGH_REFLECTION_ROUGHNESS_CUTOFF) {
		specular.TemporalData.empty().store(icoord);
		return;
	}

	float3 dir_world
		= normalize(front_pos_scene - translation_part(ap.camera.viewInv));

	if (userSettings.SPECULAR_TRACER == 0) {
		specular.do_rough_specular(
			specular.HiZScreenSpaceTracer(),
			material,
			icoord,
			front_pos_screen,
			front_pos_view,
			front_pos_scene + ap.camera.position,
			dir_world,
			normal_world,
			skylight
		);
	} else {
		specular.do_rough_specular(
			specular.HardwareRtTracer(),
			material,
			icoord,
			front_pos_screen,
			front_pos_view,
			front_pos_scene + ap.camera.position,
			dir_world,
			normal_world,
			skylight
		);
	}
}


