public module trace;

import aperture;
import lib.lighting.vxrt.util;
import lib.surface.material;
import lib.util.color;
import lib.util.math;
import settings;

namespace vxrt {
internal Texture2D blockAtlas;
internal Texture2D blockAtlasS;
internal Texture2D blockAtlasN;
internal Texture3D<uint2> tex_voxel_face_data;

internal struct Hit {
	internal int3 voxel;
	internal int3 normal;
	internal float3 pos_world;
}

struct Surface {
	Material material;
	float3 pos_world;
	float3 normal;
	float opacity;
}

Optional<Surface> trace(Ray ray, int max_steps, out float3 tint) {
	// Straightforward implementation of
	// http://www.cse.yorku.ca/~amana/research/grid.pdf.
	int3 current_voxel = int3(floor(ray.o));
	int3 sign_d = int3(sign(ray.d));
	float3 rcp_d = rcp(ray.d);
	float3 t_max = (step(0.0, ray.d) - frac(ray.o)) * rcp_d;
	float3 t_delta = rcp(abs(ray.d));
	tint = float3(1.0);

	for (int i = 0; i < max_steps; ++i) {
		// Original paper has a lot of logic that amounts to stepping by
		// step.{component} in the component where t_max is minimal.
		bool3 minimal_component = t_max == min_of(t_max);
		current_voxel += int3(minimal_component) * sign_d;

		if (ap.voxel[current_voxel] != -1) {
			int3 last_voxel = current_voxel - int3(minimal_component) * sign_d;

			Surface s = get_hit_surface(
				Hit(current_voxel,
					last_voxel - current_voxel,
					float3(ray.o + min_of(t_max) * ray.d))
			);

			if (s.opacity > 0.99) {
				return s;
			} else {
				tint *= s.material.albedo;
			}
		}

		t_max += float3(minimal_component) * t_delta;
	}

	return none;
}

internal struct VoxelFaceData {
	internal float2 uv_top_left;
	internal float4 color;
}

internal VoxelFaceData get_voxel_face_data(int3 voxel_pos, float3 normal) {
	voxel_pos = voxel_pos - int3(floor(ap.camera.position))
		+ VOXEL_RT_VOLUME_SIZE / 2;
	if (any(voxel_pos != clamp(voxel_pos, int3(0), VOXEL_RT_VOLUME_SIZE - 1))) {
		return VoxelFaceData(float2(0.0), float4(0.0));
	}

	int face_index = face_index_from_normal(normal);
	int3 image_coord = voxel_pos;
	image_coord.x = image_coord.x * 6 + face_index;
	uint2 packed = tex_voxel_face_data[image_coord];

	float2 uv_top_left = unpackUnorm2x16ToFloat(packed.x);
	float4 color = unpackUnorm4x8ToFloat(packed.y);

	return VoxelFaceData(uv_top_left, color);
}

internal Surface get_hit_surface(Hit hit) {
	// why do local variables have to be internal??
	internal VoxelFaceData face = get_voxel_face_data(hit.voxel, hit.normal);

	int block_atlas_w, block_atlas_h;
	blockAtlas.GetDimensions(block_atlas_w, block_atlas_h);
	float2 atlas_dims = float2(block_atlas_w, block_atlas_h);
	float3x3 tbn = make_tbn_matrix(hit.normal);

	float2 uv = abs(
		frac(float2(dot(tbn[0], hit.pos_world), dot(tbn[1], hit.pos_world)))
	);
	uv = face.uv_top_left + uv * (16.0 / float2(block_atlas_w, block_atlas_h));

	float4 albedo = blockAtlas.sampleNearestLevel(uv, 0) * face.color;
	float4 specular_map = float4(0.0);
	if (userSettings.LABPBR_SUPPORT_ENABLED) {
		specular_map = blockAtlasS.sampleNearestLevel(uv, 0);
	}

	Material material = Material.get(srgb_eotf_inv(albedo.rgb), 0);
	if (userSettings.LABPBR_SUPPORT_ENABLED) {
		material.apply_specular_map(specular_map);
	}

	return Surface(material, hit.pos_world, hit.normal, albedo.a);
}

} // namespace vxrt


