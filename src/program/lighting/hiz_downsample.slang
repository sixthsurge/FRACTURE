// Create Hi-Z depth chain with closest and furthest depth in RG channels using
// FidelityFX-SPD. Integration following GPU integration guide.
/*
Copyright (c) 2020 Advanced Micro Devices, Inc. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/

import aperture;
import lib.util.math;

globallycoherent RWTexture2D[] imgDst;

struct SpdGlobalAtomicBuffer {
	uint counter;
}

globallycoherent RWStructuredBuffer<SpdGlobalAtomicBuffer> spdGlobalAtomic;

extern static const int mips;
extern static const int numWorkGroups;
static const float2 workGroupOffset = float2(0.0);

#define A_GPU 1
#define A_HLSL 1

#include "third_party/fidelityfx_spd/ffx_a.h"

// Define LDS variables
groupshared AF4 spdIntermediate[16][16];
groupshared AU1 spdCounter;

// Load from source image
AF4 SpdLoadSourceImage(ASU2 tex, AU1 slice) { return ap.depth[tex]; }

// SpdLoad() takes a 32-bit signed integer 2D coordinate and loads color.
// Loads the 5th mip level, each value is computed by a different thread group
// last thread group will access all its elements and compute the subsequent
// mips reminder: if non-power-of-2 textures, add border controls if you do not
// want to read zeros past the border
AF4 SpdLoad(ASU2 tex, AU1 slice) {
	const int LOD = 5;
	int w, h;
	imgDst[LOD].GetDimensions(w, h);
	return imgDst[LOD][clamp(tex, int2(0), int2(w, h))];
}

void SpdStore(ASU2 pix, AF4 value, AU1 mip, AU1 slice) {
	imgDst[mip][pix] = value;
}

void SpdIncreaseAtomicCounter(AU1 slice) {
	InterlockedAdd(spdGlobalAtomic[0].counter, 1, spdCounter);
}

AU1 SpdGetAtomicCounter() { return spdCounter; }

void SpdResetAtomicCounter(AU1 slice) { spdGlobalAtomic[0].counter = 0; }

AF4 SpdLoadIntermediate(AU1 x, AU1 y) { return spdIntermediate[x][y]; }

void SpdStoreIntermediate(AU1 x, AU1 y, AF4 value) {
	spdIntermediate[x][y] = value;
}

AF4 SpdReduce4(AF4 v0, AF4 v1, AF4 v2, AF4 v3) {
	return AF4(
		min_of(float4(v0.x, v1.x, v2.x, v3.x)),
		max_of(float4(v0.y, v1.y, v2.y, v3.y)),
		0.0,
		0.0
	);
}

#include "third_party/fidelityfx_spd/ffx_spd.h"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 WorkGroupId: SV_GroupID, uint LocalThreadIndex: SV_GroupIndex) {
	SpdDownsample(
		AU2(WorkGroupId.xy),
		AU1(LocalThreadIndex),
		AU1(mips),
		AU1(numWorkGroups),
		AU1(WorkGroupId.z)
	);
}

[shader("compute")]
[numthreads(1)]
void zero_spd_global_atomic() { spdGlobalAtomic[0].counter = 0; }


