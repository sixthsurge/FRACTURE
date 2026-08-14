import aperture;
import lib.gbuffer_packing;
import lib.lighting.material;
import lib.util.math;
import object_shader;

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

struct BasicObject : Shader<VertexOutput, FragmentOutput> {
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

		float4 normal_map = float4(0.5, 0.5, 1.0, 1.0);
		float4 specular_map = float4(0.0, 0.0, 0.0, 0.1);

		if (let normal_tex = object_data.normal()) {
			normal_map = normal_tex.sampleTexture(input.uv);
		}
		if (let specular_tex = object_data.specular()) {
			specular_map = specular_tex.sampleTexture(input.uv);
		}

		float3 flat_normal_world
			= unpackUnorm4x8ToFloat(input.normal_packed).xyz * 2.0 - 1.0;
		float4 tangent_world
			= unpackUnorm4x8ToFloat(input.tangent_packed) * 2.0 - 1.0;

		float3 detail_normal_world = flat_normal_world;
		if (max_of(abs(tangent_world)) > EPS) {
			float3x3 tbn = float3x3(
				tangent_world.xyz,
				cross(tangent_world.xyz, flat_normal_world)
					* sign(tangent_world.w),
				flat_normal_world
			);

			NormalMapData normal_map_data = NormalMapData.unpack(normal_map);
			detail_normal_world = mul(normal_map_data.normal_tangent, tbn);
		}

		return FragmentOutput(
			GbufferData(
				albedo.rgb,
				flat_normal_world,
				input.lightmap,
				input.id,
				detail_normal_world,
				specular_map
			)
				.pack()
		);
	}
}


