package resources;

import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.objects.ShadowTexture;
import dev.irisshaders.aperture.api.objects.Texture2D;
import dev.irisshaders.aperture.api.objects.TextureFormat;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import util.Flipper;

public class Textures {
	public static final int ATMOSPHERE_TRANSMITTANCE_LUT_WIDTH = 256;
	public static final int ATMOSPHERE_TRANSMITTANCE_LUT_HEIGHT = 64;

	public static final int ATMOSPHERE_MULTISCATTER_LUT_WIDTH = 32;
	public static final int ATMOSPHERE_MULTISCATTER_LUT_HEIGHT = 32;

	public static final int ATMOSPHERE_SKY_VIEW_LUT_WIDTH = 256;
	public static final int ATMOSPHERE_SKY_VIEW_LUT_HEIGHT = 128;

	public static final int ATMOSPHERE_AP_LUT_WIDTH = 32;
	public static final int ATMOSPHERE_AP_LUT_HEIGHT = 32;
	public static final int ATMOSPHERE_AP_LUT_DEPTH = 32;

	public final Flipper<Texture2D> scene;
	public final Flipper<Texture2D> bloom;
	public final Texture2D gbufferSolid;
	public final Texture2D gbufferTranslucent;
	public final Texture2D depthHizMinMax;
	public final Texture2D atmosphereTransmittance;
	public final Texture2D atmosphereMultiscatter;
	public final Texture2D atmosphereSkyView;
	public final ShadowTexture shadowColor;

	public Textures(PipelineConfig pipeline, Screen screen) {
		pipeline.loadPNGTexture("tex_blue_noise", "texture/blue_noise.png");
		pipeline.loadPNGTexture("tex_galaxy", "texture/galaxy.png");

		final var sceneTexA
			= pipeline.texture2D("tex_scene_a", TextureFormat.RG11B10_UFLOAT)
				  .renderSize()
				  .create();
		final var sceneTexB
			= pipeline.texture2D("tex_scene_b", TextureFormat.RG11B10_UFLOAT)
				  .renderSize()
				  .create();
		scene = new Flipper<>(sceneTexA, sceneTexB);

		final var bloomA
			= pipeline.texture2D("tex_bloom_a", TextureFormat.RG11B10_UFLOAT)
				  .renderSize()
				  .usesMipmaps()
				  .create();
		final var bloomB
			= pipeline.texture2D("tex_bloom_b", TextureFormat.RG11B10_UFLOAT)
				  .renderSize()
				  .usesMipmaps()
				  .create();
		bloom = new Flipper<Texture2D>(bloomA, bloomB);

		// Select texture format for the amount of data needed.
		final var labPbrEnabled
			= pipeline.settings().getBoolValue("LABPBR_SUPPORT_ENABLED");
		final var solidGbufferFormat = labPbrEnabled
			? TextureFormat.RGBA32_UINT
			: TextureFormat.RG32_UINT;
		final var translucentGbufferFormat
			= labPbrEnabled ? TextureFormat.RG32_UINT : TextureFormat.R32_UINT;

		gbufferSolid
			= pipeline.texture2D("tex_gbuffer_solid", solidGbufferFormat)
				  .renderSize()
				  .create();

		gbufferTranslucent
			= pipeline
				  .texture2D(
					  "tex_gbuffer_translucent",
					  translucentGbufferFormat
				  )
				  .renderSize()
				  .create();

		depthHizMinMax
			= pipeline
				  .texture2D("tex_depth_hiz_min_max", TextureFormat.RG32_SFLOAT)
				  .size(screen.renderWidth() / 2, screen.renderHeight() / 2)
				  .usesMipmaps()
				  .create();

		atmosphereTransmittance
			= pipeline
				  .texture2D(
					  "tex_atmosphere_transmittance",
					  TextureFormat.RG11B10_UFLOAT
				  )
				  .size(
					  ATMOSPHERE_TRANSMITTANCE_LUT_WIDTH,
					  ATMOSPHERE_TRANSMITTANCE_LUT_HEIGHT
				  )
				  .create();

		atmosphereMultiscatter
			= pipeline
				  .texture2D(
					  "tex_atmosphere_multiscatter",
					  TextureFormat.RGBA16_SFLOAT
				  )
				  .size(
					  ATMOSPHERE_MULTISCATTER_LUT_WIDTH,
					  ATMOSPHERE_MULTISCATTER_LUT_HEIGHT
				  )
				  .create();

		atmosphereSkyView
			= pipeline
				  .texture2D(
					  "tex_atmosphere_sky_view",
					  TextureFormat.RG11B10_UFLOAT
				  )
				  .size(
					  ATMOSPHERE_SKY_VIEW_LUT_WIDTH,
					  ATMOSPHERE_SKY_VIEW_LUT_HEIGHT
				  )
				  .create();

		pipeline
			.texture3D(
				"tex_atmosphere_aerial_perspective",
				TextureFormat.RG11B10_UFLOAT
			)
			.size(
				ATMOSPHERE_AP_LUT_WIDTH,
				ATMOSPHERE_AP_LUT_HEIGHT,
				ATMOSPHERE_AP_LUT_DEPTH
			)
			.create();

		final var fogVolumeSizeX
			= pipeline.settings().getIntValue("FOG_VOLUME_SIZE_X");
		final var fogVolumeSizeY
			= pipeline.settings().getIntValue("FOG_VOLUME_SIZE_Y");
		final var fogVolumeSizeZ
			= pipeline.settings().getIntValue("FOG_VOLUME_SIZE_Z");
		pipeline
			.texture3D("tex_fog_volume_light_a", TextureFormat.RGBA16_SFLOAT)
			.size(fogVolumeSizeX, fogVolumeSizeY, fogVolumeSizeZ)
			.create();
		pipeline
			.texture3D(
				"tex_fog_volume_extinction_a",
				TextureFormat.RGBA16_SFLOAT
			)
			.size(fogVolumeSizeX, fogVolumeSizeY, fogVolumeSizeZ)
			.create();
		pipeline
			.texture3D("tex_fog_volume_light_b", TextureFormat.RGBA16_SFLOAT)
			.size(fogVolumeSizeX, fogVolumeSizeY, fogVolumeSizeZ)
			.create();
		pipeline
			.texture3D(
				"tex_fog_volume_extinction_b",
				TextureFormat.RGBA16_SFLOAT
			)
			.size(fogVolumeSizeX, fogVolumeSizeY, fogVolumeSizeZ)
			.create();
		pipeline
			.texture3D(
				"tex_fog_volume_integrated_light",
				TextureFormat.RG11B10_UFLOAT
			)
			.size(fogVolumeSizeX, fogVolumeSizeY, fogVolumeSizeZ)
			.create();
		pipeline
			.texture3D(
				"tex_fog_volume_integrated_extinction",
				TextureFormat.RG11B10_UFLOAT
			)
			.size(fogVolumeSizeX, fogVolumeSizeY, fogVolumeSizeZ)
			.create();

		shadowColor = pipeline.shadowTexture(
			"tex_shadow_color",
			TextureFormat.RGBA8_UNORM
		);

		pipeline.texture2D("tex_exposure_histogram", TextureFormat.R32_UINT)
			.size(256, 1)
			.create();
	}
}
