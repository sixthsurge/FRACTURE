import aperture;

RWTexture2D<float3>[] dest;
Texture2D<float3> input;
extern static const int INPUT_LOD;

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID) {
	const int DST_LOD = INPUT_LOD + 1;

	int dest_w, dest_h;
	dest[DST_LOD].GetDimensions(dest_w, dest_h);

	if (any(icoord >= int2(dest_w, dest_h))) {
		return;
	}
	float2 ncoord = (float2(icoord) + 0.5) / float2(dest_w, dest_h);

	int input_w, input_h, input_levels;
	input.GetDimensions(INPUT_LOD, input_w, input_h, input_levels);
	float2 input_pixel_size = 1.0 / float2(input_w, input_h);

	// 6x6 downsampling filter made from overlapping 4x4 box kernels
	// As described in "Next Generation Post-Processing in Call of Duty
	// Advanced Warfare"
	dest[DST_LOD][icoord]
		= input.sampleLinearLevel(
				   ncoord + float2(0.0, 0.0) * input_pixel_size,
				   INPUT_LOD
		  )
				.rgb
			* 0.125

		+ input.sampleLinearLevel(
				   ncoord + float2(1.0, 1.0) * input_pixel_size,
				   INPUT_LOD
		  )
				.rgb
			* 0.125
		+ input.sampleLinearLevel(
				   ncoord + float2(-1.0, 1.0) * input_pixel_size,
				   INPUT_LOD
		  )
				.rgb
			* 0.125
		+ input.sampleLinearLevel(
				   ncoord + float2(1.0, -1.0) * input_pixel_size,
				   INPUT_LOD
		  )
				.rgb
			* 0.125
		+ input.sampleLinearLevel(
				   ncoord + float2(-1.0, -1.0) * input_pixel_size,
				   INPUT_LOD
		  )
				.rgb
			* 0.125

		+ input.sampleLinearLevel(
				   ncoord + float2(2.0, 0.0) * input_pixel_size,
				   INPUT_LOD
		  )
				.rgb
			* 0.0625
		+ input.sampleLinearLevel(
				   ncoord + float2(-2.0, 0.0) * input_pixel_size,
				   INPUT_LOD
		  )
				.rgb
			* 0.0625
		+ input.sampleLinearLevel(
				   ncoord + float2(0.0, 2.0) * input_pixel_size,
				   INPUT_LOD
		  )
				.rgb
			* 0.0625
		+ input.sampleLinearLevel(
				   ncoord + float2(0.0, -2.0) * input_pixel_size,
				   INPUT_LOD
		  )
				.rgb
			* 0.0625

		+ input.sampleLinearLevel(
				   ncoord + float2(2.0, 2.0) * input_pixel_size,
				   INPUT_LOD
		  )
				.rgb
			* 0.03125
		+ input.sampleLinearLevel(
				   ncoord + float2(-2.0, 2.0) * input_pixel_size,
				   INPUT_LOD
		  )
				.rgb
			* 0.03125
		+ input.sampleLinearLevel(
				   ncoord + float2(2.0, -2.0) * input_pixel_size,
				   INPUT_LOD
		  )
				.rgb
			* 0.03125
		+ input.sampleLinearLevel(
				   ncoord + float2(-2.0, -2.0) * input_pixel_size,
				   INPUT_LOD
		  )
				.rgb
			* 0.03125;
}


