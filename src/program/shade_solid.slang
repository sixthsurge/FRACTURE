import aperture;
import lib.atmosphere;
import lib.gbuffer_packing;
import lib.lighting.main_lighting;
import lib.lighting.material;
import lib.fog;
import lib.sky;
import lib.util.color;
import lib.util.math;
import lib.util.random;
import lib.util.space_conversion;
import settings;

RWTexture2D<float3> tex_scene_write;
Texture2D<uint4> tex_gbuffer_solid;
Texture3D<float3> tex_atmosphere_aerial_perspective;
Texture2D<float3> tex_atmosphere_transmittance;
Texture3D<float3> tex_fog_volume_integrated_light;
Texture3D<float3> tex_fog_volume_integrated_extinction;
Texture2D<float4> tex_gtao_output_current;
Texture2D<float> tex_blue_noise;

[shader("compute")]
[numthreads(16, 16, 1)]
void main(int2 icoord: SV_DispatchThreadID) {
	float2 coord = float2(icoord) + 0.5;
	float2 ncoord = coord / float2(ap.game.renderSize);

	float depth = ap.opaqueDepth[icoord];
	uint4 packed_gbuffer = tex_gbuffer_solid[icoord];
	float2 dither = float2(
		tex_blue_noise[icoord & 511],
		tex_blue_noise[(icoord + int2(93, 41)) & 511]
	);

	float3 pos_screen = float3(ncoord, depth);
	float3 pos_view = screen_to_view(pos_screen);
	float4 gtao_output = tex_gtao_output_current.sampleLinear(ncoord);

	// Lookup fog participation a while before using it (latency hiding).
	fog.FogParticipation fog_participation = fog.lookup_fog_participation(
		tex_fog_volume_integrated_light,
		tex_fog_volume_integrated_extinction,
		pos_screen,
		pos_view
	);

	float3 pos_scene = view_to_scene(pos_view);
	float3 dir_world = normalize(pos_scene);

	if (depth == 0.0) {
		float3 radiance = calculate_sky_radiance(dir_world);
		radiance = fog_participation.apply(radiance);
		tex_scene_write[icoord] = radiance;
		return;
	}

	SolidGbuffer gbuffer = SolidGbuffer.unpack(packed_gbuffer);

	float3 albedo = srgb_eotf_inv(gbuffer.albedo);

	Material material = Material.get(albedo, gbuffer.mat_id);
	if (userSettings.LABPBR_SUPPORT_ENABLED) {
		material.apply_specular_map(gbuffer.specular_map.get().value);
	}

	float3 bent_normal_world = mul(
		float3x3(ap.camera.viewInv),
		float3(
			gtao_output.zw,
			sqrt(saturate(1.0 - length_squared(gtao_output.zw)))
		)
	);

	float3 radiance = calculate_outgoing_radiance(
		material,
		pos_scene,
		dir_world,
		gbuffer.flat_normal_world,
		gbuffer.detail_normal_world.get().orElse(gbuffer.flat_normal_world),
		gbuffer.lightmap,
		gtao_output.x,
		gtao_output.y,
		bent_normal_world,
		dither
	);

	if (userSettings.ATMOSPHERE_AP_LUT_ENABLED) {
		radiance = atmosphere.apply_aerial_perspective(
			tex_atmosphere_aerial_perspective,
			tex_atmosphere_transmittance,
			pos_screen,
			pos_scene,
			radiance
		);
	}

	radiance = fog_participation.apply(radiance);

	tex_scene_write[icoord] = radiance;
}


