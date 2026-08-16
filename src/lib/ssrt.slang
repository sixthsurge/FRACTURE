// Hi-Z screen-space ray-tracing following //
// https://sugulee.wordpress.com/2021/01/19/screen-space-reflections-implementation-and-optimization-part-2-hi-z-tracing-method.
//
// The logic is basically the same as in the article, I just wanted to write it
// out it in my own words to make sure I understand it. I have also modified the
// algorithm to work with a Hi-Z map storing both the closest and furthest
// depth, to allow rays to pass efficiently behind the volume as well.
//
// As Aperture uses reverse Z, where the article refers to the minimum depth,
// we refer to the maximum.

public module ssrt;

import aperture;
import lib.util.math;
import lib.util.space_conversion;

namespace ssrt {
internal Texture2D<float2> tex_depth_hiz_min_max;

float3 screen_space_ray_direction(
	float3 ray_origin_screen,
	float3 ray_origin_view,
	float3 ray_dir_view
) {
	return normalize(
		view_to_screen(ray_origin_view + ray_dir_view) - ray_origin_screen
	);
}

/// Returns the distance to the edge of screen space.
float screen_space_ray_length(Ray ray_screen) {
	return min_of(
		abs(step(0.0, ray_screen.d) - ray_screen.o)
		/ max(abs(ray_screen.d), EPS)
	);
}

// Depth tolerance heuristic from DrDesten in sLABS (used with permission).
float thickness_heuristic(float3 pos_view, float3 ray_dir_screen) {
	return max(abs(ray_dir_screen.z) * 0.01, 0.02 / pow2(pos_view.z));
}

internal int2 depth_lod_size(int lod) {
	return max(1, ap.game.renderSize >> lod);
}

// Returns the distance to the next boundary between cells in the pixel grid, in
// the ray direction. This is used to push the ray onto the next cell.
internal float distance_to_cell_boundary(
	Ray ray,
	float2 cell_coord,
	float2 cell_count,
	float2 nearest_cell_boundary,
	float2 cross_offset,
) {
	// X and Y coordinates of the vertical and horizontal cell boundaries in
	// screen space.
	float2 boundary = (cell_coord + nearest_cell_boundary) / cell_count;

	// Small offset to make sure we end up in the next cell.
	boundary += cross_offset;

	// Intersect each plane and take the closest distance.
	return min_of((boundary - ray.o.xy) / ray.d.xy);
}

internal bool crossed_cell_boundary(float2 cell_a, float2 cell_b) {
	return any(int2(cell_a) != int2(cell_b));
}

internal float2 read_min_max_depth(int2 pos, int lod) {
	if (lod == 0) {
		return float2(ap.depth[pos]);
	} else {
		return tex_depth_hiz_min_max.Load(int3(pos, lod - 1));
	}
}

Optional<float3>
trace_hiz(Ray ray_screen, float ray_length, float thickness_heuristic) {
	const int MAX_STEPS = 50; // Limit the maximum number of steps.
	const int INITIAL_LOD = 5; // Lod at which to start tracing.
	const int STOP_LOD = 0; // Lod at which to stop tracing

	// Which cell boundaries are we stepping towards?
	float2 nearest_cell_boundary = step(
		0.0,
		ray_screen.d.xy
	); // crossStep in ththickness_heuristic article.

	// Small offset added to make sure we end up in the next cell after
	// advancing to the cell boundary.
	float2 cross_offset = (nearest_cell_boundary * 2.0 - 1.0)
		/ (float2(ap.game.renderSize) * 128.0);

	int current_lod = 2;
	int max_lod = int(ceil(log2(float(max_of(ap.game.renderSize))))) - 1;

	// Start the ray at the next cell boundary.
	float2 initial_cell_count = depth_lod_size(current_lod);
	float t = distance_to_cell_boundary(
		ray_screen,
		floor(ray_screen.o.xy * initial_cell_count),
		initial_cell_count,
		nearest_cell_boundary,
		cross_offset * 64.0 // See discussion in the article for why a
							// larger cross offset is used here.
	);
	bool travelling_towards_screen
		= ray_screen.d.z > 0.0; // isBackwardsRay in the article.

	int i = 0;
	while (i < MAX_STEPS && current_lod >= STOP_LOD && t < ray_length) {
		float2 cell_count = depth_lod_size(current_lod);
		float3 ray_pos = ray_screen.at(t);
		float2 ray_cell = floor(ray_pos.xy * cell_count);

		float2 depth_min_max = read_min_max_depth(int2(ray_cell), current_lod);

		// Stepping logic:
		// If we are in front of the volume and going away from the camera then
		// we want to move the ray either to the next cell or to the point where
		// it intersects the plane where the depth is the closest depth within
		// this cell. If we are in front of the volume and towards from the
		// camera we can always move to the next cell.
		//
		// If we are behind the volume then we want to move the ray either
		// to the next cell or to the point where it intersects the plane
		// where the depth is the furthest depth within this cell.
		// If we are behind the volume and going away from the camera we
		// can always move to the next cell.
		//
		// If we are inside the volume then we just want to keep the same
		// position and move to the finer-grained LOD. We do this by first
		// calculating the intersection point with the max depth plane, then
		// deciding whether it crossed a cell boundary, and if it crossed,
		// clipping it to the distance the cell boundary.
		bool behind_volume = ray_pos.z < depth_min_max.x - thickness_heuristic;
		bool inside_volume = !behind_volume && ray_pos.z < depth_min_max.y;
		// Depth of the plane we want to move towards:
		// - Behind volume: furthest depth plane.
		// - In front of volume: closest depth plane.
		float plane_depth
			= select(behind_volume, depth_min_max.x, depth_min_max.y);
		float plane_intersection_t
			= (plane_depth - ray_screen.o.z) / ray_screen.d.z;
		// The t we want to move to if we don't cross a boundary.
		float ideal_t = select(
			inside_volume,
			t,
			select(
				behind_volume == travelling_towards_screen,
				plane_intersection_t,
				ray_length
			)
		);

		float3 ideal_pos = ray_screen.at(ideal_t);
		float2 ideal_cell = floor(ideal_pos.xy * cell_count);

		bool crossed_into_next_cell
			= crossed_cell_boundary(ray_cell, ideal_cell);
		t = select(
			crossed_into_next_cell,
			distance_to_cell_boundary(
				ray_screen,
				ray_cell,
				cell_count,
				nearest_cell_boundary,
				cross_offset
			),
			ideal_t
		);
		current_lod = select(
			crossed_into_next_cell,
			min(current_lod + 1, max_lod),
			current_lod - 1
		);
		i++;
	}

	return select<Optional<float3>>(
		current_lod < STOP_LOD,
		ray_screen.at(t),
		// If we ran out of steps before reaching the sky, use the position
		// of the last intersection (better than nothing).
		Optional<float3>(none),
	);
}
}


