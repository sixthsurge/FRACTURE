import aperture;

Texture2D<float3> input_smaller;
Texture2D<float3> input_bigger;
extern static const int DST_LOD;

struct FragmentOutput {
	float3 upsampled;
}

[shader("fragment")]
FragmentOutput main(float2 coord: SV_Position) {
	int w, h, levels;
	input_bigger.GetDimensions(DST_LOD, w, h, levels);

	int2 icoord = int2(coord);
	float2 ncoord = coord / float2(w, h);

	float3 upsampled = input_bigger.Load(int3(icoord, DST_LOD))
		+ input_smaller.sampleLinearLevel(ncoord, DST_LOD + 1);

	return FragmentOutput(upsampled);
}


