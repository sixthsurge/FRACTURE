// Spatial resampling.

import aperture;
import lib.lighting.restir_gi;
import lib.surface.material;
import lib.surface.gbuffer_packing;
import lib.util.color;
import lib.util.math;
import lib.util.space_conversion;
import lib.util.random;
import lib.util.sampling;
import settings;

import lib.util.debug;

RWTexture2D<float4> tex_reserviour_spatial_1;
RWTexture2D<float4> tex_reserviour_spatial_2;
RWTexture2D<float4> tex_reserviour_spatial_3;
RWTexture2D<float4> tex_reserviour_spatial_4;
Texture2D<float4> tex_reserviour_spatial_1_prev;
Texture2D<float4> tex_reserviour_spatial_2_prev;
Texture2D<float4> tex_reserviour_spatial_3_prev;
Texture2D<float4> tex_reserviour_spatial_4_prev;
Texture2D<float4> tex_reserviour_temporal_1;
Texture2D<float4> tex_reserviour_temporal_2;
Texture2D<float4> tex_reserviour_temporal_3;
Texture2D<float4> tex_reserviour_temporal_4;
Texture2D<uint4> tex_gbuffer_opaque;
Texture2D<float> tex_noise_blue;

static const int MAX_ITERATIONS = 9;

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID) {
	float depth = ap.depth[icoord];
	if (depth == 0.0) {
		return;
	}

	float2 dither = float2(
		tex_noise_blue[icoord & 511],
		tex_noise_blue[(icoord + int2(93, 41)) & 511]
	);
	uint4 gbuffer_packed = tex_gbuffer_opaque[icoord];

	uint random_seed
		= ap.timing.frameCounter * (ap.game.renderSize.x * ap.game.renderSize.y)
		+ icoord.y * ap.game.renderSize.x + icoord.x;
	// Adding one then xorshifting to make sure RNG is different to the one used
	// for initial sampling and temporal reuse.
	PcgRandom random = PcgRandom(xorshift(random_seed));
	float2 ncoord = (float2(icoord) + 0.5) * rcp(float2(ap.game.renderSize));

	float3 pos_screen = float3((icoord + 0.5) / ap.game.renderSize, depth);
	float3 pos_view = screen_to_view(pos_screen);
	float3 pos_scene = view_to_scene(pos_view);
	float3 pos_world = pos_scene + ap.camera.position;
	float3 pos_prev_screen = view_to_screen(
		scene_to_view(pos_world - ap.temporal.position, ap.temporal.view),
		ap.temporal.projection
	);
	int2 icoord_prev = int2(pos_prev_screen.xy * ap.game.renderSize);

	OpaqueGbuffer gbuffer = OpaqueGbuffer.unpack(gbuffer_packed);
	float3 detail_normal_world
		= gbuffer.detail_normal_world.get().orElse(gbuffer.flat_normal_world);

	restir_gi.Reserviour spatial_reserviour;
	if (all(clamp(icoord_prev, int2(0), ap.game.renderSize - 1) == icoord_prev)
		&& ap.timing.frameCounter > 0) {
		spatial_reserviour.load_interpolated(
			tex_reserviour_spatial_1_prev,
			tex_reserviour_spatial_2_prev,
			tex_reserviour_spatial_3_prev,
			tex_reserviour_spatial_4_prev,
			icoord_prev,
			pos_prev_screen.xy
		);
		if (distance(pos_world, spatial_reserviour.sample.visible_pos_world)
				> 1.0
			|| dot(detail_normal_world,
				   spatial_reserviour.sample.visible_normal_world)
				< 0.75) {
			spatial_reserviour.load(
				tex_reserviour_temporal_1,
				tex_reserviour_temporal_2,
				tex_reserviour_temporal_3,
				tex_reserviour_temporal_4,
				icoord,
			);
		}
	} else {
		spatial_reserviour.load(
			tex_reserviour_temporal_1,
			tex_reserviour_temporal_2,
			tex_reserviour_temporal_3,
			tex_reserviour_temporal_4,
			icoord,
		);
	}

	dither = r2(ap.timing.frameCounter, dither);
	for (int i = 0; i < MAX_ITERATIONS; ++i) {
		float2 sample_ncoord = ncoord
			+ 0.05
				* sample_vogel_disc(
					i,
					MAX_ITERATIONS,
					TAU * dither.x,
					dither.y
				);
		int2 sample_icoord = clamp(
			int2(sample_ncoord * ap.game.renderSize),
			int2(0),
			ap.game.renderSize - 1
		);

		restir_gi.Reserviour reserviour_n;
		reserviour_n.load(
			tex_reserviour_temporal_1,
			tex_reserviour_temporal_2,
			tex_reserviour_temporal_3,
			tex_reserviour_temporal_4,
			sample_icoord,
		);

		if (distance(pos_world, reserviour_n.sample.visible_pos_world) > 1.0
			|| dot(detail_normal_world,
				   reserviour_n.sample.visible_normal_world)
				< 0.75) {
			continue;
		}

		float J = restir_gi.jacobian_determinant(
			reserviour_n.sample.visible_pos_world,
			reserviour_n.sample.sample_pos_world,
			pos_world,
			reserviour_n.sample.sample_normal_world,
		);
		if (J < EPS) {
			continue;
		}

		float p_hat_over_J = (restir_gi.target_function(reserviour_n.sample));

		if (any(isnan(reserviour_n.w))) {
			debug.show(icoord, float3(1.0));
		}
		// TODO visibility test

		spatial_reserviour.merge(random, reserviour_n, p_hat_over_J, 2000.0);
	}

	spatial_reserviour.W = spatial_reserviour.w
		/ (spatial_reserviour.M
		   * restir_gi.target_function(spatial_reserviour.sample));

	spatial_reserviour.clamp_M(2000.0);

	spatial_reserviour.store(
		tex_reserviour_spatial_1,
		tex_reserviour_spatial_2,
		tex_reserviour_spatial_3,
		tex_reserviour_spatial_4,
		icoord,
	);
}


