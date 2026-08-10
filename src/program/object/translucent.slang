import aperture;
import lib.atmosphere;
import lib.mat_ids;
import lib.lighting.brdf;
import lib.lighting.main_lighting;
import lib.lighting.material;
import lib.ssrt;
import lib.util.color;
import lib.util.math;
import lib.util.random;
import lib.util.space_conversion;
import object_shader;
import settings;

Texture2D<float3> tex_scene;
Texture2D<float3> tex_atmosphere_sky_view;
Texture2D<float> tex_blue_noise;

struct FragmentOutput {
	float4 color;
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
		float4 specular_map = float4(0.0, 0.0, 0.0, 0.1);

		if (let normal_tex = object_data.normal()) {
			normal_map = normal_tex.sampleLevel(input.uv, 2);
		}
		if (let specular_tex = object_data.specular()) {
			specular_map = specular_tex.sampleTexture(input.uv);
		}

		float3 pos_view = scene_to_view(input.pos_scene);
		float3 pos_screen = view_to_screen(pos_view);
		int2 icoord = int2(pos_screen.xy * ap.game.renderSize);
		float2 dither = float2(
			tex_blue_noise[icoord & 511],
			tex_blue_noise[(icoord + int2(93, 41)) & 511]
		);

		float3 flat_normal_world
			= unpackUnorm4x8ToFloat(input.normal_packed).xyz * 2.0 - 1.0;
		float4 tangent_world
			= unpackUnorm4x8ToFloat(input.tangent_packed) * 2.0 - 1.0;

		float3 detail_normal_world = flat_normal_world;
		if (max_of(abs(tangent_world)) > EPS && all(normal_map.xy > 1.0 / 255.0)
			&& all(normal_map.xy < 1.0 - 1.0 / 255.0)) {
			float3x3 tbn = float3x3(
				tangent_world.xyz,
				cross(flat_normal_world, tangent_world.xyz)
					* sign(tangent_world.w),
				flat_normal_world
			);

			NormalMapData normal_map_data = NormalMapData.unpack(normal_map);
			detail_normal_world = mul(normal_map_data.normal_tangent, tbn);
		}

		albedo.rgb = srgb_eotf_inv(albedo.rgb);

		Material material = Material.get(albedo.rgb, input.id);
		material.apply_specular_map(specular_map);

		float3 radiance = calculate_outgoing_radiance(
			material,
			input.pos_scene,
			normalize(input.pos_scene),
			flat_normal_world,
			detail_normal_world,
			input.lightmap,
			dither
		);

		float3 dir_view = normalize(pos_view);
		float3 dir_world = normalize(input.pos_scene);
		float3 ray_dir_view = reflect(
			dir_view,
			mul(float3x3(ap.camera.view), detail_normal_world)
		);

		float3 ray_dir_screen = ssrt.screen_space_ray_direction(
			pos_screen,
			pos_view,
			ray_dir_view
		);
		Ray ray = Ray(pos_screen, ray_dir_screen);

		if (input.id == MAT_WATER) {
			float3 reflected_radiance;
			if (let hit_pos = ssrt.trace_hiz(
					ray,
					ssrt.screen_space_ray_length(ray),
					ssrt.thickness_heuristic(pos_view, ray_dir_screen)
				)) {
				reflected_radiance = tex_scene.sampleLinear(hit_pos.xy);
			} else {
				reflected_radiance = atmosphere.lookup_sky_radiance(
					tex_atmosphere_sky_view,
					mul(float3x3(ap.camera.viewInv), ray_dir_view),
				);
			}

			radiance = reflected_radiance / max(albedo.a, EPS);
			albedo.a = 1.0;
		}

		return FragmentOutput(float4(radiance, albedo.a));
	}
}


