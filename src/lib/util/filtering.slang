public module filtering;

import aperture;
import lib.util.math;

internal float4 bicubic_weights(float v) {
	float4 n = float4(1.0, 2.0, 3.0, 4.0) - v;
	float4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	float w = 6.0 - x - y - z;
	return float4(x, y, z, w) * (1.0 / 6.0);
}

extension<T> Texture2D<T>
	where T : IArithmetic, IFloat, ITexelElement {
	internal T lerp_t(T a, T b, float blend) { return a + (b - a) * T(blend); }

	// 4-taps.
	T sample_bicubic(float2 coord, int lod) {
		// Source: https://stackoverflow.com/a/42179924.

		int w, h, levels;
		GetDimensions(lod, w, h, levels);
		float2 res = float2(w, h);
		float2 pixel_size = 1.0 / res;

		coord = coord * res - 0.5;

		float2 fxy = fract(coord);
		coord -= fxy;

		float4 x_weights = bicubic_weights(fxy.x);
		float4 y_weights = bicubic_weights(fxy.y);

		float4 c = coord.xxyy + float2(-0.5, 1.5).xyxy;

		float4 s
			= float4(x_weights.xz + x_weights.yw, y_weights.xz + y_weights.yw);
		float4 offset = c + float4(x_weights.yw, y_weights.yw) / s;

		offset *= pixel_size.xxyy;

		T sample0 = sampleLinearLevel(offset.xz, lod);
		T sample1 = sampleLinearLevel(offset.yz, lod);
		T sample2 = sampleLinearLevel(offset.xw, lod);
		T sample3 = sampleLinearLevel(offset.yw, lod);

		float sx = s.x / (s.x + s.y);
		float sy = s.z / (s.z + s.w);

		return lerp_t(
			lerp_t(sample3, sample2, sx),
			lerp_t(sample1, sample0, sx),
			sy
		);
	}

	// 9-taps.
	// Returns filtered value and confidence factor.
	Tuple<T, float> catmull_rom_filter(float2 coord, int lod) {
		// Source:
		// https://gist.github.com/TheRealMJP/c83b8c0f46b63f3a88a5986f4fa982b1.
		// License:
		/*
		MIT License

		Copyright (c) 2019 MJP

		Permission is hereby granted, free of charge, to any person obtaining a
		copy of this software and associated documentation files (the
		"Software"), to deal in the Software without restriction, including
		without limitation the rights to use, copy, modify, merge, publish,
		distribute, sublicense, and/or sell copies of the Software, and to
		permit persons to whom the Software is furnished to do so, subject to
		the following conditions:

		The above copyright notice and this permission notice shall be included
		in all copies or substantial portions of the Software.

		THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
		OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
		MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
		IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
		CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
		TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
		SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
		 */

		int w, h, levels;
		GetDimensions(lod, w, h, levels);
		float2 res = float2(w, h);
		float2 pixel_size = 1.0 / res;

		// We're going to sample a a 4x4 grid of texels surrounding the target
		// UV coordinate. We'll do this by rounding down the sample location to
		// get the exact center of our "starting" texel. The starting texel will
		// be at location [1, 1] in the grid, where [0, 0] is the top left
		// corner.
		float2 sample_pos = coord * res;
		float2 tex_pos_1 = floor(sample_pos - 0.5) + 0.5;

		// Compute the fractional offset from our starting texel to our original
		// sample location, which we'll feed into the Catmull-Rom spline
		// function to get our filter weights.
		float2 f = sample_pos - tex_pos_1;

		// Compute the Catmull-Rom weights using the fractional offset that we
		// calculated earlier. These equations are pre-expanded based on our
		// knowledge of where the texels will be located, which lets us avoid
		// having to evaluate a piece-wise function.
		float2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
		float2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
		float2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
		float2 w3 = f * f * (-0.5 + 0.5 * f);

		// Work out weighting factors and sampling offsets that will let us use
		// bilinear filtering to simultaneously evaluate the middle 2 samples
		// from the 4x4 grid.
		float2 w12 = w1 + w2;
		float2 offset12 = w2 / (w1 + w2);

		// Compute the final UV coordinates we'll use for sampling the texture
		float2 tex_pos_0 = tex_pos_1 - 1.0;
		float2 tex_pos_3 = tex_pos_1 + 2.0;
		float2 tex_pos_12 = tex_pos_1 + offset12;

		tex_pos_0 *= pixel_size;
		tex_pos_3 *= pixel_size;
		tex_pos_12 *= pixel_size;

		T result = T(0.0);
		result = result
			+ sampleLinearLevel(float2(tex_pos_0.x, tex_pos_0.y), lod)
				* T(w0.x * w0.y)
			+ sampleLinearLevel(float2(tex_pos_12.x, tex_pos_0.y), lod)
				* T(w12.x * w0.y)
			+ sampleLinearLevel(float2(tex_pos_3.x, tex_pos_0.y), lod)
				* T(w3.x * w0.y)

			+ sampleLinearLevel(float2(tex_pos_0.x, tex_pos_12.y), lod)
				* T(w0.x * w12.y)
			+ sampleLinearLevel(float2(tex_pos_12.x, tex_pos_12.y), lod)
				* T(w12.x * w12.y)
			+ sampleLinearLevel(float2(tex_pos_3.x, tex_pos_12.y), lod)
				* T(w3.x * w12.y)

			+ sampleLinearLevel(float2(tex_pos_0.x, tex_pos_3.y), lod)
				* T(w0.x * w3.y)
			+ sampleLinearLevel(float2(tex_pos_12.x, tex_pos_3.y), lod)
				* T(w12.x * w3.y)
			+ sampleLinearLevel(float2(tex_pos_3.x, tex_pos_3.y), lod)
				* T(w3.x * w3.y);

		// Calculate confidence-of-quality factor using UE method (maximum
		// weight)
		float confidence = max_of(float4(w0.x, w1.x, w2.x, w3.x))
			* max_of(float4(w0.y, w1.y, w2.y, w3.y));

		return makeTuple(result, confidence);
	}

	// Approximation from Siggraph 2016 SMAA presentation
	// Ignores the corner texels, reducing the overhead from 9 to 5 bilinear
	// samples.
	// 5 taps.
	T catmull_rom_filter_fast(float2 coord, int lod, float sharpness) {
		int w, h, levels;
		GetDimensions(lod, w, h, levels);
		float2 res = float2(w, h);
		float2 pixel_size = 1.0 / res;

		float2 position = res * coord;
		float2 center_position = floor(position - 0.5) + 0.5;
		float2 f = position - center_position;
		float2 f2 = f * f;
		float2 f3 = f * f2;

		float2 w0 = -sharpness * f3 + 2.0 * sharpness * f2 - sharpness * f;
		float2 w1 = (2.0 - sharpness) * f3 - (3.0 - sharpness) * f2 + 1.0;
		float2 w2 = -(2.0 - sharpness) * f3 + (3.0 - 2.0 * sharpness) * f2
			+ sharpness * f;
		float2 w3 = sharpness * f3 - sharpness * f2;

		float2 w12 = w1 + w2;
		float2 tc12 = pixel_size * (center_position + w2 / w12);
		T center_color = sampleLinearLevel(float2(tc12.x, tc12.y), lod);

		float2 tc0 = pixel_size * (center_position - 1.0);
		float2 tc3 = pixel_size * (center_position + 2.0);

		float l0 = w12.x * w0.y;
		float l1 = w0.x * w12.y;
		float l2 = w12.x * w12.y;
		float l3 = w3.x * w12.y;
		float l4 = w12.x * w3.y;

		T color = sampleLinearLevel(float2(tc12.x, tc0.y), lod) * T(l0)
			+ sampleLinearLevel(float2(tc0.x, tc12.y), lod) * T(l1)
			+ center_color * T(l2)
			+ sampleLinearLevel(float2(tc3.x, tc12.y), lod) * T(l3)
			+ sampleLinearLevel(float2(tc12.x, tc3.y), lod) * T(l4);

		return color / T(l0 + l1 + l2 + l3 + l4);
	}
}


