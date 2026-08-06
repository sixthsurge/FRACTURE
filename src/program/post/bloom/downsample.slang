import aperture;

Texture2D<float3> dest;
Texture2D<float3> input;
extern static const int INPUT_LOD;

struct FragmentOutput {
	float3 downsampled;
}

[shader("fragment")]
FragmentOutput main(float2 coord: SV_Position) {
	int input_w, input_h, input_levels;
	input.GetDimensions(INPUT_LOD, input_w, input_h, input_levels);

	int dest_w, dest_h, dest_levels;
	dest.GetDimensions(INPUT_LOD + 1, dest_w, dest_h, dest_levels);

	float2 ncoord = coord / float2(dest_w, dest_h);
	float2 input_pixel_size = 1.0 / float2(input_w, input_h);

	// 6x6 downsampling filter made from overlapping 4x4 box kernels
	// As described in "Next Generation Post-Processing in Call of Duty
	// Advanced Warfare"
	float3 downsampled
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

	return FragmentOutput(downsampled);
}


