import aperture;
import lib.atmosphere;
import lib.buffer.sky_sh;
import lib.gbuffer_packing;
import lib.sky_view_projection;
import lib.lighting.celestial_shadow;
import lib.util.color;
import lib.util.math;
import lib.util.space_conversion;
import lib.util.spherical_harmonics;
import settings;

Texture2D<uint2> tex_packed_gbuffer_data;
Texture2D<float3> tex_atmosphere_sky_view;
Texture2D<float3> tex_atmosphere_transmittance_lut;
Texture3D<float3> tex_atmosphere_aerial_perspective;

ConstantBuffer<SkyShBuffer> buf_sky_sh;

struct FragmentOutput {
	float3 radiance;
}

[shader("pixel")]
FragmentOutput main(float2 coord: SV_Position) {
	int2 icoord = int2(coord);
	float2 ncoord = coord / float2(ap.game.renderSize);

	uint2 packed_gbuffer_data = tex_packed_gbuffer_data[icoord];
	float depth = ap.opaqueDepth[icoord];

	float3 pos_screen = float3(ncoord, depth);
	float3 pos_view = screen_to_view(pos_screen);
	float3 pos_scene = view_to_scene(pos_view);

	float3 dir_world = normalize(pos_scene);

	if (depth == 0.0) {
		return FragmentOutput(tex_atmosphere_sky_view.Sample(
			apt_linearSampler,
			project_sky_view(dir_world)
		));
	}

	GbufferData gbuffer_data = GbufferData.unpack(packed_gbuffer_data);

	float3 albedo = srgb_eotf_inv(gbuffer_data.albedo);
	float3 brdf = albedo / PI;

	ShadowResult celestial_shadow = get_celestial_shadow(pos_scene);

	float3 radiance = celestial_shadow.visibility
		* saturate(dot(gbuffer_data.normal_world, buf_global.light_dir_world))
		* buf_global.celestial_light_irradiance * brdf;

	radiance += sh_evaluate_irradiance(
					buf_sky_sh.coeff,
					gbuffer_data.normal_world,
					1.0
				)
		* pow2(gbuffer_data.lightmap.y) * brdf;

	radiance = atmosphere.apply_aerial_perspective(
		tex_atmosphere_aerial_perspective,
		tex_atmosphere_transmittance_lut,
		pos_screen,
		pos_scene,
		radiance
	);

	return FragmentOutput(radiance);
}


