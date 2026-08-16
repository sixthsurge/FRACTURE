import aperture;
import lib.atmosphere;
import lib.util.math;
import lib.util.space_conversion;
import settings;

RWTexture3D<float3> tex_atmosphere_aerial_perspective;
Texture2D<float3> tex_atmosphere_transmittance;
Texture2D<float3> tex_atmosphere_multiscatter;

static const atmosphere.AtmosphereParameters ATMOSPHERE_PARAMS
	= atmosphere.EARTH_PARAMS;

[shader("compute")]
[numthreads(16, 16, 1)]
void main(int3 icoord: SV_DispatchThreadID) {
	float w, h, d;
	tex_atmosphere_aerial_perspective.GetDimensions(w, h, d);

	float3 ncoord = (float3(icoord) + 0.5) / float3(w, h, d);

	float depth = get_unit_range_from_uv(ncoord.z, int(d));
	depth = pow2(pow2(depth)); // Focus precision towards the view.
	depth = view_to_screen_depth(
		depth * atmosphere.AERIAL_PERSPECTIVE_DEPTH_SCALE
	);
	depth = min(depth, 1.0 - EPS);

	float3 pos_screen = float3(ncoord.xy, depth);
	float3 pos_view = screen_to_view(pos_screen);
	float3 pos_scene = view_to_scene(pos_view);
	float3 dir_world = normalize(pos_scene);

	tex_atmosphere_aerial_perspective[icoord]
		= atmosphere
			  .calculate_scattering(
				  ATMOSPHERE_PARAMS,
				  tex_atmosphere_transmittance,
				  tex_atmosphere_multiscatter,
				  atmosphere.camera_pos(),
				  dir_world,
				  length(pos_scene)
					  * atmosphere.AERIAL_PERSPECTIVE_TERRAIN_SCALE,
				  atmosphere.light_sources()
			  )
			  .scattering;
}


