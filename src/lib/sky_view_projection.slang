public module sky_view_projection;

import lib.util.math;

float2 project_sky_view(float3 direction) {
	float2 projected_dir = normalize(direction.xz);

	float azimuth_angle = PI + atan2(projected_dir.x, -projected_dir.y);
	float altitude_angle = 0.5 * PI - fast_acos(direction.y);

	float2 coord;
	coord.x = azimuth_angle / TAU;
	coord.y = 0.5
		+ 0.5 * sign(altitude_angle)
			* sqrt((2.0 / PI) * abs(altitude_angle)); // Section 5.3

	return coord;
}

float3 unproject_sky_view(float2 coord) {
	// Non-linear mapping of altitude angle (See section 5.3 of the paper)
	coord.y = (coord.y < 0.5) ? -pow2(1.0 - 2.0 * coord.y)
							  : pow2(2.0 * coord.y - 1.0);

	float azimuth_angle = coord.x * TAU - PI;
	float altitude_angle = coord.y * (0.5 * PI);

	float altitude_sin, altitude_cos, azimuth_sin, azimuth_cos;
	sincos(altitude_angle, altitude_sin, altitude_cos);
	sincos(azimuth_angle, azimuth_sin, azimuth_cos);

	return float3(
		altitude_cos * azimuth_sin,
		altitude_sin,
		-altitude_cos * azimuth_cos
	);
}


