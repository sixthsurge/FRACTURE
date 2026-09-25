import aperture;
import lib.volumetrics.atmosphere;
import lib.volumetrics.clouds;
import lib.util.math;
import lib.util.space_conversion;
import settings;

import lib.util.debug;

RWTexture2D<float3> tex_atmosphere_sky_view;
RWTexture2D<float4> tex_cloudy_sky_view;
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

	float3 sky_radiance
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

	if (userSettings.CLOUDS_ENABLED) {
		clouds.RenderResult result = clouds.render(
			clouds.RENDER_PARAMS_SKY_VIEW,
			Ray(clouds.camera_pos(), ray_dir),
			sky_radiance,
			0.5
		);
		tex_cloudy_sky_view[icoord] = float4(
			sky_radiance * result.transmittance + result.scattering,
			result.transmittance
		);
	} else {
		tex_cloudy_sky_view[icoord] = float4(sky_radiance, 1.0);
	}

	tex_atmosphere_sky_view[icoord] = sky_radiance;
}


