import aperture;
import lib.fog;
import lib.util.math;
import lib.util.random;
import lib.util.space_conversion;

RWTexture3D<float3> tex_fog_volume_light_a;
RWTexture3D<float3> tex_fog_volume_light_b;
RWTexture3D<float3> tex_fog_volume_extinction_a;
RWTexture3D<float3> tex_fog_volume_extinction_b;

typedef fog.OverworldProfile DimensionFogProfile;

void create(
	RWTexture3D<float3> tex_fog_volume_light,
	RWTexture3D<float3> tex_fog_volume_light_prev,
	RWTexture3D<float3> tex_fog_volume_extinction,
	RWTexture3D<float3> tex_fog_volume_extinction_prev,
	int3 icoord,
) {
	int w, h, d;
	tex_fog_volume_light.GetDimensions(w, h, d);

	float3 ncoord = (icoord + r3(ap.timing.frameCounter)) / float3(w, h, d);
	ncoord = get_unit_range_from_uv(ncoord, float3(w, h, d));

	float3 p0v
		= fog.unproject_fog_volume(float3(ncoord.xy, ncoord.z - 0.5 / d));
	float3 p1v
		= fog.unproject_fog_volume(float3(ncoord.xy, ncoord.z + 0.5 / d));
	float ray_length = distance(p0v, p1v);

	float3 pos_view = fog.unproject_fog_volume(ncoord);
	float3 pos_scene = view_to_scene(pos_view);
	float3 pos_world = pos_scene + ap.camera.position;
	float3 dir_world = normalize(pos_scene);

	fog.FogParticipation froxel_participation
		= fog.calculate_local_participation<DimensionFogProfile>(
			pos_world,
			dir_world,
			ray_length
		);

	// Temporal reprojection.
	float3 pos_prev_view
		= transform(ap.temporal.view, pos_world - ap.temporal.position);
	float3 pos_prev_screen
		= view_to_screen(pos_prev_view, ap.temporal.projection);
	float3 coord_prev = fog.project_fog_volume(pos_prev_screen, pos_prev_view);
	coord_prev = get_uv_from_unit_range(coord_prev, float3(w, h, d));
	if (all(saturate(coord_prev) == coord_prev)) {
		int3 icoord_prev = int3(coord_prev * float3(w, h, d));
		float3 light = tex_fog_volume_light_prev[icoord_prev];
		float3 extinction = tex_fog_volume_extinction_prev[icoord_prev];
		if (all(isfinite(light)) && all(isfinite(extinction))
			&& ap.timing.frameCounter > 0) {
			float blend = 0.95;
			froxel_participation.added_light
				= lerp(froxel_participation.added_light, light, blend);
			froxel_participation.extinction
				= lerp(froxel_participation.extinction, extinction, blend);
		}
	}

	tex_fog_volume_light[icoord] = froxel_participation.added_light;
	tex_fog_volume_extinction[icoord] = froxel_participation.extinction;
}

[shader("compute")]
[numthreads(8, 8, 4)]
void main(int3 icoord: SV_DispatchThreadID) {
	if ((ap.timing.frameCounter & 1) == 0) {
		create(
			tex_fog_volume_light_a,
			tex_fog_volume_light_b,
			tex_fog_volume_extinction_a,
			tex_fog_volume_extinction_b,
			icoord
		);
	} else {
		create(
			tex_fog_volume_light_b,
			tex_fog_volume_light_a,
			tex_fog_volume_extinction_b,
			tex_fog_volume_extinction_a,
			icoord
		);
	}
}


