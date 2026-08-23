import aperture;
import lib.util.filtering;

RWTexture2D<float3>[] dest;
Texture2D<float3> input_smaller;
Texture2D<float3> input_bigger;
extern static const int DST_LOD;

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID) {
	int w, h;
	dest[DST_LOD].GetDimensions(w, h);
	if (any(icoord >= int2(w, h))) {
		return;
	}

	float2 ncoord = (float2(icoord) + 0.5) / float2(w, h);

	// I use bicubic upsampling for coarser LoDs, where its effects are more
	// benefical and the performance effect is lower.
	float3 upsampled;
	if (DST_LOD <= 3) {
		upsampled = input_smaller.sampleLinearLevel(ncoord, DST_LOD + 1);
	} else {
		upsampled = input_smaller.sample_bicubic(ncoord, DST_LOD + 1);
	}

	dest[DST_LOD][icoord]
		= input_bigger.Load(int3(icoord, DST_LOD)) + upsampled;
}


