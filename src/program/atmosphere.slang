import aperture;
import lib.atmosphere;
import lib.util.math;
import lib.util.space_conversion;
import settings;

Texture2D<float3> tex_atmosphere_transmittance_lut;
Texture2D<float3> tex_atmosphere_multiscatter_lut;
Texture2D<float3> tex_atmosphere_sky_view;
RWTexture3D<float3> tex_atmosphere_aerial_perspective;

struct TransmittanceOutput {
	float3 transmittance;
}

struct MultiscatterOutput {
	float3 multiscatter_energy;
}

struct SkyViewOutput {
	float3 sky_radiance;
}

static const atmosphere.AtmosphereParameters ATMOSPHERE_PARAMS
	= atmosphere.EARTH_PARAMS;

[shader("fragment")]
TransmittanceOutput transmittance_lut_main(float2 coord: SV_Position) {
	float w, h;
	tex_atmosphere_transmittance_lut.GetDimensions(w, h);
	float2 ncoord = coord / float2(w, h);
	ncoord = get_unit_range_from_uv(ncoord, float2(w, h));

	float cos_zenith_angle = ncoord.x * 2.0 - 1.0;
	float r = lerp(
		ATMOSPHERE_PARAMS.planet_radius,
		ATMOSPHERE_PARAMS.atmosphere_radius(),
		ncoord.y
	);

	float3 ray_origin = float3(0.0, r, 0.0);
	float3 ray_dir = float3(
		0.0,
		cos_zenith_angle,
		sqrt(saturate(1.0 - pow2(cos_zenith_angle)))
	);

	return TransmittanceOutput(atmosphere.calculate_transmittance(
		ATMOSPHERE_PARAMS,
		ray_origin,
		ray_dir
	));
}

[shader("fragment")]
MultiscatterOutput multiscatter_lut_main(float2 coord: SV_Position) {
	float w, h;
	tex_atmosphere_multiscatter_lut.GetDimensions(w, h);
	float2 ncoord = coord / float2(w, h);
	ncoord = get_unit_range_from_uv(ncoord, float2(w, h));

	float cos_sun_zenith_angle = ncoord.x * 2.0 - 1.0;
	float r = lerp(
		ATMOSPHERE_PARAMS.planet_radius,
		ATMOSPHERE_PARAMS.atmosphere_radius(),
		ncoord.y
	);

	return MultiscatterOutput(atmosphere.calculate_multiscatter_energy(
		ATMOSPHERE_PARAMS,
		tex_atmosphere_transmittance_lut,
		r,
		cos_sun_zenith_angle
	));
}

[shader("fragment")]
SkyViewOutput sky_view_main(float2 coord: SV_Position) {
	float w, h;
	tex_atmosphere_sky_view.GetDimensions(w, h);
	float2 ncoord = coord / float2(w, h);
	ncoord = get_unit_range_from_uv(ncoord, float2(w, h));

	float3 ray_dir = atmosphere.unproject_sky_view(ncoord);

	return SkyViewOutput(
		atmosphere
			.calculate_scattering(
				ATMOSPHERE_PARAMS,
				tex_atmosphere_transmittance_lut,
				tex_atmosphere_multiscatter_lut,
				atmosphere.camera_pos(),
				ray_dir,
				none,
				atmosphere.light_sources()
			)
			.scattering
	);
}

[shader("compute")]
[numthreads(16, 16, 1)]
void aerial_perspective_main(int3 icoord: SV_DispatchThreadID) {
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
				  tex_atmosphere_transmittance_lut,
				  tex_atmosphere_multiscatter_lut,
				  atmosphere.camera_pos(),
				  dir_world,
				  length(pos_scene)
					  * atmosphere.AERIAL_PERSPECTIVE_TERRAIN_SCALE,
				  atmosphere.light_sources()
			  )
			  .scattering;
}


