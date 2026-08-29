import aperture;
import lib.lighting.vxrt.write_face_data;
import lib.lighting.vxrt.util;
import lib.surface.gbuffer_packing;
import lib.surface.material;
import lib.toggles;
import lib.util.math;
import object_shader;
import settings;

extern static const int USAGE_CURRENT;
extern static const int USAGE_BASIC;
extern static const int USAGE_TERRAIN_SOLID;
extern static const int USAGE_TERRAIN_CUTOUT;

Texture2D blockAtlas;

struct FragmentOutput {
	uint4 gbuffer;
}

struct VertexOutput {
	float2 uv : TEXCOORD;
	float2 lightmap;

	nointerpolation uint id;
	nointerpolation uint color_packed;
	nointerpolation uint overlay_color_packed;
	nointerpolation uint normal_packed;
	nointerpolation uint tangent_packed;
}

struct Object : Shader<VertexOutput, FragmentOutput> {
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
		output.overlay_color_packed
			= packUnorm4x8(v.overlayColor().orElse(float4(0.0, 0.0, 0.0, 1.0)));
		output.normal_packed
			= packUnorm4x8(float4(normal_world * 0.5 + 0.5, 1.0));
		output.tangent_packed = packUnorm4x8(tangent_world * 0.5 + 0.5);

		// world's worst voxelization
		if (toggle.VXRT_DATA
			&& (USAGE_CURRENT == USAGE_TERRAIN_SOLID
				|| USAGE_CURRENT == USAGE_TERRAIN_CUTOUT)
			&& v.blockID().value.id != -1) {
			int block_atlas_w, block_atlas_h;
			blockAtlas.GetDimensions(block_atlas_w, block_atlas_h);
			float2 atlas_dims = float2(block_atlas_w, block_atlas_h);

			int3 pos = int3(floor(
						   pos_scene.xyz + v.midBlock().orElse(float3(0.0))
						   + frac(ap.camera.position)
					   ))
				+ VOXEL_RT_VOLUME_SIZE / 2;
			float2 grid_size = atlas_dims * rcp(16.0);
			float2 uv_topleft = floor(v.uv() * grid_size) / grid_size;
			int face_index = face_index_from_normal(v.normal().value);

			write_voxel_face_data(pos, face_index, uv_topleft, v.color());
		}
	}

	override static float4
	transformClipSpace(float4 pos_clip, VertexOutput data) {
		pos_clip.xy += buf_global.taa_jitter * pos_clip.w;
		return pos_clip;
	}

	static FragmentOutput
	shadeSurface(PixelData object_data, VertexOutput input) {
		var albedo = unpackUnorm4x8ToFloat(input.color_packed);
		if (let albedo_tex = object_data.albedo()) {
			albedo *= albedo_tex.sampleTexture(input.uv);
		}
		ap.discardCutout(albedo);

		float4 normal_map = float4(0.5, 0.5, 1.0, 1.0);
		float4 specular_map = float4(0.0);
		if (userSettings.LABPBR_SUPPORT_ENABLED) {
			if (let normal_tex = object_data.normal()) {
				normal_map = normal_tex.sampleTexture(input.uv);
			}
			if (let specular_tex = object_data.specular()) {
				specular_map = specular_tex.sampleTexture(input.uv);
			}
		}

		float3 flat_normal_world
			= unpackUnorm4x8ToFloat(input.normal_packed).xyz * 2.0 - 1.0;

		float4 overlay_color
			= unpackUnorm4x8ToFloat(input.overlay_color_packed);
		albedo.rgb = lerp(overlay_color.rgb, albedo.rgb, overlay_color.a);

		OpaqueGbuffer gbuffer;
		gbuffer.albedo = albedo.rgb;
		gbuffer.flat_normal_world = flat_normal_world;
		gbuffer.lightmap = input.lightmap;
		gbuffer.mat_id = input.id;

		float4 tangent_world
			= unpackUnorm4x8ToFloat(input.tangent_packed) * 2.0 - 1.0;

		if (userSettings.LABPBR_SUPPORT_ENABLED) {
			float3 detail_normal_world = flat_normal_world;
			if (max_of(abs(tangent_world)) > EPS) {
				float3x3 tbn = float3x3(
					tangent_world.xyz,
					cross(tangent_world.xyz, flat_normal_world)
						* sign(tangent_world.w),
					flat_normal_world
				);

				NormalMapData normal_map_data
					= NormalMapData.unpack(normal_map);
				detail_normal_world = mul(normal_map_data.normal_tangent, tbn);
			}

			gbuffer.detail_normal_world.set(detail_normal_world);
			gbuffer.specular_map.set(specular_map);
		}

		return FragmentOutput(gbuffer.pack());
	}
}


