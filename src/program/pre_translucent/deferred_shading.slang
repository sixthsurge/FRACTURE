import aperture;

import lib.gbuffer_packing;
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

	float3 pos_screen = float3(npos, depth);
	float3 pos_view = screen_to_view(pos_screen, HandleJitter.True);
	float3 pos_scene = view_to_scene(pos_view);

	GbufferData gbuffer_data = GbufferData.unpack(packed_gbuffer_data);

	float3 radiance = srgb_eotf_inv(gbuffer_data.albedo);

	return { radiance };
}


