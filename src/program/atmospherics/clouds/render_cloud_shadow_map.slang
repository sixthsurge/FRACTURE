import aperture;
import lib.atmospherics.atmosphere;
import lib.atmospherics.clouds;
import lib.lighting.cloud_shadow;
import settings;
import lib.util.debug;
import lib.util.math;
import lib.util.ray_sphere_intersection;

RWTexture2D<float> tex_cloud_shadow;

static const int STEPS = 8;

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID) {
	let ncoord
		= (float2(icoord) + 0.5) * rcp(float(userSettings.CLOUD_SHADOW_RES));

	var ray_origin = cloud_shadow.unproject(ncoord);
	ray_origin += clouds.camera_pos();

	// Move ray to volume middle.
	ray_origin += buf_global.light_dir_world
		* intersect_sphere(
			  ray_origin,
			  buf_global.light_dir_world,
			  clouds.VOLUME_INNER_RADIUS
		)
			  .y;

	float optical_depth = clouds.calculate_optical_depth(
		Ray(ray_origin, buf_global.light_dir_world),
		STEPS,
		0.5
	);

	tex_cloud_shadow[icoord] = exp(-optical_depth);
}


