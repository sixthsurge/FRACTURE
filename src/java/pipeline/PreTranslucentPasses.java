package pipeline;

import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import resources.Textures;

public class PreTranslucentPasses {
	public static void
	setup(PipelineConfig pipeline, Screen screen, Textures textures) {
		pipeline.stage(ProgramStage.PRE_TRANSLUCENT)
			.composite(
				"shade_solid",
				"program/shade_solid",
				"main"
			)
			.writes("radiance", textures.scene.back());
		textures.scene.flip();
	}
}
