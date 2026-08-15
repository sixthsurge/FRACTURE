import aperture;
import lib.atmosphere;
import lib.gbuffer_packing;
import lib.lighting.main_lighting;
import lib.lighting.material;
import lib.sky;
import lib.util.color;
import lib.util.math;
import lib.util.random;
import lib.util.space_conversion;
import settings;

Texture2D<uint4> tex_packed_solid_gbuffer;
Texture3D<float3> tex_atmosphere_aerial_perspective;
Texture2D<float3> tex_atmosphere_transmittance_lut;
Texture2D<float> tex_blue_noise;

struct FragmentOutput {
	float3 radiance;
}

[shader("pixel")]
FragmentOutput main(float2 coord: SV_Position) {
	int2 icoord = int2(coord);
	float2 ncoord = coord / float2(ap.game.renderSize);

	float depth = ap.opaqueDepth[icoord];
	uint4 packed_gbuffer = tex_packed_solid_gbuffer[icoord];
	float2 dither = float2(
		tex_blue_noise[icoord & 511],
		tex_blue_noise[(icoord + int2(93, 41)) & 511]
	);

	float3 pos_screen = float3(ncoord, depth);
	float3 pos_view = screen_to_view(pos_screen);
	float3 pos_scene = view_to_scene(pos_view);

	float3 dir_world = normalize(pos_scene);

	if (depth == 0.0) {
		return FragmentOutput(calculate_sky_radiance(dir_world));
	}

	SolidGbuffer gbuffer = SolidGbuffer.unpack(packed_gbuffer);

	float3 albedo = srgb_eotf_inv(gbuffer.albedo);

	Material material = Material.get(albedo, gbuffer.mat_id);
	if (userSettings.LABPBR_SUPPORT_ENABLED) {
		material.apply_specular_map(gbuffer.specular_map.get().value);
	}

	float3 radiance = calculate_outgoing_radiance(
		material,
		pos_scene,
		dir_world,
		gbuffer.flat_normal_world,
		gbuffer.detail_normal_world.get().orElse(gbuffer.flat_normal_world),
		gbuffer.lightmap,
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


