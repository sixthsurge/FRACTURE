import aperture;
import lib.atmospherics.atmosphere;
import lib.buffer.sky_sh;
import lib.util.math;
import lib.util.random;
import lib.util.sampling;
import lib.util.spherical_harmonics;

groupshared float3 thread_samples[256][9];

RWStructuredBuffer<SkyShBuffer> buf_sky_sh;

Texture2D<float3> tex_atmosphere_sky_view;

[shader("compute")]
[numthreads(256)]
void main(int i: SV_GroupIndex) {
	static const int THREAD_COUNT = 256;

	// Each thread represents one sample. First the shader samples the sky view
	// LUT in a uniformly random direction, then the threads' values are summed
	// via parallel reduction.

	// Sample radiance in a random direction.
	float3 direction = sample_uniform_hemisphere(float3(0.0, 1.0, 0.0), r2(i));

	float3 radiance
		= atmosphere.lookup_sky_radiance(tex_atmosphere_sky_view, direction);

	// Project into SH.
	float coeff[9] = sh_coeff_order_2(direction);
	[unroll]
	for (int band = 0; band < 9; ++band) {
		thread_samples[i][band]
			= radiance * coeff[band] * (TAU / float(THREAD_COUNT));
	}

	GroupMemoryBarrierWithGroupSync();

	// Sum across threads.
	[unroll]
	for (int stride = THREAD_COUNT / 2; stride > 0; stride /= 2) {
		if (i < stride) {
			for (int band = 0; band < 9; ++band) {
				thread_samples[i][band] += thread_samples[i + stride][band];
			}
		} else {
			return;
		}

		GroupMemoryBarrierWithGroupSync();
	}

	// Save to buffer.
	[unroll]
	for (int band = 0; band < 9; ++band) {
		buf_sky_sh[0].coeff[band] = thread_samples[0][band];
	}

	// I also precalculate the irradiance facing upwards for use in simple
	// lighting.
	buf_sky_sh[0].irradiance_up
		= sh_evaluate_irradiance(thread_samples[0], float3(0.0, 1.0, 0.0), 1.0);
}


