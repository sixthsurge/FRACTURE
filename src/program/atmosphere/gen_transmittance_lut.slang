import aperture;
import lib.atmosphere;
import lib.util.math;
import lib.util.space_conversion;
import settings;

RWTexture2D<float3> tex_atmosphere_transmittance;

static const atmosphere.AtmosphereParameters ATMOSPHERE_PARAMS
	= atmosphere.EARTH_PARAMS;

[shader("compute")]
[numthreads(16, 16, 1)]
void main(int2 icoord: SV_DispatchThreadID) {
	int w, h;
	tex_atmosphere_transmittance.GetDimensions(w, h);
	if (any(icoord >= int2(w, h))) {
		return;
	}

	float2 ncoord = (float2(icoord) + 0.5) / float2(w, h);
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

	tex_atmosphere_transmittance[icoord] = atmosphere.calculate_transmittance(
		ATMOSPHERE_PARAMS,
		ray_origin,
		ray_dir
	);
}


