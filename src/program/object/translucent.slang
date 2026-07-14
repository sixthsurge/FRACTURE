import aperture;
import lib.gbuffer_packing;
import lib.lighting.celestial_shadow;
import lib.ssrt;
import lib.util.color;
import lib.util.math;
import lib.util.space_conversion;
import object_shader;
import settings;

Texture2D<float3> tex_scene;

struct FragmentOutput {
	float4 color;
}

struct VertexOutput {
	float2 uv : TEXCOORD;
	float2 lightmap;
	float3 pos_scene;

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
		output.color_packed = packUnorm4x8(v.color());
		output.normal_packed = packUnorm4x8(float4(normal_world, 1.0));
	}

	static FragmentOutput
	shadeSurface(PixelData object_data, VertexOutput input) {
		var albedo = unpackUnorm4x8ToFloat(input.color_packed);
		if (let albedo_tex = object_data.albedo()) {
			albedo *= albedo_tex.sampleTexture(input.uv);
		}
		ap.discardCutout(albedo);

		float3 normal_world = unpackUnorm4x8ToFloat(input.normal_packed).xyz;

		float3 radiance = srgb_eotf_inv(albedo.rgb);
		float opacity = albedo.a;

		ShadowResult celestial_shadow = get_celestial_shadow(input.pos_scene);

		radiance *= celestial_shadow.visibility
				* max(0, dot(normal_world, buf_global.light_dir_world)) * 0.8
			+ 0.2;

		float3 pos_view = scene_to_view(input.pos_scene);
		float3 pos_screen = view_to_screen(pos_view);
		float3 dir_view = normalize(pos_view);
		float3 ray_dir_view
			= reflect(dir_view, mul(float3x3(ap.camera.view), normal_world));

		float3 ray_dir_screen
			= normalize(view_to_screen(pos_view + ray_dir_view) - pos_screen);

		if (let hit = raymarch_depth_hiz(pos_screen, ray_dir_screen)) {
			float3 hit_color
				= tex_scene.Sample(apt_linearSampler, hit.pos_screen.xy);
			radiance = hit_color;
			opacity = 1;
		}

		return FragmentOutput(float4(radiance, opacity));
	}
}


