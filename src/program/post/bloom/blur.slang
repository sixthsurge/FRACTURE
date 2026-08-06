extern static const int LOD;

static const int WORK_GROUP_SIZE = 64;
static const int FILTER_RADIUS = 4;
static const int SHARED_SIZE = WORK_GROUP_SIZE + FILTER_RADIUS * 4;

groupshared float3 preloaded[SHARED_SIZE];

RWTexture2D<float3> dest[];
Texture2D<float3> input;

void preload<bool VERTICAL>(int2 icoord, int2 group_coord, int local_index) {
	int w, h, levels;
	input.GetDimensions(LOD, w, h, levels);

	int group_base
		= (VERTICAL ? group_coord.y : group_coord.x) * WORK_GROUP_SIZE
		- FILTER_RADIUS;

	// Load area of SHARED_SIZE into `preloaded`
	for (int i = local_index; i < SHARED_SIZE; i += WORK_GROUP_SIZE) {
		int2 texel = VERTICAL ? int2(icoord.x, group_base + i)
							  : int2(group_base + i, icoord.y);
		texel = clamp(texel, int2(0), int2(w, h));

		preloaded[i] = input.Load(int3(texel, LOD));
	}
}

float3 blur<bool VERTICAL>(int2 icoord, int2 group_coord, int local_index) {
	const float binomial_weights_9[]
		= { 0.2734375, 0.21875, 0.109375, 0.03125, 0.00390625 };

	int w, h, levels;
	input.GetDimensions(LOD, w, h, levels);

	float3 color_sum = float3(0.0);
	float weight_sum = 0.0;

	for (int i = -FILTER_RADIUS; i <= FILTER_RADIUS; i++) {
		int2 sample_pos = icoord + (VERTICAL ? int2(0, i) : int2(i, 0));

		bool in_bounds
			= all(sample_pos == clamp(sample_pos, int2(0), int2(w, h)));

		float weight = binomial_weights_9[abs(i)] * float(in_bounds);

		color_sum += preloaded[local_index + FILTER_RADIUS + i] * weight;
		weight_sum += weight;
	}

	return color_sum / weight_sum;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void horizontal_main(
	int2 icoord: SV_DispatchThreadID,
	int2 group_coord: SV_GroupID,
	int local_index: SV_GroupIndex
) {
	preload<false>(icoord, group_coord, local_index);
	GroupMemoryBarrierWithGroupSync();
	dest[LOD][icoord] = blur<false>(icoord, group_coord, local_index);
}

[shader("compute")]
[numthreads(1, 64, 1)]
void vertical_main(
	int2 icoord: SV_DispatchThreadID,
	int2 group_coord: SV_GroupID,
	int local_index: SV_GroupIndex
) {
	preload<true>(icoord, group_coord, local_index);
	GroupMemoryBarrierWithGroupSync();
	dest[LOD][icoord] = blur<true>(icoord, group_coord, local_index);
}


