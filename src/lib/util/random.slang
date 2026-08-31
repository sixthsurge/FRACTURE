public module random;

interface IRandom {
	[mutating]
	uint next();

	[mutating]
	float next_float() {
		// Source: https://stackoverflow.com/a/79656319.
		return (next() >> 8) * 0x1p-24f;
	}

	[mutating]
	float2 next_float2() { return float2(next_float(), next_float()); }

	[mutating]
	float3 next_float3() { return float3(next_float2(), next_float()); }

	[mutating]
	float4 next_float4() { return float4(next_float3(), next_float()); }
}

struct PcgRandom : IRandom {
	uint state;

	[mutating]
	uint next() {
		// Source:
		// https://github.com/riccardoscalco/glsl-pcg-prng/blob/main/index.glsl

		// ---------------------------------------------------------------------
		// License for shader version:
		// Copyright 2020 Riccardo Scalco

		// Permission is hereby granted, free of charge, to any person obtaining
		// a copy of this software and associated documentation files (the
		// "Software"), to deal in the Software without restriction, including
		// without limitation the rights to use, copy, modify, merge, publish,
		// distribute, sublicense, and/or sell copies of the Software, and to
		// permit persons to whom the Software is furnished to do so, subject to
		// the following conditions:

		// The above copyright notice and this permission notice shall be
		// included in all copies or substantial portions of the Software.

		// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
		// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
		// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
		// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
		// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
		// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
		// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
		// SOFTWARE.

		// ---------------------------------------------------------------------
		// Original license for PCG:
		// PCG Random Number Generation for C.
		//
		// Copyright 2014 Melissa O'Neill <oneill@pcg-random.org>
		//
		// Licensed under the Apache License, Version 2.0 (the "License");
		// you may not use this file except in compliance with the License.
		// You may obtain a copy of the License at
		//
		//     http://www.apache.org/licenses/LICENSE-2.0
		//
		// Unless required by applicable law or agreed to in writing, software
		// distributed under the License is distributed on an "AS IS" BASIS,
		// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
		// implied. See the License for the specific language governing
		// permissions and limitations under the License.
		//
		// For additional information about the PCG random number generation
		// scheme, including its license and other licensing options, visit
		//
		//     http://www.pcg-random.org

		uint state = state * uint(747796405) + uint(2891336453);
		uint word = ((state >> ((state >> uint(28)) + uint(4))) ^ state)
			* uint(277803737);
		this.state = (word >> uint(22)) ^ word;
		return state;
	}
}

// From thebbq in shaderLABS.
uint xorshift(uint value) {
	// Xorshift*32
	value ^= value << 13;
	value ^= value >> 17;
	value ^= value << 5;
	return value;
}

// -----------------------------------------------------------------------------
// R_n low-discrepency sequences from
// http://extremelearning.com.au/unreasonable-effectiveness-of-quasirandom-sequences/

static const float PHI_1
	= 1.6180339887; // Golden ratio, solution to x^2 = x + 1
static const float PHI_2
	= 1.3247179572; // Plastic constant, solution to x^3 = x + 1
static const float PHI_3 = 1.2207440846; // Solution to x^4 = x + 1

float r1(int n, float seed) {
	const float alpha = 1.0 / PHI_1;
	return frac(seed + n * alpha);
}

float r1(int n) { return r1(n, 0.5); }

float r1_next(float u) {
	const float alpha = 1.0 / PHI_1;
	return frac(u + alpha);
}

float2 r2(int n, float2 seed) {
	const float2 alpha = 1.0 / float2(PHI_2, PHI_2 * PHI_2);
	return frac(seed + n * alpha);
}

float2 r2(int n) { return r2(n, float2(0.5)); }

float2 r2_next(float2 u) {
	const float2 alpha = 1.0 / float2(PHI_2, PHI_2 * PHI_2);
	return frac(u + alpha);
}

float3 r3(int n, float3 seed) {
	const float3 alpha
		= 1.0 / float3(PHI_3, PHI_3 * PHI_3, PHI_3 * PHI_3 * PHI_3);
	return frac(seed + n * alpha);
}

float3 r3(int n) { return r3(n, float3(0.5)); }

float3 r3_next(float3 u) {
	const float3 alpha
		= 1.0 / float3(PHI_3, PHI_3 * PHI_3, PHI_3 * PHI_3 * PHI_3);
	return frac(u + alpha);
}

// -----------------------------------------------------------------------------
// Float hash functions from https://www.shadertoy.com/view/4djSRW
// License:
/* Copyright (c)2014 David Hoskins.
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.*/

float hash1(float p) {
	p = fract(p * .1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash1(float2 p) {
	float3 p3 = fract(float3(p.xyx) * .1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash1(float3 p3) {
	p3 = fract(p3 * .1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float2 hash2(float p) {
	float3 p3 = fract(float3(p) * float3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float2 hash2(float2 p) {
	float3 p3 = fract(float3(p.xyx) * float3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float2 hash2(float3 p3) {
	p3 = fract(p3 * float3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float3 hash3(float p) {
	float3 p3 = fract(float3(p) * float3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

float3 hash3(float2 p) {
	float3 p3 = fract(float3(p.xyx) * float3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

float3 hash3(float3 p3) {
	p3 = fract(p3 * float3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

float4 hash4(float p) {
	float4 p4 = fract(float4(p) * float4(.1031, .1030, .0973, .1099));
	p4 += dot(p4, p4.wzxy + 33.33);
	return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

float4 hash4(float2 p) {
	float4 p4 = fract(float4(p.xyxy) * float4(.1031, .1030, .0973, .1099));
	p4 += dot(p4, p4.wzxy + 33.33);
	return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

float4 hash4(float3 p) {
	float4 p4 = fract(float4(p.xyzx) * float4(.1031, .1030, .0973, .1099));
	p4 += dot(p4, p4.wzxy + 33.33);
	return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

float4 hash4(float4 p4) {
	p4 = fract(p4 * float4(.1031, .1030, .0973, .1099));
	p4 += dot(p4, p4.wzxy + 33.33);
	return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}


