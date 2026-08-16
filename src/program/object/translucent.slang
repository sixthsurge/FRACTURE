import aperture;
import lib.atmosphere;
import lib.mat_ids;
import lib.lighting.main_lighting;
import lib.lighting.material;
import lib.gbuffer_packing;
import lib.fog;
import lib.util.color;
import lib.util.math;
import lib.util.random;
import lib.util.space_conversion;
import object_shader;
import settings;

Texture2D<float> tex_blue_noise;
Texture3D<float3> tex_fog_volume_integrated_light;
Texture3D<float3> tex_fog_volume_integrated_extinction;

struct FragmentOutput {
	float4 color;
	uint2 gbuffer;
}

struct VertexOutput {
	float2 uv : TEXCOORD;
	float2 lightmap;
	float3 pos_scene;

	nointerpolation uint id;
	nointerpolation uint color_packed;
	nointerpolation uint normal_packed;
	nointerpolation uint tangent_packed;
}

struct TranslucentObject : Shader<VertexOutput, FragmentOutput> {
	static void
	emitVertex(Vertex v, out VertexOutput output, out float4 pos_scene) {
		pos_scene = v.pos();

		float3 normal_world = v.normal().orElse(-normalize(pos_scene.xyz));
		float4 tangent_world = v.tangent().orElse(float4(0.0));

		output.uv = v.uv();
		output.lightmap
			= linstep(float2(1.0 / 32.0), float2(31.0 / 32.0), v.lightCoord());
		output.pos_scene = pos_scene.xyz;
		output.id
			= select(v.blockID().hasValue, v.blockID().value.data.customId, 0);
		output.color_packed = packUnorm4x8(v.color());
		output.normal_packed
			= packUnorm4x8(float4(normal_world * 0.5 + 0.5, 1.0));
		output.tangent_packed = packUnorm4x8(tangent_world * 0.5 + 0.5);
	}

	static FragmentOutput
	shadeSurface(PixelData object_data, VertexOutput input) {
		var albedo = unpackUnorm4x8ToFloat(input.color_packed);
		if (let albedo_tex = object_data.albedo()) {
			albedo *= albedo_tex.sampleTexture(input.uv);
		}
		ap.discardCutout(albedo);

		float4 normal_map = float4(0.5, 0.5, 1.0, 1.0);
		float4 specular_map = float4(0.0);
		if (userSettings.LABPBR_SUPPORT_ENABLED) {
			if (let normal_tex = object_data.normal()) {
				normal_map = normal_tex.sampleLevel(input.uv, 2);
			}
			if (let specular_tex = object_data.specular()) {
				specular_map = specular_tex.sampleTexture(input.uv);
			}
		}

		float3 pos_view = scene_to_view(input.pos_scene);
		float3 pos_screen = view_to_screen(pos_view);
		int2 icoord = int2(pos_screen.xy * ap.game.renderSize);
		float2 dither = float2(
			tex_blue_noise[icoord & 511],
			tex_blue_noise[(icoord + int2(93, 41)) & 511]
		);
		// Lookup fog participation a while before using it (latency hiding).
		fog.FogParticipation fog_participation = fog.lookup_fog_participation(
			tex_fog_volume_integrated_light,
			tex_fog_volume_integrated_extinction,
			pos_screen,
			pos_view
		);

		float3 flat_normal_world
			= unpackUnorm4x8ToFloat(input.normal_packed).xyz * 2.0 - 1.0;
		float4 tangent_world
			= unpackUnorm4x8ToFloat(input.tangent_packed) * 2.0 - 1.0;

		float3 detail_normal_world = flat_normal_world;
		if (userSettings.LABPBR_SUPPORT_ENABLED) {
			if (max_of(abs(tangent_world)) > EPS
				&& !all(normal_map == normal_map.xxxx)) {
				float3x3 tbn = float3x3(
					tangent_world.xyz,
					cross(tangent_world.xyz, flat_normal_world)
						* sign(tangent_world.w),
					flat_normal_world
				);

				NormalMapData normal_map_data
					= NormalMapData.unpack(normal_map);
				detail_normal_world = mul(normal_map_data.normal_tangent, tbn);
			}
		}

		Material material = Material.get(srgb_eotf_inv(albedo.rgb), input.id);
		if (userSettings.LABPBR_SUPPORT_ENABLED && input.id != MAT_WATER) {
			material.apply_specular_map(specular_map);
		}

		float3 radiance = calculate_outgoing_radiance(
			material,
			input.pos_scene,
			normalize(input.pos_scene),
			flat_normal_world,
			detail_normal_world,
			input.lightmap,
			1.0,
			0.0,
			detail_normal_world,
			dither
		);

		radiance = fog_participation.apply(radiance);

		TranslucentGbuffer gbuffer;
		gbuffer.normal_world = detail_normal_world;
		gbuffer.mat_id = input.id;
		gbuffer.skylight = input.lightmap.y;
		if (userSettings.LABPBR_SUPPORT_ENABLED) {
			bool is_albedo_metal = all(material.f0 == material.albedo);
			gbuffer.specular_map_rg.set(specular_map.rg);
			gbuffer.albedo_for_albedo_metals.set(
				select(is_albedo_metal, material.albedo, none)
			);
		}

		return FragmentOutput(float4(radiance, albedo.a), gbuffer.pack());
	}
}


