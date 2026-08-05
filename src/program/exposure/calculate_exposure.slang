import aperture;
import lib.post.exposure;
import lib.buffer.exposure;
import lib.util.math;
import settings;

RWStructuredBuffer<ExposureBuffer> buf_exposure;

Texture2D<uint> tex_exposure_histogram;

[shader("compute")]
[numthreads(1, 1, 1)]
void main() {
	// Find median luminance.

	int histogram_target_cdf = int(
		userSettings.EXPOSURE_TARGET * ap.game.screenSize.x
		* ap.game.screenSize.y
	);

	int cdf = 0;
	int best_bin = 0;

	for (int i = 0; i < 256; ++i) {
		int count = tex_exposure_histogram[int2(i, 0)];

		cdf += count;

		if (cdf > histogram_target_cdf) {
			best_bin = i;
			break;
		}
	}

	float median_luminance = exposure.bin_to_luminance(int(best_bin));

	// Calculate exposure.

	const float blend_factor = saturate(4.0 * ap.timing.lastFrameTime);

	buf_exposure[0].value = lerp(
		max0(buf_exposure[0].previous_value),
		exposure.luminance_to_exposure(median_luminance),
		blend_factor
	);
	buf_exposure[0].previous_value = buf_exposure[0].value;
	buf_exposure[0].selected_bin = best_bin;
}


