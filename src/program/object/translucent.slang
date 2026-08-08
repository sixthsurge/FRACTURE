import aperture;
import lib.block_ids;
import lib.lighting.main_lighting;
import lib.lighting.material;
import lib.sky_view_projection;
import lib.ssrt;
import lib.util.color;
import lib.util.math;
import lib.util.space_conversion;
import object_shader;
import settings;

Texture2D<float3> tex_scene;
Texture2D<float3> tex_atmosphere_sky_view;

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
}

struct TranslucentObject : Shader<VertexOutput, FragmentOutput> {
	static void
	emitVertex(Vertex v, out VertexOutput output, out float4 pos_scene) {
		pos_scene = v.pos();

		float3 normal_world = v.normal().orElse(-normalize(pos_scene.xyz));

		output.uv = v.uv();
		output.lightmap
			= linstep(float2(1.0 / 32.0), float2(31.0 / 32.0), v.lightCoord());
		output.pos_scene = pos_scene.xyz;
		output.id = v.blockID().orElse(WorldBlock(0)).id;
		output.color_packed = packUnorm4x8(v.color());
		output.normal_packed
			= packUnorm4x8(float4(normal_world * 0.5 + 0.5, 1.0));
	}

	static FragmentOutput
	shadeSurface(PixelData object_data, VertexOutput input) {
		var albedo = unpackUnorm4x8ToFloat(input.color_packed);
		if (let albedo_tex = object_data.albedo()) {
			albedo *= albedo_tex.sampleTexture(input.uv);
		}
		ap.discardCutout(albedo);

		float3 normal_world
			= unpackUnorm4x8ToFloat(input.normal_packed).xyz * 2.0 - 1.0;

		albedo.rgb = srgb_eotf_inv(albedo.rgb);

		Material material = Material.get(albedo.rgb);

		float3 radiance = calculate_outgoing_radiance(
			material,
			input.pos_scene,
			normalize(input.pos_scene),
			normal_world,
			normal_world,
			input.lightmap
		);

		float3 pos_view = scene_to_view(input.pos_scene);
		float3 pos_screen = view_to_screen(pos_view);
		float3 dir_view = normalize(pos_view);
		float3 dir_world = normalize(input.pos_scene);
		float3 ray_dir_view
			= reflect(dir_view, mul(float3x3(ap.camera.view), normal_world));

		float3 ray_dir_screen = ssrt.screen_space_ray_direction(
			pos_screen,
			pos_view,
			ray_dir_view
		);
		Ray ray = Ray(pos_screen, ray_dir_screen);
		float ray_length = ssrt.screen_space_ray_length(ray);

		if (input.id == BLOCK_WATER) {
			float3 reflected_radiance;
			if (let hit = ssrt.trace_hiz(ap.opaqueDepth, ray, ray_length)) {
				reflected_radiance = tex_scene.sampleNearest(hit.pos_screen.xy);
			} else {
				reflected_radiance
					= tex_atmosphere_sky_view.sampleLinear(project_sky_view(
						mul(float3x3(ap.camera.viewInv), ray_dir_view)
					));
			}

			radiance = reflected_radiance / max(albedo.a, EPS);
			albedo.a = 1.0;
		}

		return FragmentOutput(float4(radiance, albedo.a));
	}
}


