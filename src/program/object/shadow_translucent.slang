import aperture;
import lib.surface.mat_ids;
import lib.surface.water_waves;
import lib.util.math;
import lib.volumetrics.water_medium;
import object_shader;
import settings;

struct FragmentOutput {
	float3 color;
}

struct VertexOutput {
	float2 uv : TEXCOORD;
	float2 lightmap;
	float3 pos_scene;
	nointerpolation uint color_packed;
	nointerpolation uint normal_packed;
	nointerpolation uint id;
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

		float3 normal_world = v.normal().orElse(-normalize(pos_scene.xyz));

		output.uv = v.uv();
		output.lightmap
			= linstep(float2(1.0 / 32.0), float2(31.0 / 32.0), v.lightCoord());
		output.pos_scene = pos_scene.xyz;
		output.color_packed = packUnorm4x8(v.color());
		output.normal_packed
			= packUnorm4x8(float4(normal_world * 0.5 + 0.5, 1.0));
		output.id
			= select(v.blockID().hasValue, v.blockID().value.data.customId, 0);
	}

	static FragmentOutput
	shadeSurface(PixelData object_data, VertexOutput input) {
		float3 color;
		if (input.id == MAT_WATER) {
			float caustics = 1.0;
			if (userSettings.WATER_CAUSTICS) {
				float3 flat_normal_world = float3(0, 1, 0);
				float3x3 tbn
					= float3x3(-1.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0);

				WaterWaves.Params params = WaterWaves.init_params(
					tbn,
					normalize(input.pos_scene),
					flat_normal_world,
					1.0
				);
				caustics = WaterWaves.calculate_caustics(
					params,
					tbn,
					input.pos_scene + ap.camera.position,
					5.0
				);
			}
			color = caustics * exp(-BASE_WATER_ABSORPTION_COEFF * 5.0);
		} else {
			float4 color4 = unpackUnorm4x8ToFloat(input.color_packed);
			if (let texture = object_data.albedo()) {
				color4 *= texture.sampleTexture(input.uv);
				ap.discardCutout(color4);
			}
			color = lerp(float3(1.0), color4.rgb, color4.a);
		}

		return FragmentOutput(color);
	}
}


