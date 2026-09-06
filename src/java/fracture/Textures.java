package fracture;

import dev.irisshaders.aperture.api.objects.ArrayTexture;
import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.objects.Texture2D;
import dev.irisshaders.aperture.api.objects.TextureFormat;
import dev.irisshaders.aperture.api.objects.TextureReference;
import dev.irisshaders.aperture.api.pipeline.FrameState;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import fracture.util.Flipper;
import fracture.util.Util;

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
	public Texture2D debug;

	// TAA

	public final Texture2D taaOutputA;
	public final Texture2D taaOutputB;
	public final TextureReference taaOutputCurrent;
	public final TextureReference taaOutputPrevious;

	// G-Buffer

	public final Texture2D gbufferOpaque;
	public final Texture2D gbufferTranslucent;

	// Hi-Z depth

	public final Texture2D depthHizMinMax;

	// Atmosphere

	public final Texture2D atmosphereTransmittance;
	public final Texture2D atmosphereMultiscatter;
	public final Texture2D atmosphereSkyView;

	// Quarter-res general

	public final Texture2D qresTemporalDataA;
	public final Texture2D qresTemporalDataB;
	public final TextureReference qresTemporalDataCurrent;
	public final TextureReference qresTemporalDataPrevious;

	// GTAO

	public final Texture2D gtaoOutputA;
	public final Texture2D gtaoOutputB;
	public final TextureReference gtaoOutputCurrent;
	public final TextureReference gtaoOutputPrevious;

	// RSM

	public final Texture2D rsmOutputRaw;
	public final Texture2D rsmOutputFiltered;

	// Restir GI

	public Texture2D reserviourTemporal1A;
	public Texture2D reserviourTemporal2A;
	public Texture2D reserviourTemporal3A;
	public Texture2D reserviourTemporal4A;
	public Texture2D reserviourTemporal1B;
	public Texture2D reserviourTemporal2B;
	public Texture2D reserviourTemporal3B;
	public Texture2D reserviourTemporal4B;
	public Texture2D reserviourSpatial1A;
	public Texture2D reserviourSpatial2A;
	public Texture2D reserviourSpatial3A;
	public Texture2D reserviourSpatial4A;
	public Texture2D reserviourSpatial1B;
	public Texture2D reserviourSpatial2B;
	public Texture2D reserviourSpatial3B;
	public Texture2D reserviourSpatial4B;
	public TextureReference reserviourTemporal1;
	public TextureReference reserviourTemporal2;
	public TextureReference reserviourTemporal3;
	public TextureReference reserviourTemporal4;
	public TextureReference reserviourTemporal1Prev;
	public TextureReference reserviourTemporal2Prev;
	public TextureReference reserviourTemporal3Prev;
	public TextureReference reserviourTemporal4Prev;
	public TextureReference reserviourSpatial1;
	public TextureReference reserviourSpatial2;
	public TextureReference reserviourSpatial3;
	public TextureReference reserviourSpatial4;
	public TextureReference reserviourSpatial1Prev;
	public TextureReference reserviourSpatial2Prev;
	public TextureReference reserviourSpatial3Prev;
	public TextureReference reserviourSpatial4Prev;

	// Shadow

	public final ArrayTexture shadowColor;
	public final ArrayTexture shadowRsmData;

	public Textures(
		PipelineConfig pipeline,
		Screen screen,
		FeatureToggles toggles
	) {
		pipeline.loadPNGTexture("tex_blue_noise", "texture/blue_noise.png");
		pipeline.loadPNGTexture(
			"tex_worley_noise_2d",
			"texture/worley_noise_2d.png"
		);
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

		debug = pipeline.texture2D("tex_debug", TextureFormat.RGBA8_UNORM)
					.windowSize()
					.create();

		// Bloom

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

		// TAA

		taaOutputA
			= pipeline
				  .texture2D(
					  "tex_taa_output_a",
					  pipeline.settings().getBoolValue("INFINITE_ACCUMULATION")
						  ? TextureFormat.RGBA32_SFLOAT
						  : TextureFormat.RGBA16_SFLOAT
				  )
				  .windowSize()
				  .create();
		taaOutputB = pipeline.texture2D("tex_taa_output_b", taaOutputA.format())
						 .windowSize()
						 .create();
		taaOutputCurrent
			= pipeline.reference("tex_taa_output_current", taaOutputA.format())
				  .windowSize()
				  .createEmpty();
		taaOutputPrevious
			= pipeline.reference("tex_taa_output_prev", taaOutputA.format())
				  .windowSize()
				  .createEmpty();

		// G-Buffer

		// Select texture format for the amount of data needed.
		final var labPbrEnabled
			= pipeline.settings().getBoolValue("LABPBR_SUPPORT_ENABLED");
		final var OpaqueGbufferFormat = labPbrEnabled
			? TextureFormat.RGBA32_UINT
			: TextureFormat.RG32_UINT;

		gbufferOpaque
			= pipeline.texture2D("tex_gbuffer_opaque", OpaqueGbufferFormat)
				  .renderSize()
				  .create();

		gbufferTranslucent
			= pipeline
				  .texture2D("tex_gbuffer_translucent", TextureFormat.RG32_UINT)
				  .renderSize()
				  .create();

		// Hi-Z depth

		// The texture must be padded so that the all lods except the last are
		// even-sized.
		final var maxLod = (int) Math.ceil(
			Math.log(Math.max(screen.windowWidth(), screen.windowHeight()))
			/ Math.log(2.0)
		);
		final var lodCount = Math.min(maxLod, 11);
		// Subtract 2, because:
		// - last mip doesn't need to be even.
		// - the first mip in the texture is actually the 2nd mip in the whole
		// chain.
		final var roundFactor = Math.powExact(2, lodCount - 2);
		final var hiZWidth
			= Util.roundUp(Math.ceilDiv(screen.renderWidth(), 2), roundFactor);
		final var hiZHeight
			= Util.roundUp(Math.ceilDiv(screen.renderHeight(), 2), roundFactor);

		depthHizMinMax
			= pipeline
				  .texture2D("tex_depth_hiz_min_max", TextureFormat.RG32_SFLOAT)
				  .size(hiZWidth, hiZHeight)
				  .usesMipmaps()
				  .create();

		// Atmosphere

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

		// Quarter-res general

		final var qresWidth = Math.ceilDiv(screen.renderWidth(), 2);
		final var qresHeight = Math.ceilDiv(screen.renderHeight(), 2);

		qresTemporalDataA
			= pipeline
				  .texture2D(
					  "tex_qres_temporal_data_a",
					  TextureFormat.RGBA16_SFLOAT
				  )
				  .size(qresWidth, qresHeight)
				  .create();
		qresTemporalDataB
			= pipeline
				  .texture2D(
					  "tex_qres_temporal_data_b",
					  TextureFormat.RGBA16_SFLOAT
				  )
				  .size(qresWidth, qresHeight)
				  .create();
		qresTemporalDataCurrent
			= pipeline
				  .reference(
					  "tex_qres_temporal_data_current",
					  qresTemporalDataA.format()
				  )
				  .size(qresWidth, qresHeight)
				  .createEmpty();
		qresTemporalDataPrevious
			= pipeline
				  .reference(
					  "tex_qres_temporal_data_prev",
					  qresTemporalDataA.format()
				  )
				  .size(qresWidth, qresHeight)
				  .createEmpty();

		// GTAO

		gtaoOutputA
			= pipeline
				  .texture2D("tex_gtao_output_a", TextureFormat.RGBA16_SFLOAT)
				  .size(qresWidth, qresHeight)
				  .create();
		gtaoOutputB
			= pipeline
				  .texture2D("tex_gtao_output_b", TextureFormat.RGBA16_SFLOAT)
				  .size(qresWidth, qresHeight)
				  .create();
		gtaoOutputCurrent
			= pipeline
				  .reference("tex_gtao_output_current", gtaoOutputA.format())
				  .size(qresWidth, qresHeight)
				  .createEmpty();
		gtaoOutputPrevious
			= pipeline.reference("tex_gtao_output_prev", gtaoOutputA.format())
				  .size(qresWidth, qresHeight)
				  .createEmpty();

		// RSM

		rsmOutputRaw
			= pipeline
				  .texture2D("tex_rsm_output_raw", TextureFormat.RGBA16_SFLOAT)
				  .size(qresWidth, qresHeight)
				  .create();
		rsmOutputFiltered
			= pipeline
				  .texture2D(
					  "tex_rsm_output_filtered",
					  TextureFormat.RGBA16_SFLOAT
				  )
				  .size(qresWidth, qresHeight)
				  .create();

		// Fog

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

		shadowColor
			= pipeline
				  .arrayTexture(
					  "tex_shadow_color",
					  TextureFormat.RG11B10_UFLOAT
				  )
				  .shadowSize()
				  .create();
		shadowRsmData
			= pipeline
				  .arrayTexture("tex_shadow_rsm_data", TextureFormat.RG32_UINT)
				  .shadowSize()
				  .create();

		// Exposure histogram

		pipeline.texture2D("tex_exposure_histogram", TextureFormat.R32_UINT)
			.size(256, 1)
			.create();

		// Voxel RT

		if (toggles.vxrtData) {
			pipeline.texture3D("tex_voxel_face_data", TextureFormat.RG32_UINT)
				.size(
					pipeline.settings().getIntValue("VOXEL_RT_VOLUME_SIZE_X")
						* 6,
					pipeline.settings().getIntValue("VOXEL_RT_VOLUME_SIZE_Y"),
					pipeline.settings().getIntValue("VOXEL_RT_VOLUME_SIZE_Z")
				)
				.create();
		}

		// Restir GI

		if (pipeline.settings().getBoolValue("RESTIR_GI_ENABLED")) {
			final var reserviourWidth = screen.renderWidth();
			final var reserviourHeight = screen.renderHeight();

			reserviourTemporal1A
				= pipeline
					  .texture2D(
						  "tex_reserviour_temporal_1a",
						  TextureFormat.RGBA16_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .create();
			reserviourTemporal2A
				= pipeline
					  .texture2D(
						  "tex_reserviour_temporal_2a",
						  TextureFormat.RGBA32_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .create();
			reserviourTemporal3A
				= pipeline
					  .texture2D(
						  "tex_reserviour_temporal_3a",
						  TextureFormat.RGBA32_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .create();
			reserviourTemporal4A
				= pipeline
					  .texture2D(
						  "tex_reserviour_temporal_4a",
						  TextureFormat.RGBA8_UNORM
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .create();

			reserviourTemporal1B
				= pipeline
					  .texture2D(
						  "tex_reserviour_temporal_1b",
						  TextureFormat.RGBA16_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .create();
			reserviourTemporal2B
				= pipeline
					  .texture2D(
						  "tex_reserviour_temporal_2b",
						  TextureFormat.RGBA32_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .create();
			reserviourTemporal3B
				= pipeline
					  .texture2D(
						  "tex_reserviour_temporal_3b",
						  TextureFormat.RGBA32_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .create();
			reserviourTemporal4B
				= pipeline
					  .texture2D(
						  "tex_reserviour_temporal_4b",
						  TextureFormat.RGBA8_UNORM
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .create();

			reserviourTemporal1
				= pipeline
					  .reference(
						  "tex_reserviour_temporal_1",
						  TextureFormat.RGBA16_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .createEmpty();
			reserviourTemporal2
				= pipeline
					  .reference(
						  "tex_reserviour_temporal_2",
						  TextureFormat.RGBA32_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .createEmpty();
			reserviourTemporal3
				= pipeline
					  .reference(
						  "tex_reserviour_temporal_3",
						  TextureFormat.RGBA32_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .createEmpty();
			reserviourTemporal4
				= pipeline
					  .reference(
						  "tex_reserviour_temporal_4",
						  TextureFormat.RGBA8_UNORM
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .createEmpty();

			reserviourTemporal1Prev
				= pipeline
					  .reference(
						  "tex_reserviour_temporal_1_prev",
						  TextureFormat.RGBA16_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .createEmpty();
			reserviourTemporal2Prev
				= pipeline
					  .reference(
						  "tex_reserviour_temporal_2_prev",
						  TextureFormat.RGBA32_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .createEmpty();
			reserviourTemporal3Prev
				= pipeline
					  .reference(
						  "tex_reserviour_temporal_3_prev",
						  TextureFormat.RGBA32_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .createEmpty();
			reserviourTemporal4Prev
				= pipeline
					  .reference(
						  "tex_reserviour_temporal_4_prev",
						  TextureFormat.RGBA8_UNORM
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .createEmpty();

			reserviourSpatial1A
				= pipeline
					  .texture2D(
						  "tex_reserviour_spatial_1a",
						  TextureFormat.RGBA16_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .create();
			reserviourSpatial2A
				= pipeline
					  .texture2D(
						  "tex_reserviour_spatial_2a",
						  TextureFormat.RGBA32_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .create();
			reserviourSpatial3A
				= pipeline
					  .texture2D(
						  "tex_reserviour_spatial_3a",
						  TextureFormat.RGBA32_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .create();
			reserviourSpatial4A
				= pipeline
					  .texture2D(
						  "tex_reserviour_spatial_4a",
						  TextureFormat.RGBA8_UNORM
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .create();

			reserviourSpatial1B
				= pipeline
					  .texture2D(
						  "tex_reserviour_spatial_1b",
						  TextureFormat.RGBA16_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .create();
			reserviourSpatial2B
				= pipeline
					  .texture2D(
						  "tex_reserviour_spatial_2b",
						  TextureFormat.RGBA32_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .create();
			reserviourSpatial3B
				= pipeline
					  .texture2D(
						  "tex_reserviour_spatial_3b",
						  TextureFormat.RGBA32_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .create();
			reserviourSpatial4B
				= pipeline
					  .texture2D(
						  "tex_reserviour_spatial_4b",
						  TextureFormat.RGBA8_UNORM
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .create();

			reserviourSpatial1
				= pipeline
					  .reference(
						  "tex_reserviour_spatial_1",
						  TextureFormat.RGBA16_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .createEmpty();
			reserviourSpatial2
				= pipeline
					  .reference(
						  "tex_reserviour_spatial_2",
						  TextureFormat.RGBA32_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .createEmpty();
			reserviourSpatial3
				= pipeline
					  .reference(
						  "tex_reserviour_spatial_3",
						  TextureFormat.RGBA32_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .createEmpty();
			reserviourSpatial4
				= pipeline
					  .reference(
						  "tex_reserviour_spatial_4",
						  TextureFormat.RGBA8_UNORM
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .createEmpty();

			reserviourSpatial1Prev
				= pipeline
					  .reference(
						  "tex_reserviour_spatial_1_prev",
						  TextureFormat.RGBA16_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .createEmpty();
			reserviourSpatial2Prev
				= pipeline
					  .reference(
						  "tex_reserviour_spatial_2_prev",
						  TextureFormat.RGBA32_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .createEmpty();
			reserviourSpatial3Prev
				= pipeline
					  .reference(
						  "tex_reserviour_spatial_3_prev",
						  TextureFormat.RGBA32_SFLOAT
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .createEmpty();
			reserviourSpatial4Prev
				= pipeline
					  .reference(
						  "tex_reserviour_spatial_4_prev",
						  TextureFormat.RGBA8_UNORM
					  )
					  .size(reserviourWidth, reserviourHeight)
					  .createEmpty();
		}
	}

	// Called in onNewFrame.
	public void updateReferences(FrameState state) {
		final var frameCounter
			= state.uniforms().getInt("ap.timing.frameCounter");
		final var oddFrame = (frameCounter & 1) == 0;

		taaOutputCurrent.set(oddFrame ? taaOutputA : taaOutputB);
		taaOutputPrevious.set(oddFrame ? taaOutputB : taaOutputA);

		gtaoOutputCurrent.set(oddFrame ? gtaoOutputA : gtaoOutputB);
		gtaoOutputPrevious.set(oddFrame ? gtaoOutputB : gtaoOutputA);

		qresTemporalDataCurrent.set(
			oddFrame ? qresTemporalDataA : qresTemporalDataB
		);
		qresTemporalDataPrevious.set(
			oddFrame ? qresTemporalDataB : qresTemporalDataA
		);

		if (reserviourTemporal1 != null) {
			reserviourTemporal1.set(
				oddFrame ? reserviourTemporal1A : reserviourTemporal1B
			);
			reserviourTemporal2.set(
				oddFrame ? reserviourTemporal2A : reserviourTemporal2B
			);
			reserviourTemporal3.set(
				oddFrame ? reserviourTemporal3A : reserviourTemporal3B
			);
			reserviourTemporal4.set(
				oddFrame ? reserviourTemporal4A : reserviourTemporal4B
			);
			reserviourTemporal1Prev.set(
				oddFrame ? reserviourTemporal1B : reserviourTemporal1A
			);
			reserviourTemporal2Prev.set(
				oddFrame ? reserviourTemporal2B : reserviourTemporal2A
			);
			reserviourTemporal3Prev.set(
				oddFrame ? reserviourTemporal3B : reserviourTemporal3A
			);
			reserviourTemporal4Prev.set(
				oddFrame ? reserviourTemporal4B : reserviourTemporal4A
			);

			reserviourSpatial1.set(
				oddFrame ? reserviourSpatial1A : reserviourSpatial1B
			);
			reserviourSpatial2.set(
				oddFrame ? reserviourSpatial2A : reserviourSpatial2B
			);
			reserviourSpatial3.set(
				oddFrame ? reserviourSpatial3A : reserviourSpatial3B
			);
			reserviourSpatial4.set(
				oddFrame ? reserviourSpatial4A : reserviourSpatial4B
			);
			reserviourSpatial1Prev.set(
				oddFrame ? reserviourSpatial1B : reserviourSpatial1A
			);
			reserviourSpatial2Prev.set(
				oddFrame ? reserviourSpatial2B : reserviourSpatial2A
			);
			reserviourSpatial3Prev.set(
				oddFrame ? reserviourSpatial3B : reserviourSpatial3A
			);
			reserviourSpatial4Prev.set(
				oddFrame ? reserviourSpatial4B : reserviourSpatial4A
			);
		}
	}
}
