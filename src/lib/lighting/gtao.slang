public module gtao;

import aperture;
import lib.util.math;
import lib.util.space_conversion;

namespace gtao {
internal static const float RADIUS = 3.0; // Meters.
internal static const float FALLOFF_START = 0.75; // Fraction of radius.
internal static const int SLICE_COUNT = 2;
internal static const int HORIZON_STEP_COUNT = 4;

internal float integrate_arc(float2 h, float n, float cos_n) {
	float2 tmp = cos_n + 2.0 * h * sin(n) - cos(2.0 * h - n);
	return 0.25 * (tmp.x + tmp.y);
}

internal float compute_maximum_horizon_angle(
	float3 slice_dir_view,
	float3 viewer_dir,
	float3 pos_screen,
	float3 pos_view,
	float radius,
	float dither
) {
	const float STEP_GROWTH_RATIO = 2.0;
	const float INITIAL_STEP_SIZE_SCALE = STEP_GROWTH_RATIO == 1.0
		? 1.0 / float(HORIZON_STEP_COUNT)
		: (1.0 - STEP_GROWTH_RATIO)
			/ (1.0 - pow(STEP_GROWTH_RATIO, float(HORIZON_STEP_COUNT)));

	float step_size = (INITIAL_STEP_SIZE_SCALE * RADIUS) * radius;

	float max_cos_theta = -1.0;

	float2 ray_step
		= (view_to_screen(pos_view + slice_dir_view * step_size) - pos_screen)
			  .xy;
	float2 ray_pos = pos_screen.xy
		+ normalize(ray_step) * max_of(rcp(float2(ap.game.renderSize)));

	for (int i = 0; i < HORIZON_STEP_COUNT; ++i, ray_pos += ray_step) {
		float2 dithered_pos = ray_pos + dither * ray_step;
		int2 texel
			= int2(saturate(dithered_pos) * float2(ap.game.renderSize) - 0.5);
		float depth = ap.depth[texel];

		if (depth == 0.0) {
			continue;
		}

		float3 offset = screen_to_view(float3(dithered_pos, depth)) - pos_view;

		float len_sq = length_squared(offset);
		float norm = rsqrt(len_sq);

		float distance_falloff = pow4(
			linstep(FALLOFF_START * RADIUS, RADIUS, len_sq * norm * rcp(radius))
		);

		float cos_theta = dot(viewer_dir, offset) * norm;
		cos_theta = lerp(cos_theta, -1.0, distance_falloff);

		max_cos_theta = max(cos_theta, max_cos_theta);
		ray_step *= STEP_GROWTH_RATIO;
	}

	return fast_acos(clamp(max_cos_theta, -1.0, 1.0));
}

struct Result {
	float ao;
	float ambient_sss;
	float3 bent_normal;
}

Result calculate(
	float3 pos_screen,
	float3 pos_view,
	float3 normal_view,
	float2 dither
) {
	float ao = 0.0;
	float ambient_sss = 0.0;
	float3 bent_normal = float3(0.0);

	// Construct local working space
	float3 viewer_dir = normalize(-pos_view);
	float3 viewer_right = normalize(cross(float3(0.0, 1.0, 0.0), viewer_dir));
	float3 viewer_up = cross(viewer_dir, viewer_right);
	float3x3 local_to_view = float3x3(viewer_right, viewer_up, viewer_dir);

	// Reduce AO radius very close up, makes some screen-space artifacts less
	// obvious
	float ao_radius = max(
		0.25 + 0.75 * smoothstep(0.0, 81.0, length_squared(pos_view)),
		0.5
	);

	// Increase AO radius for LoD terrain (looks nice)
#ifdef LOD_MOD_ACTIVE
	if (is_lod) {
		ao_radius *= 3.0;
	}
#endif

	for (int i = 0; i < SLICE_COUNT; ++i) {
		float slice_angle = (i + dither.x) * (PI / float(SLICE_COUNT));

		float3 slice_dir = float3(cos(slice_angle), sin(slice_angle), 0.0);
		float3 slice_dir_view = mul(local_to_view, slice_dir);

		float3 ortho_dir = slice_dir - dot(slice_dir, viewer_dir) * viewer_dir;
		float3 axis = cross(slice_dir, viewer_dir);
		float3 projected_normal = normal_view - axis * dot(normal_view, axis);

		float len_sq = dot(projected_normal, projected_normal);
		float norm = rsqrt(len_sq);

		float sgn_gamma = sign(dot(ortho_dir, projected_normal));
		float cos_gamma = saturate(dot(projected_normal, viewer_dir) * norm);
		float gamma = sgn_gamma * fast_acos(cos_gamma);

		float2 max_horizon_angles;
		max_horizon_angles.x = compute_maximum_horizon_angle(
			-slice_dir_view,
			viewer_dir,
			pos_screen,
			pos_view,
			ao_radius,
			dither.y,
		);
		max_horizon_angles.y = compute_maximum_horizon_angle(
			slice_dir_view,
			viewer_dir,
			pos_screen,
			pos_view,
			ao_radius,
			dither.y,
		);

		ambient_sss += max0(max_horizon_angles.y - (0.5 * PI)) * rcp(PI);

		max_horizon_angles = gamma
			+ clamp(float2(-1.0, 1.0) * max_horizon_angles - gamma,
					-(0.5 * PI),
					0.5 * PI);
		ao += integrate_arc(max_horizon_angles, gamma, cos_gamma) * len_sq
			* norm;

		float bent_angle = dot(max_horizon_angles, float2(0.5));
		bent_normal
			+= viewer_dir * cos(bent_angle) + ortho_dir * sin(bent_angle);
	}

	const float albedo = 0.2; // albedo of surroundings (for multibounce approx)

	ao *= rcp(float(SLICE_COUNT));
	ambient_sss = saturate(ambient_sss * rcp(float(SLICE_COUNT)));
	ao = saturate(ao / (albedo * ao + (1.0 - albedo)));

	bent_normal = normalize(normalize(bent_normal) - 0.5 * viewer_dir);

	return Result(ao, ambient_sss, bent_normal);
}
}


