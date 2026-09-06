// Pixel-perfect POM using ideas from
// https://sugulee.wordpress.com/2021/01/19/screen-space-reflections-implementation-and-optimization-part-2-hi-z-tracing-method.

module pom;

import aperture;
import lib.util.math;
import object_shader;
import settings;

namespace pom {
struct AtlasTile {
	float2 offset;
	float2 scale;

	float2 atlas_from_local(float2 local_coord) {
		return offset + scale * frac(local_coord);
	}

	float2 local_from_atlas(float2 uv) { return (uv - offset) * rcp(scale); }
}

static const int MAX_STEPS = 64;
static const int MAX_STEPS_SHADOW = 12;

public struct Result {
	public float2 uv;
	public Optional<float3> slope_normal;
	public bool self_shadow;

	static Result no_hit(float2 uv) { return Result(uv, none, false); }
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

public Result calculate(
	PixelData object_data,
	float2 tile_offset,
	float2 tile_scale,
	float2 uv,
	float3 dir_tangent,
	float3x3 tbn,
	float2x2 uv_gradient
) {
	if (!object_data.normal().hasValue) {
		return Result.no_hit(uv);
	}
	let normal_tex = object_data.normal().value;

	if (normal_tex.sampleLevel(uv, 0.0).w > 254.0 / 255.0) {
		return Result.no_hit(uv);
	}

	AtlasTile tile = AtlasTile(tile_offset, tile_scale);
	float2 local_coord = tile.local_from_atlas(uv);

	Ray ray = Ray(float3(local_coord, 0.0), dir_tangent);

	// Which cell boundaries are we stepping towards?
	float2 nearest_cell_boundary = step(0.0, ray.d.xy);

	// Small offset added to make sure we end up in the next cell after
	// advancing to the cell boundary.
	float2 cross_offset = (nearest_cell_boundary * 2.0 - 1.0) * 0.00001;
	float t = 0.0;

	float depth;
	float2 p;
	float2 last_cell = floor(ray.o.xy * userSettings.RESOURCE_PACK_RESOLUTION);
	Optional<float3> slope_normal = none;
	for (int i = 0; i < MAX_STEPS; ++i) {
		float3 ray_pos = ray.at(t);
		float2 ray_cell
			= floor(ray_pos.xy * userSettings.RESOURCE_PACK_RESOLUTION);

		depth = -userSettings.POM_DEPTH
			* (1.0
			   - normal_tex
					 .sampleLevel(
						 tile.atlas_from_local(
							 ray_cell
							 * rcp(float(userSettings.RESOURCE_PACK_RESOLUTION))
						 ),
						 0.0
					 )
					 .w);

		bool inside_volume = ray_pos.z < depth;

		float plane_intersection_t = (depth - ray.o.z) / ray.d.z;

		float ideal_t = select(inside_volume, t, plane_intersection_t);

		float3 ideal_pos = ray.at(ideal_t);
		float2 ideal_cell
			= floor(ideal_pos.xy * userSettings.RESOURCE_PACK_RESOLUTION);
		bool crossed_into_next_cell = any(ray_cell != ideal_cell);

		if (crossed_into_next_cell) {
			t = distance_to_cell_boundary(
				ray,
				ray_cell,
				userSettings.RESOURCE_PACK_RESOLUTION,
				nearest_cell_boundary,
				cross_offset
			);
		} else {
			t = ideal_t;
			if (inside_volume) {
				slope_normal = float3(last_cell - ray_cell, 0.0);
			}
			break;
		}
		last_cell = ray_cell;
	}

	bool self_shadow = false;
	float3 light_dir_tangent = mul(tbn, buf_global.light_dir_world);
	if (light_dir_tangent.z > EPS
		&& dot(slope_normal.orElse(float3(0.0, 0.0, 1.0)), light_dir_tangent)
			> EPS) {
		Ray shadow_ray = Ray(ray.at(t), light_dir_tangent);
		float2 shadow_cell
			= floor(shadow_ray.o.xy * userSettings.RESOURCE_PACK_RESOLUTION);

		// Which cell boundaries are we stepping towards?
		float2 nearest_cell_boundary = step(0.0, shadow_ray.d.xy);

		// Small offset added to make sure we end up in the next cell after
		// advancing to the cell boundary.
		float2 cross_offset = (nearest_cell_boundary * 2.0 - 1.0) * 0.00001;
		float t = distance_to_cell_boundary(
			shadow_ray,
			shadow_cell,
			userSettings.RESOURCE_PACK_RESOLUTION,
			nearest_cell_boundary,
			cross_offset
		);
		float ray_length = -shadow_ray.o.z / shadow_ray.d.z; // Stop at 0.0

		for (int i = 0; i < MAX_STEPS_SHADOW && t < ray_length; ++i) {
			float3 ray_pos = shadow_ray.at(t);
			float2 ray_cell
				= floor(ray_pos.xy * userSettings.RESOURCE_PACK_RESOLUTION);

			depth = -userSettings.POM_DEPTH
				* (1.0
				   - normal_tex
						 .sampleLevel(
							 tile.atlas_from_local(
								 ray_cell
								 * rcp(
									 float(userSettings
											   .RESOURCE_PACK_RESOLUTION)
								 )
							 ),
							 0.0
						 )
						 .w);

			bool inside_volume = ray_pos.z < depth;

			float plane_intersection_t
				= (depth - shadow_ray.o.z) / shadow_ray.d.z;

			float ideal_t = select(inside_volume, t, plane_intersection_t);

			float3 ideal_pos = shadow_ray.at(ideal_t);
			float2 ideal_cell
				= floor(ideal_pos.xy * userSettings.RESOURCE_PACK_RESOLUTION);
			bool crossed_into_next_cell = any(ray_cell != ideal_cell);

			if (!crossed_into_next_cell) {
				self_shadow = true;
				break;
			} else {
				t = distance_to_cell_boundary(
					shadow_ray,
					ray_cell,
					userSettings.RESOURCE_PACK_RESOLUTION,
					nearest_cell_boundary,
					cross_offset
				);
			}
		}
	} else {
		self_shadow = true;
	}

	// Move final position to texel center.
	float2 final_coord
		= (floor(ray.at(t).xy * float(userSettings.RESOURCE_PACK_RESOLUTION))
		   + 0.5)
		/ float(userSettings.RESOURCE_PACK_RESOLUTION);

	return Result(
		tile.atlas_from_local(final_coord),
		slope_normal,
		self_shadow
	);
}
}


