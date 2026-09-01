// Perform initial sampling and temporal resampling.

import aperture;
import lib.lighting.restir_gi;
import lib.surface.material;
import lib.surface.gbuffer_packing;
import lib.util.color;
import lib.util.math;
import lib.util.space_conversion;
import lib.util.random;
import settings;

import lib.util.debug;

Texture2D<uint4> tex_gbuffer_opaque;

RWTexture2D<float4> tex_reserviour_temporal_1;
RWTexture2D<float4> tex_reserviour_temporal_2;
RWTexture2D<float4> tex_reserviour_temporal_3;
RWTexture2D<float4> tex_reserviour_temporal_4;
Texture2D<float4> tex_reserviour_temporal_1_prev;
Texture2D<float4> tex_reserviour_temporal_2_prev;
Texture2D<float4> tex_reserviour_temporal_3_prev;
Texture2D<float4> tex_reserviour_temporal_4_prev;

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID) {
	float depth = ap.depth[icoord];
	if (depth == 0.0) {
		return;
	}

	uint4 gbuffer_packed = tex_gbuffer_opaque[icoord];

	float3 pos_screen = float3((icoord + 0.5) / ap.game.renderSize, depth);
	float3 pos_view = screen_to_view(pos_screen);
	float3 pos_scene = view_to_scene(pos_view);
	float3 dir_world
		= normalize(pos_scene - translation_part(ap.camera.viewInv));
	float3 pos_world = pos_scene + ap.camera.position;

	OpaqueGbuffer gbuffer = OpaqueGbuffer.unpack(gbuffer_packed);

	Material material = Material.get(gbuffer.albedo, gbuffer.mat_id);
	if (userSettings.LABPBR_SUPPORT_ENABLED) {
		material.apply_specular_map(gbuffer.specular_map.get().value);
	}

	uint random_seed
		= ap.timing.frameCounter * (ap.game.renderSize.x * ap.game.renderSize.y)
		+ icoord.y * ap.game.renderSize.x + icoord.x;
	PcgRandom random = PcgRandom(random_seed);

	float3 detail_normal_world
		= gbuffer.detail_normal_world.get().orElse(gbuffer.flat_normal_world);
	restir_gi.Sample sample = restir_gi.initial_sample(
		random,
		material,
		pos_world,
		dir_world,
		gbuffer.flat_normal_world,
		detail_normal_world,
	);

	// Reproject.
	float3 pos_prev_view
		= transform(ap.temporal.view, pos_world - ap.temporal.position);
	float3 pos_prev_screen
		= view_to_screen(pos_prev_view, ap.temporal.projection);
	int2 icoord_prev = int2(pos_prev_screen.xy * ap.game.renderSize);

	// Target function.
	float p_hat_q = restir_gi.target_function(sample);
	// PDF of sampling routine (cos-weighted).
	// float p_q = sample.cos_theta() * rcp(PI);
	float p_q = 1.0;
	float w = p_hat_q / p_q;

	restir_gi.Reserviour temporal_reserviour;
	if (all(clamp(icoord_prev, int2(0), ap.game.renderSize - 1) == icoord_prev)
		&& ap.timing.frameCounter != 0) {
		temporal_reserviour.load_interpolated(
			tex_reserviour_temporal_1_prev,
			tex_reserviour_temporal_2_prev,
			tex_reserviour_temporal_3_prev,
			tex_reserviour_temporal_4_prev,
			icoord_prev,
			pos_prev_screen.xy,
		);
		temporal_reserviour.update(random, sample, w, 30);
		temporal_reserviour.clamp_M(30.0);
	} else {
		temporal_reserviour.init(sample, w);
	}
	if (distance(pos_world, temporal_reserviour.sample.visible_pos_world) > 1.0
		|| dot(detail_normal_world,
			   temporal_reserviour.sample.visible_normal_world)
			< 0.75) {
		temporal_reserviour.init(sample, w);
	}

	temporal_reserviour.W = temporal_reserviour.w
		/ (temporal_reserviour.M
		   * restir_gi.target_function(temporal_reserviour.sample));

	/*
	debug.show_tonemapped(
		icoord,
		all(icoord.x < 0.5 * ap.game.renderSize.x)
			? temporal_reserviour.sample.radiance * temporal_reserviour.W
				* temporal_reserviour.sample.cos_theta()
			: sample.radiance
	);
	*/

	temporal_reserviour.store(
		tex_reserviour_temporal_1,
		tex_reserviour_temporal_2,
		tex_reserviour_temporal_3,
		tex_reserviour_temporal_4,
		icoord
	);
}


