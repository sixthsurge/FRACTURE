import aperture;

import lib.gbuffer_packing;
import lib.util.color;

Texture2D<uint2> tex_packed_gbuffer_data;

struct FragmentOutput {
    float3 radiance;
}

[[shader("pixel")]]
FragmentOutput main(float2 pos: SV_Position) {
    int2 ipos = int2(pos);

    uint2 packed_gbuffer_data = tex_packed_gbuffer_data.Load(int3(ipos, 0));

    GbufferData gbuffer_data = GbufferData.unpack(packed_gbuffer_data);

    float3 radiance = srgb_eotf_inv(gbuffer_data.albedo);

    return { radiance };
}