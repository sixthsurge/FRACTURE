package pipeline;

import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import resources.Textures;

public class PreRenderPasses {
	public static void
	setup(PipelineConfig pipeline, Screen screen, Textures textures) {
		setupAtmospherePasses(pipeline, textures);

		pipeline.stage(ProgramStage.PRE_RENDER)
			.compute("gen_sky_sh", "program/lighting/gen_sky_sh", "main")
			.dispatch1D(1);
	}

	private static void
	setupAtmospherePasses(PipelineConfig pipeline, Textures textures) {
		pipeline.stage(ProgramStage.PRE_RENDER)
			.composite(
				"atmosphere/transmittance_lut",
				"program/atmosphere",
				"transmittance_lut_main"
			)
			.writes("transmittance", textures.atmosphereTransmittanceLut);

		pipeline.stage(ProgramStage.PRE_RENDER)
			.composite(
				"atmosphere/multiscatter_lut",
				"program/atmosphere",
				"multiscatter_lut_main"
			)
			.writes("multiscatter_energy", textures.atmosphereMultiscatterLut);

		pipeline.stage(ProgramStage.PRE_RENDER)
			.composite(
				"atmosphere/sky_view",
				"program/atmosphere",
				"sky_view_main"
			)
			.writes("sky_radiance", textures.atmosphereSkyView);

		pipeline.stage(ProgramStage.PRE_RENDER)
			.compute(
				"atmosphere/aerial_perspective",
				"program/atmosphere",
				"aerial_perspective_main"
			)
			.dispatch3D(32 / 16, 32 / 16, 32);
	}
}
