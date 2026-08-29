RWTexture3D<uint2> tex_voxel_face_data;

[shader("compute")]
[numthreads(8, 8, 4)]
void main(int3 icoord: SV_DispatchThreadID) {
	tex_voxel_face_data[icoord] = uint2(0);
}


