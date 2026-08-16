package pipeline;

import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import resources.Textures;

public class PreTranslucentPasses {
	public static void
	setup(PipelineConfig pipeline, Screen screen, Textures textures) {
		pipeline.stage(ProgramStage.PRE_TRANSLUCENT)
			.compute("shade_solid", "program/shade_solid", "main")
			.dispatch2D(
				Math.ceilDiv(screen.renderWidth(), 16),
				Math.ceilDiv(screen.renderWidth(), 16)
			)
			.overrideObject("tex_scene_write", textures.scene.back().name());
		textures.scene.flip();
	}
}
