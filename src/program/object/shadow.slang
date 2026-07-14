import aperture;
import object_shader;

struct FragmentOutput {}

struct VertexOutput {
	float2 uv : TEXCOORD;
}

struct ShadowObject : Shader<VertexOutput, FragmentOutput> {
	static void emitVertex(Vertex v, out VertexOutput output, out float4 pos) {
		pos = v.pos();
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


