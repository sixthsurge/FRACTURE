// Hi-Z screen-space ray-tracing following
// https://sugulee.wordpress.com/2021/01/19/screen-space-reflections-implementation-and-optimization-part-2-hi-z-tracing-method.
//
// The logic is basically the same as in the article, I just wanted to write it
// out it in my own words to make sure I understand it.
//
// As Aperture uses reverse Z, where the article refers to the minimum depth,
// we refer to the maximum.

public module ssrt;

import aperture;
import lib.util.math;
import lib.util.space_conversion;

namespace ssrt {
struct Hit {
	float3 pos_screen;
}

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

bool crossed_cell_boundary(float2 cell_a, float2 cell_b) {
	return any(int2(cell_a) != int2(cell_b));
}

Optional<Hit>
trace_linear(MippedDepthTexture depth_tex, Ray ray_screen, float ray_length) {
	float t = 0.0;
	int i = 0;

	while (i < 100 && t < ray_length) {
		float3 pos = ray_screen.at(t);
		float depth = depth_tex[int2(pos.xy * ap.game.renderSize)];

		if (depth > pos.z) {
			return Hit(pos);
		}
		t += 0.01;
		i++;
	}
	return none;
}

Optional<Hit>
trace_hiz(MippedDepthTexture depth_tex, Ray ray_screen, float ray_length) {
	const int MAX_STEPS = 100; // Limit the maximum number of steps.
	const int INITIAL_LOD = 2; // Lod at which to start tracing.
	const int STOP_LOD = 0; // Lod at which to stop tracing

	// Which cell boundaries are we stepping towards?
	float2 nearest_cell_boundary = step(0.0, ray_screen.d.xy);

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

	int i = 0;
	while (i < MAX_STEPS && current_lod >= STOP_LOD && t < ray_length) {
		float2 cell_count = depth_lod_size(current_lod);
		float3 ray_pos = ray_screen.at(t);
		float2 ray_cell = floor(ray_pos.xy * cell_count);

		float max_depth = depth_tex.loadLevel(int2(ray_cell), current_lod);

		// Stepping logic:
		// If we are outside the volume then we want to move the ray either
		// to the next cell or to the point where it intersects the plane
		// where the depth is the maximum depth within this cell. If we are
		// inside the volume then we just want to keep the same position and
		// move to the finer-grained LOD. We do this by first calculating
		// the intersection point with the max depth plane, then deciding
		// whether it crossed a cell boundary, and if it crossed, clipping
		// it to the distance the cell boundary.
		bool inside_cell_volume = ray_pos.z < max_depth;
		float volume_intersection_t = inside_cell_volume
			? t
			: ((max_depth - ray_screen.o.z) / ray_screen.d.z);
		float3 volume_intersection_pos = ray_screen.at(volume_intersection_t);
		float2 volume_intersection_cell
			= floor(volume_intersection_pos.xy * cell_count);

		bool crossed_into_next_cell
			= crossed_cell_boundary(ray_cell, volume_intersection_cell);
		t = crossed_into_next_cell
			? distance_to_cell_boundary(
				  ray_screen,
				  ray_cell,
				  cell_count,
				  nearest_cell_boundary,
				  cross_offset
			  )
			: volume_intersection_t;
		current_lod = crossed_into_next_cell
			? min(current_lod + 1, max_lod)
			: current_lod - 1;
		i++;
	}

	if (current_lod >= STOP_LOD) {
		return none;
	}
	return Hit(ray_screen.at(t));
}
}


