import aperture;
import object_shader;

struct FragmentOutput {
	float3 color;
}

struct VertexOutput {
	float2 uv : TEXCOORD;
	nointerpolation uint color_packed;
}

struct ShadowObject : Shader<VertexOutput, FragmentOutput> {
	static void emitVertex(Vertex v, out VertexOutput output, out float4 pos) {
		pos = v.pos();
		output.uv = v.uv();
		output.color_packed = packUnorm4x8(v.color());
	}

	static FragmentOutput
	shadeSurface(PixelData object_data, VertexOutput input) {
		float4 color = unpackUnorm4x8ToFloat(input.color_packed);
		if (let texture = object_data.albedo()) {
			color *= texture.sampleTexture(input.uv);
			ap.discardCutout(color);
		}
		color.rgb = lerp(float3(1.0), color.rgb, color.a);
		color.rgb = lerp(color.rgb, float3(0.0), color.a);
		return FragmentOutput(color.rgb);
	}
}


