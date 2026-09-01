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
	int between_percentiles = 0;
	float target_luminance = 0.0;

	for (int i = 0; i < 256 && !(bin_a.hasValue && bin_b.hasValue); ++i) {
		int count = tex_exposure_histogram[int2(i, 0)];

		cdf += count;

		if (cdf > histogram_target_cdf_a && !bin_a.hasValue) {
			bin_a = i;
			between_percentiles = 1;
		}
		if (cdf > histogram_target_cdf_b && !bin_b.hasValue) {
			bin_b = i;
			between_percentiles = 1;
		}

		target_luminance += exposure.bin_to_luminance(i) * between_percentiles;
	}

	target_luminance /= float(abs(bin_a.value - bin_b.value) + 1);

	// Calculate exposure.

	float target = exposure.luminance_to_exposure(target_luminance);
	float previous = max0(buf_exposure[0].previous_value);
	float current_weight = select(
		ap.timing.frameCounter > 1,
		saturate(ap.timing.lastFrameTime * select(previous < target, 1.5, 4.0)),
		1.0
	);

	buf_exposure[0].value = lerp(previous, target, current_weight);
	buf_exposure[0].previous_value = buf_exposure[0].value;
	buf_exposure[0].bin_a = bin_a.orElse(0);
	buf_exposure[0].bin_b = bin_b.orElse(0);
}


