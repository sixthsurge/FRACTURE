import aperture;
import lib.util.math;
import lib.util.filtering;
import lib.util.random;
import lib.util.space_conversion;
import settings;

import lib.util.debug;

RWTexture2D tex_clouds_temporal_current;
RWTexture2D<float2> tex_clouds_temporal_data_current;
Texture2D tex_clouds_temporal_prev;
Texture2D<float2> tex_clouds_temporal_data_prev;
Texture2D tex_clouds_raw;
Texture2D<float> tex_clouds_raw_data;

static const float MAX_PIXEL_AGE = 5.0;

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID) {
	if (any(icoord >= ap.game.renderSize)) {
		return;
	}

	int raw_w, raw_h;
	tex_clouds_raw.GetDimensions(raw_w, raw_h);

	float2 ncoord = (icoord + 0.5) / ap.game.renderSize;

	float2 raw_sample_pos = ncoord
		- (r2(ap.timing.frameCounter, 0.25) - 0.5) * rcp(float2(raw_w, raw_h));
	Tuple<float4, float> upsampled
		= tex_clouds_raw.sample_catmull_rom(raw_sample_pos, 0);
	float4 upsampled_bicubic = tex_clouds_raw.sample_bicubic(raw_sample_pos, 0);
	float apparent_distance = tex_clouds_raw_data.sampleLinear(ncoord);

	float3 dir_world = mul(
		float3x3(ap.camera.viewInv),
		normalize(screen_to_view(float3(ncoord, 1.0)))
	);
	float3 pos_scene
		= dir_world * apparent_distance + translation_part(ap.camera.viewInv);
	float3 pos_prev_screen = view_to_screen(
		transform(ap.temporal.view, pos_scene),
		ap.temporal.projection,
	);

	float4 result;
	float pixel_age;
	if (all(saturate(pos_prev_screen.xy) == pos_prev_screen.xy)) {
		float2 data
			= tex_clouds_temporal_data_prev.sampleLinear(pos_prev_screen.xy);
		pixel_age = min(data.x, MAX_PIXEL_AGE);

		float p = pixel_age * 128.0;
		float old_pixel = p / (p + 1.0);

		float4 history = max0(tex_clouds_temporal_prev.sample_catmull_rom_fast(
			pos_prev_screen.xy,
			0,
			lerp(0.1, 0.65, old_pixel)
		));

		float frame_weight
			= saturate(pow(lerp(0.5, upsampled._1, dampen(old_pixel)), 4.0));
		float history_weight = pixel_age / (pixel_age + frame_weight);
		result = lerp(
			lerp(
				history,
				lerp(
					upsampled_bicubic,
					upsampled._0,
					linstep(0.0, 0.75, old_pixel)
				),
				frame_weight
			),
			history,
			history_weight
		);
		pixel_age += frame_weight;
	} else {
		result = upsampled._0;
		pixel_age = 0.0;
	}

	tex_clouds_temporal_current[icoord] = result;
	tex_clouds_temporal_data_current[icoord] = float2(pixel_age, 0.0);
}


