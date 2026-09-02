import aperture;
import lib.util.math;
import object_shader;

struct FragmentOutput {}

struct VertexOutput {
	float2 uv : TEXCOORD;
}

struct Object : Shader<VertexOutput, FragmentOutput> {
	static void emitVertex(
		Vertex v,
		ObjectTransforms transforms,
		out VertexOutput output,
		out float4 pos_clip
	) {
		float3 pos_scene = v.pos().xyz;
		pos_clip = project(
			transforms.projection,
			transform(transforms.view, pos_scene)
		);

		output.uv = v.uv();
	}

	static FragmentOutput
	shadeSurface(PixelData object_data, VertexOutput input) {
		if (let texture = object_data.albedo()) {
			ap.discardCutout(texture.sampleTexture(input.uv));
		}
		return FragmentOutput();
	}
}


