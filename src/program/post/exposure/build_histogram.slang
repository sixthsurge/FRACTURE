// Thanks to Bálint Csala for help optimizing this.

import aperture;
import lib.post.exposure;
import lib.util.color;
import lib.util.math;

groupshared uint local_histogram[256];

Texture2D<float3> tex_scene;
RWTexture2D<uint> tex_exposure_histogram;

void add_to_histogram(float luminance) {
	int bin_index = int(exposure.luminance_to_bin(luminance));
	InterlockedAdd(local_histogram[bin_index], 1u);
}

float fetch_luminance(int2 p) {
	return max0(dot(tex_scene[p], luminance_weights_rec709));
}

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID, int local_index: SV_GroupIndex) {
	// Zero local histogram.
	local_histogram[local_index] = 0;
	GroupMemoryBarrierWithGroupSync();

	// Both PIXELS_PER_THREAD_X and PIXELS_PER_THREAD_Y are 2.
	int2 pixel_pos = icoord * 2;

	// Reuse computation as much as possible
	bool inside00 = all(pixel_pos < ap.game.renderSize);
	bool inside10 = pixel_pos.x + 1 < ap.game.renderSize.x;
	bool inside01 = pixel_pos.y + 1 < ap.game.renderSize.y;

	if (inside00) {
		add_to_histogram(fetch_luminance(pixel_pos + int2(0, 0)));
	}
	if (inside10) {
		add_to_histogram(fetch_luminance(pixel_pos + int2(1, 0)));
	}
	if (inside01) {
		add_to_histogram(fetch_luminance(pixel_pos + int2(0, 1)));
	}
	if (inside10 && inside01) {
		add_to_histogram(fetch_luminance(pixel_pos + int2(1, 1)));
	}

	// Add local histogram to global histogram.
	GroupMemoryBarrierWithGroupSync();
	InterlockedAdd(
		tex_exposure_histogram[int2(local_index, 0)],
		local_histogram[local_index]
	);
}


