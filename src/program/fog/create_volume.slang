import aperture;
import lib.atmospherics.fog;
import lib.util.math;
import lib.util.random;
import lib.util.space_conversion;

RWTexture3D<float4> tex_fog_volume_light;
RWTexture3D<float3> tex_fog_volume_extinction;
Texture3D<float4> tex_fog_volume_light_prev;
Texture3D<float3> tex_fog_volume_extinction_prev;

extern static const int ACTIVE_FRAME;

// Workaround for lack of 3D texture references; create two versions of the
// program; one runs on each frame.
// Each reads and writes different textures.

typedef fog.OverworldProfile DimensionFogProfile;

[shader("compute")]
[numthreads(8, 8, 4)]
void main(int3 icoord: SV_DispatchThreadID) {
	if ((ap.timing.frameCounter & 1) != ACTIVE_FRAME) {
		return;
	}
	int w, h, d;
	tex_fog_volume_light.GetDimensions(w, h, d);

	float3 ncoord = (icoord + r3(ap.timing.frameCounter)) / float3(w, h, d);
	ncoord = get_unit_range_from_uv(ncoord, float3(w, h, d));
	float3 ncoord_unjittered = (icoord + 0.5) / float3(w, h, d);
	ncoord_unjittered
		= get_unit_range_from_uv(ncoord_unjittered, float3(w, h, d));

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

	// Decorrelate ray length so that it doesn't mess up accumulatino.
	froxel_participation.added_light /= ray_length;
	froxel_participation.extinction /= ray_length;

	// Temporal reprojection.
	float pixel_age = 0.0;
	float3 pos_view_unjittered = fog.unproject_fog_volume(ncoord_unjittered);
	float3 pos_scene_unjittered = view_to_scene(pos_view_unjittered);
	float3 pos_prev_view = transform(
		ap.temporal.view,
		pos_scene_unjittered + ap.camera.position - ap.temporal.position
	);
	float3 pos_prev_screen
		= view_to_screen(pos_prev_view, ap.temporal.projection);
	float3 coord_prev = fog.project_fog_volume(pos_prev_screen, pos_prev_view);
	coord_prev = get_uv_from_unit_range(coord_prev, float3(w, h, d));
	if (all(coord_prev >= 0.0) && all(coord_prev <= 1.0)) {
		float4 light
			= tex_fog_volume_light_prev.Sample(apt_linearSampler, coord_prev);
		float3 extinction = tex_fog_volume_extinction_prev.Sample(
			apt_linearSampler,
			coord_prev
		);

		if (all(isfinite(light)) && all(isfinite(extinction))
			&& ap.timing.frameCounter > 0) {
			pixel_age = 1.0 + light.w;
			float blend = min(pixel_age / (pixel_age + 1.0), 0.95);
			froxel_participation.added_light
				= lerp(froxel_participation.added_light, light.xyz, blend);
			froxel_participation.extinction
				= lerp(froxel_participation.extinction, extinction, blend);
		}
	}

	tex_fog_volume_light[icoord]
		= float4(max0(froxel_participation.added_light), pixel_age);
	tex_fog_volume_extinction[icoord] = max0(froxel_participation.extinction);
}


