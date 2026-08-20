import aperture;
import lib.atmospherics.fog;
import settings;

RWTexture3D<float3> tex_fog_volume_integrated_light;
RWTexture3D<float3> tex_fog_volume_integrated_extinction;
Texture3D<float3> tex_fog_volume_light_a;
Texture3D<float3> tex_fog_volume_light_b;
Texture3D<float3> tex_fog_volume_extinction_a;
Texture3D<float3> tex_fog_volume_extinction_b;

void integrate(
	Texture3D<float3> tex_fog_volume_light,
	Texture3D<float3> tex_fog_volume_extinction,
	int3 icoord,
) {
	float w, h, d;
	tex_fog_volume_light.GetDimensions(w, h, d);

	float3 light = float3(0.0);
	float3 extinction = float3(0.0);

	for (int z = 0; z <= d; ++z) {
		float3 p0v
			= fog.unproject_fog_volume(float3(float2(0), float(z) / float(d)));
		float3 p1v = fog.unproject_fog_volume(
			float3(float2(0), float(z + 1) / float(d))
		);
		float ray_length = distance(p0v, p1v);

		float3 step_extinction
			= tex_fog_volume_extinction[int3(icoord.xy, z)] * ray_length;

		light += tex_fog_volume_light[int3(icoord.xy, z)] * ray_length
			* exp(-extinction);
		extinction += step_extinction;
		tex_fog_volume_integrated_light[int3(icoord.xy, z)] = light;
		tex_fog_volume_integrated_extinction[int3(icoord.xy, z)] = extinction;
	}
}

[shader("compute")]
[numthreads(16, 16)]
void main(int3 icoord: SV_DispatchThreadID) {
	if ((ap.timing.frameCounter & 1) == 0) {
		integrate(tex_fog_volume_light_a, tex_fog_volume_extinction_a, icoord);
	} else {
		integrate(tex_fog_volume_light_b, tex_fog_volume_extinction_b, icoord);
	}
}


