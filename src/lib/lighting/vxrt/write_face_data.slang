public module write_face_data;

// Format is:
// x- packUnorm2x16(uv_topleft)
// y- packUnorm4x8(color)
internal RWTexture3D<uint2> tex_voxel_face_data;

void write_voxel_face_data(
	int3 pos,
	int face_index,
	float2 uv_topleft,
	float4 color
) {
	int3 image_coord = pos;
	image_coord.x = image_coord.x * 6 + face_index;
	tex_voxel_face_data[image_coord]
		= uint2(packUnorm2x16(uv_topleft), packUnorm4x8(color));
}


