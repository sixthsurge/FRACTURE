import aperture;
import lib.gbuffer_packing;
import lib.util.math;
import object_shader;

struct FragmentOutput {
	uint2 packed_gbuffer_data;
}

struct VertexOutput {
	float2 uv : TEXCOORD;
	float2 lightmap;

	nointerpolation uint color_packed;
	nointerpolation uint normal_packed;
}

struct BasicObject : Shader<VertexOutput, FragmentOutput> {
	static void
	emitVertex(Vertex v, out VertexOutput output, out float4 pos_scene) {
		pos_scene = v.pos();

		float3 normal_world = v.normal().orElse(-normalize(pos_scene.xyz));

		output.uv = v.uv();
		output.lightmap
			= linstep(float2(1.0 / 32.0), float2(31.0 / 32.0), v.lightCoord());
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

		var normal_world = unpackUnorm4x8ToFloat(input.normal_packed).xyz;

		return {
			GbufferData(albedo.rgb, normal_world, input.lightmap, 0).pack()
		};
	}
}


