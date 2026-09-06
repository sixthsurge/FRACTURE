import aperture;
import lib.lighting.vxrt.write_face_data;
import lib.lighting.vxrt.util;
import lib.surface.gbuffer_packing;
import lib.surface.material;
import lib.surface.pom;
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

	Conditional<float3, userSettings.POM_ENABLED> pos_scene;
	nointerpolation Conditional<float2, userSettings.POM_ENABLED>
		atlas_tile_offset;
	nointerpolation Conditional<float2, userSettings.POM_ENABLED>
		atlas_tile_scale;
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
		pos_clip.xy += buf_global.taa_jitter * pos_clip.w;

		float3 normal_world = v.normal().orElse(-normalize(pos_scene.xyz));
		float4 tangent_world = v.tangent().orElse(float4(0.0));

		output.uv = v.uv();
		output.lightmap
			= linstep(float2(1.0 / 32.0), float2(31.0 / 32.0), v.lightCoord());
		output.id = 0;
		if (let block_id = v.blockID()) {
			output.id = block_id.data.customId;
		}
		output.color_packed = packUnorm4x8(v.color());
		output.overlay_color_packed
			= packUnorm4x8(v.overlayColor().orElse(float4(0.0, 0.0, 0.0, 1.0)));
		output.normal_packed
			= packUnorm4x8(float4(normal_world * 0.5 + 0.5, 1.0));
		output.tangent_packed = packUnorm4x8(tangent_world * 0.5 + 0.5);

		if (userSettings.POM_ENABLED) {
			output.pos_scene = pos_scene;

			if (let mid = v.midCoord()) {
				// Based on code sample from fayer3.
				float2 uv_minus_mid = output.uv - mid;
				output.atlas_tile_offset = min(output.uv, mid - uv_minus_mid);
				output.atlas_tile_scale = abs(uv_minus_mid) * 2.0;
			} else {
				output.atlas_tile_offset = float2(-1.0);
			}
		}

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
			float2 grid_size = atlas_dims
				* rcp(float(userSettings.RESOURCE_PACK_RESOLUTION));

			float2 mid = v.midCoord().value;
			float2 uv_minus_mid = output.uv - mid;
			float2 uv_topleft = min(output.uv, mid - uv_minus_mid);

			int face_index = face_index_from_normal(v.normal().value);

			write_voxel_face_data(pos, face_index, uv_topleft, v.color());
		}
	}

	static FragmentOutput
	shadeSurface(PixelData object_data, VertexOutput input) {
		float3 flat_normal_world
			= unpackUnorm4x8ToFloat(input.normal_packed).xyz * 2.0 - 1.0;

		float2 new_uv = input.uv;
		bool self_shadow = false;
		Optional<float3> slope_normal = none;
		float3x3 tbn;
		if (userSettings.LABPBR_SUPPORT_ENABLED) {
			float4 tangent_world
				= unpackUnorm4x8ToFloat(input.tangent_packed) * 2.0 - 1.0;

			tbn = float3x3(
				tangent_world.xyz,
				cross(tangent_world.xyz, flat_normal_world)
					* sign(tangent_world.w),
				flat_normal_world
			);

			if (userSettings.POM_ENABLED) {
				if (all(input.atlas_tile_offset.get().value >= 0.0)) {
					float3 dir_tangent = normalize(
						mul(tbn,
							input.pos_scene.get().value
								- translation_part(ap.camera.viewInv))
					);

					float2x2 uv_gradient
						= float2x2(ddx(input.uv), ddy(input.uv));

					if (object_data.normal().hasValue) {
						pom.Result result = pom.calculate(
							object_data,
							input.atlas_tile_offset.get().value,
							input.atlas_tile_scale.get().value,
							input.uv,
							dir_tangent,
							tbn,
							uv_gradient
						);
						new_uv = result.uv;
						slope_normal = result.slope_normal;
						self_shadow = result.self_shadow;
					}
				}
			}
		}

		float4 albedo = unpackUnorm4x8ToFloat(input.color_packed);

		if (let albedo_tex = object_data.albedo()) {
			albedo *= albedo_tex.sampleTexture(new_uv);
		}
		ap.discardCutout(albedo);

		float4 normal_map = float4(0.5, 0.5, 1.0, 1.0);
		float4 specular_map = float4(0.0);
		if (userSettings.LABPBR_SUPPORT_ENABLED) {
			if (let normal_tex = object_data.normal()) {
				normal_map = normal_tex.sampleTexture(new_uv);
			}
			if (let specular_tex = object_data.specular()) {
				specular_map = specular_tex.sampleTexture(new_uv);
			}
		}

		float4 overlay_color
			= unpackUnorm4x8ToFloat(input.overlay_color_packed);
		albedo.rgb = lerp(overlay_color.rgb, albedo.rgb, overlay_color.a);

		OpaqueGbuffer gbuffer;
		gbuffer.albedo = albedo.rgb;
		gbuffer.flat_normal_world = flat_normal_world;
		gbuffer.lightmap = input.lightmap;
		gbuffer.mat_id = input.id;

		if (userSettings.LABPBR_SUPPORT_ENABLED) {
			if (all(normal_map == normal_map.xxxx)) {
				// Workaround Aperture bug with missing normal maps.
				normal_map = float4(0.5, 0.5, 1.0, 1.0);
			}

			float3 detail_normal_world = flat_normal_world;
			NormalMapData normal_map_data = NormalMapData.unpack(normal_map);
			detail_normal_world
				= mul(slope_normal.orElse(normal_map_data.normal_tangent), tbn);

			gbuffer.detail_normal_world.set(detail_normal_world);
			gbuffer.specular_map.set(specular_map);
			gbuffer.texture_ao.set(normal_map_data.texture_ao);

			if (userSettings.POM_ENABLED) {
				gbuffer.parallax_self_shadow.set(self_shadow);
			}
		}

		return FragmentOutput(gbuffer.pack());
	}
}


