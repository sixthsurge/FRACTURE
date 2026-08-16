package pipeline;

import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import resources.Textures;

public class PreRenderPasses {
	public static void
	setup(PipelineConfig pipeline, Screen screen, Textures textures) {
		setupAtmosphere(pipeline, textures);

		pipeline.stage(ProgramStage.PRE_RENDER)
			.compute("gen_sky_sh", "program/gen_sky_sh", "main")
			.dispatch1D(1);
	}

	private static void
	setupAtmosphere(PipelineConfig pipeline, Textures textures) {
		pipeline.stage(ProgramStage.PRE_RENDER)
			.compute(
				"atmosphere/gen_transmittance_lut",
				"program/atmosphere/gen_transmittance_lut",
				"main"
			)
			.dispatch2D(
				Math.ceilDiv(Textures.ATMOSPHERE_TRANSMITTANCE_LUT_WIDTH, 16),
				Math.ceilDiv(Textures.ATMOSPHERE_TRANSMITTANCE_LUT_HEIGHT, 16)
			);

		pipeline.stage(ProgramStage.PRE_RENDER)
			.compute(
				"atmosphere/gen_multiscatter_lut",
				"program/atmosphere/gen_multiscatter_lut",
				"main"
			)
			.dispatch2D(
				Math.ceilDiv(Textures.ATMOSPHERE_MULTISCATTER_LUT_WIDTH, 8),
				Math.ceilDiv(Textures.ATMOSPHERE_MULTISCATTER_LUT_HEIGHT, 8)
			);

		pipeline.stage(ProgramStage.PRE_RENDER)
			.compute(
				"atmosphere/gen_sky_view_lut",
				"program/atmosphere/gen_sky_view_lut",
				"main"
			)
			.dispatch2D(
				Math.ceilDiv(Textures.ATMOSPHERE_SKY_VIEW_LUT_WIDTH, 16),
				Math.ceilDiv(Textures.ATMOSPHERE_SKY_VIEW_LUT_HEIGHT, 16)
			);

		if (pipeline.settings().getBoolValue("ATMOSPHERE_AP_LUT_ENABLED")) {
			pipeline.stage(ProgramStage.PRE_RENDER)
				.compute(
					"atmosphere/gen_aerial_perspective_lut",
					"program/atmosphere/gen_aerial_perspective_lut",
					"main"
				)
				.dispatch3D(
					Math.ceilDiv(Textures.ATMOSPHERE_AP_LUT_WIDTH, 16),
					Math.ceilDiv(Textures.ATMOSPHERE_AP_LUT_DEPTH, 16),
					Math.ceilDiv(Textures.ATMOSPHERE_AP_LUT_DEPTH, 16)
				);
		}
	}
}
