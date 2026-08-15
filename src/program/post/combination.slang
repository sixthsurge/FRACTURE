import aperture;
import lib.buffer.exposure;
import lib.post.tonemapping;
import lib.util.dithering;
import settings;

Texture2D<float3> tex_scene;
Texture2D<float3> tex_bloom;
Texture2D<float> tex_blue_noise;

ConstantBuffer<ExposureBuffer> buf_exposure;
Texture2D<uint> tex_exposure_histogram;

float3 apply_bloom(int2 icoord, float2 ncoord, float3 input) {
	// Final upsampling step from lod 1 to lod 0
	// Blurred lod 0 in bloom_tiles_a
	// Blurred lod 1 in:
	//   Even tile count => bloom_tiles_tex_a
	//   Odd  tile count => bloom_tiles_tex_b

	if (!userSettings.BLOOM_ENABLED) {
		return input;
	}

	float3 bloom_0 = tex_bloom[icoord];
	float3 bloom_1 = tex_bloom.sampleLinearLevel(ncoord, 1);

	float3 bloom = (bloom_0 + bloom_1) / userSettings.BLOOM_TILE_COUNT;
	// return tex_bloom_a.sampleLinearLevel(ncoord, 1);
	return lerp(input, bloom, userSettings.BLOOM_INTENSITY);
}

[shader("pixel")]
float4 main(float2 coord: SV_Position) {
	int2 icoord = int2(coord);
	float2 ncoord = (icoord + 0.5) / ap.game.screenSize;

	float3 color = tex_scene[icoord];
	float dither = tex_blue_noise[icoord & 511];

	color = apply_bloom(icoord, ncoord, color);

	if (userSettings.AUTO_EXPOSURE_ENABLED) {
		color *= buf_exposure.value;
	} else {
		color *= userSettings.MANUAL_EXPOSURE_VALUE;
	}

	color = tonemap_agx(color);

	color = dither_8bit(color, dither);

	// NB: do not need to apply sRGB EOTF as this is built into Hejl-Burgess.

	if (userSettings.DISPLAY_LUMINANCE_HISTOGRAM) {
		const int2 scale = int2(4);
		int2 pos = icoord / scale;
		if (pos.x < 256) {
			if (tex_exposure_histogram[int2(pos.x, 0)] > pos.y * 1000) {
				color = float3(0.0);
			}
			if (pos.x == buf_exposure.bin_a) {
				color += float3(0.5, 0.0, 0.0);
			}
			if (pos.x == buf_exposure.bin_b) {
				color += float3(0.0, 0.5, 0.0);
			}
		}
	}

	return float4(color, 1.0);
}


