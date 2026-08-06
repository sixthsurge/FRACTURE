import aperture;
import lib.atmosphere;
import lib.buffer.sky_sh;
import lib.gbuffer_packing;
import lib.sky_view_projection;
import lib.lighting.brdf;
import lib.lighting.celestial_shadow;
import lib.lighting.material;
import lib.util.color;
import lib.util.math;
import lib.util.space_conversion;
import lib.util.spherical_harmonics;
import settings;

Texture2D<uint4> tex_packed_gbuffer_data;
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

	uint4 packed_gbuffer_data = tex_packed_gbuffer_data[icoord];
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

	Material material = Material.get(albedo);
	material.apply_specular_map(gbuffer_data.specular_map);
	float3 brdf = albedo / PI;

	float3 normal_world = gbuffer_data.detail_normal_world;

	float3 radiance = float3(0.0);

	if (dot(gbuffer_data.flat_normal_world, buf_global.light_dir_world)
		>= EPS) {
		ShadowResult shadow = get_celestial_shadow(pos_scene);
		float NoL = dot(normal_world, buf_global.light_dir_world);
		float NoV = saturate(dot(normal_world, -dir_world));
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

	radiance += sh_evaluate_irradiance(
					buf_sky_sh.coeff,
					gbuffer_data.flat_normal_world,
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


