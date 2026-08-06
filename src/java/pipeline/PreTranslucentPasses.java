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
				"deferred_shading",
				"program/lighting/deferred_shading",
				"main"
			)
			.writes("radiance", textures.scene.back());

		// Must have scene data in front and back for translucent passes to read
		// and write sceneTex.
		pipeline.stage(ProgramStage.PRE_TRANSLUCENT)
			.copy(textures.scene.back(), textures.scene.front());
	}
}
