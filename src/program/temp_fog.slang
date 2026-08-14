import aperture;
import lib.fog;
import lib.util.math;
import lib.util.space_conversion;

Texture2D<float3> tex_scene;
Texture2D<float> tex_blue_noise;

Texture3D<float3> tex_fog_volume_integrated_light;
Texture3D<float3> tex_fog_volume_integrated_extinction;

struct FragmentOutput {
	float3 radiance;
}

[shader("pixel")]
FragmentOutput main(float2 coord: SV_Position) {
	int2 icoord = int2(coord);
	float2 ncoord = coord / float2(ap.game.renderSize);

	float depth = ap.depth[icoord];
	float3 radiance = tex_scene[icoord];
	float dither = tex_blue_noise[icoord & 511];

	float3 pos_screen = float3(ncoord, depth);
	float3 pos_view = screen_to_view(pos_screen);
	float3 pos_scene = view_to_scene(pos_view);

	float3 dir_world = normalize(pos_scene);

	fog.FogParticipation participation;
	if (false) {
		participation = fog.raymarch<fog.OverworldProfile>(
			ap.camera.position,
			dir_world,
			length(pos_scene),
			dither
		);
	} else {
		participation = fog.lookup_fog_participation(
			tex_fog_volume_integrated_light,
			tex_fog_volume_integrated_extinction,
			pos_screen,
			pos_view,
		);
	}
	radiance = radiance * max0(exp(-participation.extinction))
		+ max0(participation.added_light);

	return FragmentOutput(radiance);
}


