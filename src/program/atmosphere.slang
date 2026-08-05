import aperture;
import lib.atmosphere;
import lib.sky_view_projection;
import lib.util.math;
import settings;

Texture2D<float3> tex_atmosphere_transmittance_lut;
Texture2D<float3> tex_atmosphere_multiscatter_lut;
Texture2D<float3> tex_atmosphere_sky_view;

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

	float3 ray_origin
		= float3(0.0, ATMOSPHERE_PARAMS.planet_radius + 1000.0, 0.0);
	float3 ray_dir = unproject_sky_view(ncoord);

	atmosphere.LightSource light_sources[2] = {
		atmosphere
			.LightSource(buf_global.sun_radiosity, buf_global.sun_dir_world),
		atmosphere
			.LightSource(buf_global.moon_radiosity, buf_global.moon_dir_world),
	};

	return SkyViewOutput(atmosphere.calculate_scattering(
		ATMOSPHERE_PARAMS,
		tex_atmosphere_transmittance_lut,
		tex_atmosphere_multiscatter_lut,
		ray_origin,
		ray_dir,
		light_sources
	));
}


