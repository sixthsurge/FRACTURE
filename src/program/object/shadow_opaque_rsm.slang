import aperture;
import lib.util.encoding;
import lib.util.math;
import object_shader;

struct FragmentOutput {
	uint2 data;
}

struct VertexOutput {
	float2 uv : TEXCOORD;
	float skylight;
	nointerpolation uint color_packed;
	nointerpolation uint normal_packed;
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
		output.skylight = linstep(1.0 / 32.0, 31.0 / 32.0, v.lightCoord().y);
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

		float2 normal_octahedral = encode_octahedral(normal);
		uint normal_packed = pack_unorm_arb(
			float4(normal_octahedral, 0.0, 0.0),
			uint4(4, 4, 0, 0)
		);

		uint2 data;
		data.x = packUnorm4x8(float4(color.rgb, input.skylight));
		data.y = packUnorm2x16(encode_octahedral(normal));
		return FragmentOutput(data);
	}
}


