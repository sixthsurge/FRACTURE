package resources;

import dev.irisshaders.aperture.api.objects.Texture2D;
import dev.irisshaders.aperture.api.objects.Texture3D;
import dev.irisshaders.aperture.api.objects.TextureFormat;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import util.Flipper;

public class Textures {
	public final Flipper<Texture2D> scene;
	public final Texture2D packedGbufferData;
	public final Texture2D atmosphereTransmittanceLut;
	public final Texture2D atmosphereMultiscatterLut;
	public final Texture2D atmosphereSkyView;
	public final Texture3D atmosphereAerialPerspectiveLut;
	public final Texture2D exposureHistogram;

	public Textures(PipelineConfig pipeline) {
		final var sceneTexA
			= pipeline.texture2D("tex_scene_a", TextureFormat.RG11B10_UFLOAT)
				  .renderSize()
				  .create();
		final var sceneTexB
			= pipeline.texture2D("tex_scene_b", TextureFormat.RG11B10_UFLOAT)
				  .renderSize()
				  .create();
		scene = new Flipper<>(sceneTexA, sceneTexB);

		packedGbufferData
			= pipeline
				  .texture2D("tex_packed_gbuffer_data", TextureFormat.RGBA32_UINT)
				  .renderSize()
				  .create();

		atmosphereTransmittanceLut
			= pipeline
				  .texture2D(
					  "tex_atmosphere_transmittance_lut",
					  TextureFormat.RG11B10_UFLOAT
				  )
				  .size(256, 64)
				  .create();

		atmosphereMultiscatterLut
			= pipeline
				  .texture2D(
					  "tex_atmosphere_multiscatter_lut",
					  TextureFormat.RGBA16_SFLOAT
				  )
				  .size(32, 32)
				  .create();

		atmosphereSkyView
			= pipeline
				  .texture2D(
					  "tex_atmosphere_sky_view",
					  TextureFormat.RG11B10_UFLOAT
				  )
				  .size(256, 128)
				  .create();

		atmosphereAerialPerspectiveLut
			= pipeline
				  .texture3D(
					  "tex_atmosphere_aerial_perspective",
					  TextureFormat.RG11B10_UFLOAT
				  )
				  .size(32, 32, 32)
				  .create();

		exposureHistogram
			= pipeline
				  .texture2D("tex_exposure_histogram", TextureFormat.R32_UINT)
				  .size(256, 1)
				  .create();
	}
}
