import aperture;
import lib.atmospherics.atmosphere;
import lib.atmospherics.clouds;
import lib.atmospherics.sky;
import lib.toggles;
import lib.util.math;
import lib.util.space_conversion;
import settings;

import lib.util.debug;

RWTexture2D<float3> tex_sky_map;

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID) {
	int w, h;
	tex_sky_map.GetDimensions(w, h);
	if (any(icoord >= int2(w, h))) {
		return;
	}

	float2 ncoord = (float2(icoord) + 0.5) / float2(w, h);
	ncoord = get_unit_range_from_uv(ncoord, float2(w, h));

	float3 ray_dir = atmosphere.unproject_sky_view(ncoord);

	float3 sky_radiance
		= sky.DimensionSky.render<sky.RenderPurpose.SkyMap>(ray_dir);

	if (TOGGLE_CLOUDS) {
		clouds.RenderResult result = clouds.render(
			clouds.RENDER_PARAMS_SKY_VIEW,
			Ray(clouds.camera_pos(), ray_dir),
			sky_radiance,
			0.5
		);

		sky_radiance = sky_radiance * result.transmittance + result.scattering;
	}

	tex_sky_map[icoord] = max0(sky_radiance);
}


