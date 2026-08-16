import aperture;
import lib.atmosphere;
import lib.util.math;
import lib.util.space_conversion;
import settings;

RWTexture2D<float3> tex_atmosphere_multiscatter;
Texture2D<float3> tex_atmosphere_transmittance;

static const atmosphere.AtmosphereParameters ATMOSPHERE_PARAMS
	= atmosphere.EARTH_PARAMS;

[shader("compute")]
[numthreads(8, 8, 1)]
void main(int2 icoord: SV_DispatchThreadID) {
	int w, h;
	tex_atmosphere_multiscatter.GetDimensions(w, h);
	if (any(icoord >= int2(w, h))) {
		return;
	}

	float2 ncoord = (float2(icoord) + 0.5) / float2(w, h);
	ncoord = get_unit_range_from_uv(ncoord, float2(w, h));

	float cos_sun_zenith_angle = ncoord.x * 2.0 - 1.0;
	float r = lerp(
		ATMOSPHERE_PARAMS.planet_radius,
		ATMOSPHERE_PARAMS.atmosphere_radius(),
		ncoord.y
	);

	tex_atmosphere_multiscatter[icoord]
		= atmosphere.calculate_multiscatter_energy(
			ATMOSPHERE_PARAMS,
			tex_atmosphere_transmittance,
			r,
			cos_sun_zenith_angle
		);
}


