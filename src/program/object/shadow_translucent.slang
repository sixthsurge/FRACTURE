import aperture;
import lib.util.encoding;
import object_shader;

struct FragmentOutput {
	float4 color_and_normal;
}

struct VertexOutput {
	float2 uv : TEXCOORD;
	nointerpolation uint color_packed;
	nointerpolation uint normal_packed;
}

struct Object : Shader<VertexOutput, FragmentOutput> {
	static void emitVertex(Vertex v, out VertexOutput output, out float4 pos) {
		pos = v.pos();
		output.uv = v.uv();
		output.color_packed = packUnorm4x8(v.color());
		output.normal_packed = packUnorm4x8(
			float4(v.normal().orElse(float3(0.0, 1.0, 0.0)) * 0.5 + 0.5, 0.0)
		);
	}

	static FragmentOutput
	shadeSurface(PixelData object_data, VertexOutput input) {
		float4 color = unpackUnorm4x8ToFloat(input.color_packed);
		if (let texture = object_data.albedo()) {
			color *= texture.sampleTexture(input.uv);
			ap.discardCutout(color);
		}
		float3 normal
			= unpackUnorm4x8ToFloat(input.normal_packed).xyz * 2.0 - 1.0;
		color.rgb = lerp(float3(1.0), color.rgb, color.a);

		float2 normal_octahedral = encode_octahedral(normal);
		uint normal_packed = pack_unorm_arb(
			float4(normal_octahedral, 0.0, 0.0),
			uint4(4, 4, 0, 0)
		);

		return FragmentOutput(
			float4(color.rgb, float(normal_packed) * rcp(255.0))
		);
	}
}


