import aperture;
import lib.gbuffer_packing;
import lib.util.math;
import object_shader;

Texture2D blockAtlasN;
Texture2D blockAtlasS;

struct FragmentOutput {
	uint4 packed_gbuffer_data;
}

struct VertexOutput {
	float2 uv : TEXCOORD;
	float2 lightmap;

	nointerpolation uint id;
	nointerpolation uint color_packed;
	nointerpolation uint normal_packed;
	nointerpolation uint tangent_packed;
}

struct TerrainObject : Shader<VertexOutput, FragmentOutput> {
	static void
	emitVertex(Vertex v, out VertexOutput output, out float4 pos_scene) {
		pos_scene = v.pos();

		float3 normal_world = v.normal().orElse(-normalize(pos_scene.xyz));
		float4 tangent_world = v.tangent().orElse(float4(0.0));

		output.uv = v.uv();
		output.lightmap
			= linstep(float2(1.0 / 32.0), float2(31.0 / 32.0), v.lightCoord());
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

		float4 normal_map = blockAtlasN.sampleNearest(input.uv);
		float4 specular_map = blockAtlasS.sampleNearest(input.uv);

		float3 flat_normal_world
			= unpackUnorm4x8ToFloat(input.normal_packed).xyz * 2.0 - 1.0;
		float4 tangent_world
			= unpackUnorm4x8ToFloat(input.tangent_packed) * 2.0 - 1.0;

		float3x3 tbn = float3x3(
			tangent_world.xyz,
			cross(flat_normal_world, tangent_world.xyz) * sign(tangent_world.w),
			flat_normal_world
		);
		float3 detail_normal_world;
		detail_normal_world.xy = normal_map.xy * 2.0 - 1.0;
		detail_normal_world.z = sqrt(
			saturate(1.0 - dot(detail_normal_world.xy, detail_normal_world.xy))
		);
		detail_normal_world = mul(detail_normal_world, tbn);

		return FragmentOutput(
			GbufferData(
				albedo.rgb,
				flat_normal_world,
				input.lightmap,
				0,
				detail_normal_world,
				specular_map
			)
				.pack()
		);
	}
}


