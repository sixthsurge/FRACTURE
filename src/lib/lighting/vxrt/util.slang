public module util;

import lib.util.math;
import settings;

static const int3 VOXEL_RT_VOLUME_SIZE = int3(
	userSettings.VOXEL_RT_VOLUME_SIZE_X,
	userSettings.VOXEL_RT_VOLUME_SIZE_Y,
	userSettings.VOXEL_RT_VOLUME_SIZE_Z
);

int face_index_from_normal(float3 normal) {
	// +1, 0, 0 -> 0
	//  0,+1, 0 -> 1
	//  0, 0,+1 -> 2
	// -1, 0, 0 -> 3
	//  0,-1, 0 -> 4
	//  0, 0,-1 -> 5
	return clamp(
		int(dot(abs(normal), float3(0.0, 1.0, 2.0))
			+ max0(-dot(normal, float3(3.0))) + 0.5),
		0,
		5
	);
}


