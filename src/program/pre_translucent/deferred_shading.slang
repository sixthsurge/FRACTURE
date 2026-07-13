import aperture;

import buffer.global;
import lib.gbuffer_packing;
import lib.lighting.celestial_shadow;
import lib.util.color;
import lib.util.space_conversion;

Texture2D<uint2> tex_packed_gbuffer_data;

struct FragmentOutput {
	float3 radiance;
}

[shader("pixel")]
FragmentOutput main(float2 pos: SV_Position) {
	int2 ipos = int2(pos);
	float2 npos = pos / float2(ap.game.renderSize);

	uint2 packed_gbuffer_data = tex_packed_gbuffer_data[ipos];
	float depth = ap.opaqueDepth[ipos];

	if (depth == 0.0) {
		return FragmentOutput(float3(1.0, 0.25, 1.0));
	}

	float3 pos_screen = float3(npos, depth);
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


