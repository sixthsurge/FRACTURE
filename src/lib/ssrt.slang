public module ssrt;

import aperture;
import util.math;

Texture2D<float> tex_depth_hiz;

struct Hit {
	float3 pos_screen;
}

interface DepthMip {
	float get_depth(int2 pos);
	int2 size();
}

struct FirstDepthMip : DepthMip {
	float get_depth(int2 pos) { return ap.opaqueDepth[pos]; }

	int2 size() { return ap.game.renderSize; }
}

struct HigherDepthMip : DepthMip {
	int lod;

	float get_depth(int2 pos) { return tex_depth_hiz.Load(int3(pos, lod)); }

	int2 size() {
		uint width, height, levels;
		tex_depth_hiz.GetDimensions(lod, width, height, levels);
		return int2(width, height);
	}
}

Optional<Hit>
raymarch_depth_mip<Tex>(Tex tex, float3 origin_screen, float3 dir_screen)
	where Tex : DepthMip {
	int2 size = tex.size();
	float3 scale = float3(size, 1.0);

	origin_screen *= scale;
	dir_screen *= scale;
	dir_screen /= length(dir_screen.xy);

	float2 dir_step = step(0.0, dir_screen.xy);
	float2 dir_rcp = 1.0 / abs(dir_screen.xy);
	float t = 0.0;
	float last_t = 0.0;

	for (int i = 0; i < 1000; ++i) {
		float3 pos_screen = origin_screen + dir_screen * t;
		if (any(pos_screen <= 0 || pos_screen >= scale)) {
			return none;
		}
		float depth = tex.get_depth(int2(pos_screen.xy));
		if (pos_screen.z < depth) {
			return Hit((origin_screen + dir_screen * last_t) / scale);
		}
		last_t = t;

		float2 delta = frac(dir_step - pos_screen.xy) * dir_rcp;
		t += max(min(delta.x, delta.y), 0.01);
	}

	return none;
}

Optional<Hit> raymarch_depth_hiz(float3 origin_screen, float3 dir_screen) {
	int mip = 5;

	for (mip; mip > 0; mip--) {
		if (let hit = raymarch_depth_mip(
				HigherDepthMip(mip),
				origin_screen,
				dir_screen
			)) {
			origin_screen = hit.pos_screen;
		} else {
			return none;
		}
	}

	return raymarch_depth_mip(FirstDepthMip(), origin_screen, dir_screen);
}


