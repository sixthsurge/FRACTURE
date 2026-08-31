public module debug;

import lib.util.color;
import settings;

namespace debug {
internal RWTexture2D<float4> tex_debug;

void show(int2 icoord, float3 color) {
	if (userSettings.DEBUG) {
		tex_debug[icoord] = float4(srgb_eotf(color), 1.0);
	}
}

void show_tonemapped(int2 icoord, float3 color) {
	show(icoord, color / (color + 1.0));
}
}


