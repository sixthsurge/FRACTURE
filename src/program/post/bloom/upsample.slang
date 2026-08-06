import aperture;

Texture2D<float3> input;
extern static const int DST_LOD;

struct FragmentOutput {
	float3 upsampled;
}

[shader("fragment")]
FragmentOutput main(float2 coord: SV_Position) {
	int w, h, levels;
	input.GetDimensions(DST_LOD, w, h, levels);

	int2 icoord = int2(coord);
	float2 ncoord = coord / float2(w, h);

	float3 upsampled = input.Load(int3(icoord, DST_LOD))
		+ input.sampleLinearLevel(ncoord, DST_LOD + 1);

	return FragmentOutput(upsampled);
}


