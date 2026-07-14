import aperture;
import lib.gbuffer_packing;
import lib.lighting.celestial_shadow;
import lib.util.color;
import lib.util.space_conversion;
import settings;

Texture2D<uint2> tex_packed_gbuffer_data;

struct FragmentOutput {
	float3 radiance;
}

[shader("pixel")]
FragmentOutput main(float2 coord: SV_Position) {
	int2 icoord = int2(coord);
	float2 ncoord = coord / float2(ap.game.renderSize);

	uint2 packed_gbuffer_data = tex_packed_gbuffer_data[icoord];
	float depth = ap.opaqueDepth[icoord];

	if (depth == 0.0) {
		return FragmentOutput(float3(1.0, 0.25, 1.0));
	}

	float3 pos_screen = float3(ncoord, depth);
	float3 pos_view = screen_to_view(pos_screen);
	float3 pos_scene = view_to_scene(pos_view);

	float3 dir_world = normalize(pos_scene);

	GbufferData gbuffer_data = GbufferData.unpack(packed_gbuffer_data);

	float3 radiance = srgb_eotf_inv(gbuffer_data.albedo);

	ShadowResult celestial_shadow = get_celestial_shadow(pos_scene);

	radiance *= celestial_shadow.visibility
			* max(0, dot(gbuffer_data.normal_world, buf_global.light_dir_world))
			* 0.8
		+ 0.2;

	return FragmentOutput(radiance);
}


