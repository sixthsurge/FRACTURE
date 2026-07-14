import aperture;

extern static const int LOD_DST;

RWTexture2D<float>[] tex_depth_hiz;

[shader("compute")]
[numthreads(8, 8)]
void main(uint3 thread_id: SV_DispatchThreadID) {
	int2 src_pos = int2(thread_id.xy) * 2;

	float s00, s10, s01, s11;
	if (LOD_DST == -1) {
		s00 = ap.opaqueDepth[src_pos + int2(0, 0)].x;
		s10 = ap.opaqueDepth[src_pos + int2(1, 0)].x;
		s01 = ap.opaqueDepth[src_pos + int2(0, 1)].x;
		s11 = ap.opaqueDepth[src_pos + int2(1, 1)].x;
	} else {
		s00 = tex_depth_hiz[LOD_DST].Load(src_pos + int2(0, 0)).x;
		s10 = tex_depth_hiz[LOD_DST].Load(src_pos + int2(1, 0)).x;
		s01 = tex_depth_hiz[LOD_DST].Load(src_pos + int2(0, 1)).x;
		s11 = tex_depth_hiz[LOD_DST].Load(src_pos + int2(1, 1)).x;
	}

	tex_depth_hiz[LOD_DST + 1].Store(
		int2(thread_id.xy),
		max(max(s00, s10), max(s10, s11))
	);
}


