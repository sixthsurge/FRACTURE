import aperture;
import lib.util.math;
import lib.util.random;
import lib.util.space_conversion;
import lib.atmospherics.atmosphere;
import lib.atmospherics.clouds;
import lib.util.debug;

RWTexture2D tex_clouds_raw;
RWTexture2D<float> tex_clouds_raw_data;
Texture2D<float3> tex_atmosphere_sky_view;

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID) {
	int w, h;
	tex_clouds_raw.GetDimensions(w, h);
	if (any(icoord >= int2(w, h))) {
		return;
	}

	float2 ncoord
		= (float2(icoord) + r2(ap.timing.frameCounter, 0.25)) / float2(w, h);

	uint random_seed
		= ap.timing.frameCounter * (w * h) + icoord.y * w + icoord.x;
	PcgRandom random = PcgRandom(random_seed);

	float3 dir_world = mul(
		float3x3(ap.camera.viewInv),
		normalize(screen_to_view(float3(ncoord, 1.0)))
	);

	float3 sky_radiance
		= atmosphere.lookup_sky_radiance(tex_atmosphere_sky_view, dir_world);

	clouds.RenderResult result = clouds.render(
		clouds.RENDER_PARAMS_MAIN,
		Ray(clouds.camera_pos(), dir_world),
		sky_radiance,
		random.next_float()
	);

	tex_clouds_raw[icoord] = float4(result.scattering, result.transmittance);
	tex_clouds_raw_data[icoord] = result.apparent_distance;
}


