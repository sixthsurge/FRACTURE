import aperture;
import lib.atmosphere;
import lib.gbuffer_packing;
import lib.lighting.main_lighting;
import lib.lighting.material;
import lib.util.color;
import lib.util.math;
import lib.util.random;
import lib.util.space_conversion;
import settings;

Texture2D<uint4> tex_packed_gbuffer_data;
Texture2D<float3> tex_atmosphere_sky_view;
Texture2D<float3> tex_atmosphere_transmittance_lut;
Texture3D<float3> tex_atmosphere_aerial_perspective;
Texture2D<float> tex_blue_noise;

struct FragmentOutput {
	float3 radiance;
}

[shader("pixel")]
FragmentOutput main(float2 coord: SV_Position) {
	int2 icoord = int2(coord);
	float2 ncoord = coord / float2(ap.game.renderSize);

	float depth = ap.opaqueDepth[icoord];
	uint4 packed_gbuffer_data = tex_packed_gbuffer_data[icoord];
	float2 dither = float2(
		tex_blue_noise[icoord & 511],
		tex_blue_noise[(icoord + int2(93, 41)) & 511]
	);

	float3 pos_screen = float3(ncoord, depth);
	float3 pos_view = screen_to_view(pos_screen);
	float3 pos_scene = view_to_scene(pos_view);

	float3 dir_world = normalize(pos_scene);

	if (depth == 0.0) {
		return FragmentOutput(
			atmosphere.lookup_sky_radiance(tex_atmosphere_sky_view, dir_world)
		);
	}

	GbufferData gbuffer_data = GbufferData.unpack(packed_gbuffer_data);

	float3 albedo = srgb_eotf_inv(gbuffer_data.albedo);

	Material material = Material.get(albedo, gbuffer_data.mat_id);
	material.apply_specular_map(gbuffer_data.specular_map);

	float3 radiance = calculate_outgoing_radiance(
		material,
		pos_scene,
		dir_world,
		gbuffer_data.flat_normal_world,
		gbuffer_data.detail_normal_world,
		gbuffer_data.lightmap,
		dither
	);

	if (userSettings.ATMOSPHERE_AP_LUT_ENABLED) {
		radiance = atmosphere.apply_aerial_perspective(
			tex_atmosphere_aerial_perspective,
			tex_atmosphere_transmittance_lut,
			pos_screen,
			pos_scene,
			radiance
		);
	}

	return FragmentOutput(radiance);
}


