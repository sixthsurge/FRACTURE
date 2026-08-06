import aperture;
import lib.buffer.exposure;
import lib.post.tonemapping;
import settings;

Texture2D tex_scene;

ConstantBuffer<ExposureBuffer> buf_exposure;
Texture2D<uint> tex_exposure_histogram;

[shader("pixel")]
float4 main(float2 coord: SV_Position) {
	int2 icoord = int2(coord);

	float3 color = tex_scene[icoord].rgb;

	if (userSettings.AUTO_EXPOSURE_ENABLED) {
		color *= buf_exposure.value;
	} else {
		color *= userSettings.MANUAL_EXPOSURE_VALUE;
	}

	color = tonemap_agx(color);

	// NB: do not need to apply sRGB EOTF as this is built into Hejl-Burgess.

	if (userSettings.DISPLAY_LUMINANCE_HISTOGRAM) {
		const int2 scale = int2(4);
		int2 pos = icoord / scale;
		if (pos.x < 256) {
			if (tex_exposure_histogram[int2(pos.x, 0)] > pos.y * 1000) {
				color = float3(0.0);
			}
			if (pos.x == buf_exposure.selected_bin) {
				color += float3(0.5, 0.0, 0.0);
			}
		}
	}

	return float4(color, 1.0);
}


