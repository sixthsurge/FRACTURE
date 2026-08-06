public module exposure;

import lib.util.math;
import settings;

namespace exposure {
// Exposure controls.
static const int HISTOGRAM_BIN_COUNT = 256;
static const float MIN_LUMINANCE = 0.003;
static const float MAX_LUMINANCE = 10.0;
static const float BIAS = -2.0;

float luminance_to_exposure(float luminance) { return exp2(BIAS) / luminance; }

float exposure_to_luminance(float exposure) { return exp2(BIAS) / exposure; }

float luminance_to_bin(float luminance) {
	if (luminance <= MIN_LUMINANCE) {
		return 0.0; // Avoid taking log of 0
	}

	return min(
		HISTOGRAM_BIN_COUNT
			* linstep(
				log2(MIN_LUMINANCE),
				log2(MAX_LUMINANCE),
				log2(luminance)
			),
		float(HISTOGRAM_BIN_COUNT) - 1.0
	);
}

float bin_to_luminance(int bin) {
	return exp2(lerp(
		log2(MIN_LUMINANCE),
		log2(MAX_LUMINANCE),
		float(bin) / float(HISTOGRAM_BIN_COUNT)
	));
}
}


