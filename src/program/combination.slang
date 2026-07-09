import aperture;

import lib.post.tonemapping;

Texture2D tex_scene;

[[shader("pixel")]]
float4 main(float2 pos: SV_Position) {
    int2 ipos = int2(pos);

    float3 color = tex_scene.Load(int3(ipos, 0)).rgb;

    color = tonemap_hejl_burgess(color);
    // NB: do not need to apply sRGB EOTF as this is built into Hejl-Burgess.

    return float4(color, 1.0);
}