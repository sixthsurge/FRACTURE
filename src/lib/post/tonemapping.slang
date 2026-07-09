public module tonemapping;

import lib.util.color;

// Filmic tonemapping operator made by Jim Hejl and Richard Burgess, modified
// by Tech to not lose color information below 0.004
// sRGB EOTF is built in.
float3 tonemap_hejl_burgess(float3 rgb) {
    rgb = rgb * min(float3(1.0), 1.0 - 0.8 * exp(rcp(-0.004) * rgb));
    rgb = (rgb * (6.2 * rgb + 0.5)) / (rgb * (6.2 * rgb + 1.7) + 0.06);
    return rgb; // Revert built-in sRGB conversion
}

