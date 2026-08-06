package pipeline;

import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import resources.Textures;

public class PostRenderPasses {
	public static void
	setup(PipelineConfig pipeline, Screen screen, Textures textures) {
		pipeline.stage(ProgramStage.POST_RENDER)
			.compute(
				"exposure/clear_histogram",
				"program/exposure/clear_histogram",
				"main"
			)
			.dispatch1D(1);

		pipeline.stage(ProgramStage.POST_RENDER)
			.compute(
				"exposure/build_histogram",
				"program/exposure/build_histogram",
				"main"
			)
			.dispatch2D(
				Math.ceilDiv(screen.renderWidth(), 32),
				Math.ceilDiv(screen.renderHeight(), 32)
			)
			.overrideObject("tex_scene", textures.scene.front().name());

		pipeline.stage(ProgramStage.POST_RENDER)
			.compute(
				"exposure/calculate_exposure",
				"program/exposure/calculate_exposure",
				"main"
			)
			.dispatch1D(1);

		pipeline.combinationPass("program/combination")
			.overrideObject("tex_scene", textures.scene.front().name());
	}
}
