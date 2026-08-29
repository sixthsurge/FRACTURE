package pipeline;

import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import org.joml.Vector4f;
import resources.FeatureToggles;
import resources.Textures;
import util.ProgramFactory;

public class PreRenderPasses {
	public static void setup(
		PipelineConfig pipeline,
		Screen screen,
		ProgramFactory factory,
		Textures textures,
		FeatureToggles toggles
	) {
		factory.setCurrentStage(pipeline.stage(ProgramStage.PRE_RENDER));

		if (pipeline.settings().getBoolValue("DEBUG")) {
			pipeline.stage(ProgramStage.PRE_RENDER)
				.clearTo(new Vector4f(0.0f), textures.debug);
		}

		if (toggles.vxrtData()) {
			factory.compute3d(
				"vxrt/clear_face_data",
				"program/lighting/voxel_data/clear_face_data",
				"main",
				pipeline.settings().getIntValue("VOXEL_RT_VOLUME_SIZE_X") * 6,
				pipeline.settings().getIntValue("VOXEL_RT_VOLUME_SIZE_Y"),
				pipeline.settings().getIntValue("VOXEL_RT_VOLUME_SIZE_Z"),
				8,
				8,
				4
			);
		}

		setupAtmosphere(pipeline, textures, factory);

		factory.compute("gen_sky_sh", "program/lighting/gen_sky_sh", "main")
			.dispatch1D(1);
	}

	private static void setupAtmosphere(
		PipelineConfig pipeline,
		Textures textures,
		ProgramFactory factory
	) {
		factory.compute2d(
			"atmosphere/gen_transmittance_lut",
			"program/volumetrics/atmosphere/gen_transmittance_lut",
			"main",
			Textures.ATMOSPHERE_TRANSMITTANCE_LUT_WIDTH,
			Textures.ATMOSPHERE_TRANSMITTANCE_LUT_HEIGHT,
			16,
			16
		);

		factory.compute2d(
			"atmosphere/gen_multiscatter_lut",
			"program/volumetrics/atmosphere/gen_multiscatter_lut",
			"main",
			Textures.ATMOSPHERE_MULTISCATTER_LUT_WIDTH,
			Textures.ATMOSPHERE_MULTISCATTER_LUT_HEIGHT,
			8,
			8
		);

		factory.compute2d(
			"atmosphere/gen_sky_view_lut",
			"program/volumetrics/atmosphere/gen_sky_view_lut",
			"main",
			Textures.ATMOSPHERE_SKY_VIEW_LUT_WIDTH,
			Textures.ATMOSPHERE_SKY_VIEW_LUT_HEIGHT,
			16,
			16
		);

		if (pipeline.settings().getBoolValue("ATMOSPHERE_AP_LUT_ENABLED")) {
			factory.compute3d(
				"atmosphere/gen_aerial_perspective_lut",
				"program/volumetrics/atmosphere/gen_aerial_perspective_lut",
				"main",
				Textures.ATMOSPHERE_AP_LUT_WIDTH,
				Textures.ATMOSPHERE_AP_LUT_HEIGHT,
				Textures.ATMOSPHERE_AP_LUT_DEPTH,
				4,
				4,
				4
			);
		}
	}
}
