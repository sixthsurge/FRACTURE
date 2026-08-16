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

	int histogram_target_cdf_a = int(
		userSettings.EXPOSURE_TARGET_A * ap.game.screenSize.x
		* ap.game.screenSize.y
	);
	int histogram_target_cdf_b = int(
		userSettings.EXPOSURE_TARGET_B * ap.game.screenSize.x
		* ap.game.screenSize.y
	);

	int cdf = 0;
	Optional<int> bin_a = none;
	Optional<int> bin_b = none;

	for (int i = 0; i < 256; ++i) {
		int count = tex_exposure_histogram[int2(i, 0)];

		cdf += count;

		if (cdf > histogram_target_cdf_a && !bin_a.hasValue) {
			bin_a = i;
		}
		if (cdf > histogram_target_cdf_b && !bin_b.hasValue) {
			bin_b = i;
		}
		if (bin_a.hasValue && bin_b.hasValue) {
			break;
		}
	}

	float luminance_a = exposure.bin_to_luminance(bin_a.orElse(0));
	float luminance_b = exposure.bin_to_luminance(bin_b.orElse(0));
	float target_luminance = lerp(luminance_a, luminance_b, 0.5);

	// Calculate exposure.

	float current_weight = select(
		ap.timing.frameCounter > 1,
		saturate(4.0 * ap.timing.lastFrameTime),
		1.0
	);

	buf_exposure[0].value = lerp(
		max0(buf_exposure[0].previous_value),
		exposure.luminance_to_exposure(target_luminance),
		current_weight
	);
	buf_exposure[0].previous_value = buf_exposure[0].value;
	buf_exposure[0].bin_a = bin_a.orElse(0);
	buf_exposure[0].bin_b = bin_b.orElse(0);
}


