public module trace;

import aperture;
import lib.lighting.voxel_rt.util;
import lib.util.math;
import settings;

namespace vxrt {
internal Texture3D<uint2> tex_voxel_face_data;

struct VoxelFaceData {
	float2 uv_top_left;
	float4 color;
}

Optional<VoxelFaceData> get_voxel_face_data(int3 voxel_pos, float3 normal) {
	voxel_pos = voxel_pos - int3(floor(ap.camera.position))
		+ VOXEL_RT_VOLUME_SIZE / 2;
	if (any(voxel_pos != clamp(voxel_pos, int3(0), VOXEL_RT_VOLUME_SIZE - 1))) {
		return none;
	}

	int face_index = face_index_from_normal(normal);
	int3 image_coord = voxel_pos;
	image_coord.x = image_coord.x * 6 + face_index;
	uint2 packed = tex_voxel_face_data[image_coord];

	float2 uv_top_left = unpackUnorm2x16ToFloat(packed.x);
	float4 color = unpackUnorm4x8ToFloat(packed.y);

	return VoxelFaceData(uv_top_left, color);
}

struct Hit {
	int3 voxel;
	int3 normal;
	float3 pos_world;
}

Optional<Hit> trace(Ray ray, int max_steps) {
	// Straightforward implementation of
	// http://www.cse.yorku.ca/~amana/research/grid.pdf.
	int3 current_voxel = int3(floor(ray.o));
	int3 sign_d = int3(sign(ray.d));
	float3 rcp_d = rcp(ray.d);
	float3 t_max = (step(0.0, ray.d) - frac(ray.o)) * rcp_d;
	float3 t_delta = rcp(abs(ray.d));

	for (int i = 0; i < max_steps; ++i) {
		// Original paper has a lot of logic that amounts to stepping by
		// step.{component} in the component where t_max is minimal.
		bool3 minimal_component = t_max == min_of(t_max);
		current_voxel += int3(minimal_component) * sign_d;

		if (ap.voxel[current_voxel] != -1) {
			int3 last_voxel = current_voxel - int3(minimal_component) * sign_d;
			return Hit(
				current_voxel,
				last_voxel - current_voxel,
				float3(
					last_voxel + min_of(t_max) * ray.d
					+ fract(ap.camera.position)
				)
			);
		}

		t_max += float3(minimal_component) * t_delta;
	}

	return none;
}
} // namespace vxrt


