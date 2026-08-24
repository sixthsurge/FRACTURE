package pipeline;

import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import resources.Textures;
import util.ProgramFactory;

public class PreTranslucentPasses {
	public static void setup(
		PipelineConfig pipeline,
		Screen screen,
		ProgramFactory factory,
		Textures textures
	) {
		factory.setCurrentStage(pipeline.stage(ProgramStage.PRE_TRANSLUCENT));

		factory.compute2d(
			"gtao_rsm",
			"program/lighting/gtao_rsm",
			"main",
			Math.ceilDiv(screen.renderWidth(), 2),
			Math.ceilDiv(screen.renderHeight(), 2),
			16,
			16
		);

		if (pipeline.settings().getBoolValue("RSM_ENABLED")) {
			factory.compute2d(
				"filter_rsm",
				"program/lighting/filter_rsm",
				"main",
				Math.ceilDiv(screen.renderWidth(), 2),
				Math.ceilDiv(screen.renderHeight(), 2),
				16,
				16
			);
		}

		factory
			.renderSizedCompute(
				"shade_solid",
				"program/lighting/deferred_lighting",
				"main",
				16,
				16
			)
			.overrideObject("tex_scene_write", textures.scene.back().name());
		textures.scene.flip();
	}
}
