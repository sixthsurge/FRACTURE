package fracture.pipeline;

import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import fracture.Resources;
import fracture.util.PipelineBuilder;

public class ScreenSetup {
	public static void setup(PipelineBuilder builder, Resources resources) {
		builder.setStage(ProgramStage.SCREEN_SETUP);

		// Zero spdGlobalAtomic for FidelityFX SPD.
		builder
			.compute(
				"zero_spd_global_atomic",
				"program/lighting/hiz_downsample",
				"zero_spd_global_atomic"
			)
			.dispatch1D(1);
	}
}
