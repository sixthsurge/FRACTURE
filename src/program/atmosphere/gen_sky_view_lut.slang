import aperture;
import lib.atmospherics.atmosphere;
import lib.util.math;
import lib.util.space_conversion;
import settings;

RWTexture2D<float3> tex_atmosphere_sky_view;
Texture2D<float3> tex_atmosphere_transmittance;
Texture2D<float3> tex_atmosphere_multiscatter;

static const atmosphere.AtmosphereParameters ATMOSPHERE_PARAMS
	= atmosphere.EARTH_PARAMS;

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID) {
	int w, h;
	tex_atmosphere_sky_view.GetDimensions(w, h);
	if (any(icoord >= int2(w, h))) {
		return;
	}

	float2 ncoord = (float2(icoord) + 0.5) / float2(w, h);
	ncoord = get_unit_range_from_uv(ncoord, float2(w, h));

	float3 ray_dir = atmosphere.unproject_sky_view(ncoord);

	tex_atmosphere_sky_view[icoord]
		= atmosphere
			  .calculate_scattering(
				  ATMOSPHERE_PARAMS,
				  tex_atmosphere_transmittance,
				  tex_atmosphere_multiscatter,
				  atmosphere.camera_pos(),
				  ray_dir,
				  none,
				  atmosphere.light_sources()
			  )
			  .scattering;
}


