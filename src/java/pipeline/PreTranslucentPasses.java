package pipeline;

import dev.irisshaders.aperture.api.commands.MipCalculator;
import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import resources.Textures;

public class PreTranslucentPasses {
	public static void
	setup(PipelineConfig pipeline, Screen screen, Textures textures) {
		// Create Hi-Z min/max depth texture.
		{
			final var maxLod = (int) Math.ceil(
				Math.log(Math.max(screen.windowWidth(), screen.windowHeight()))
				/ Math.log(2.0)
			);
			final var lodCount = Math.min(maxLod, 11);
			final var workGroupsX = Math.ceilDiv(screen.renderWidth(), 64);
			final var workGroupsY = Math.ceilDiv(screen.renderHeight(), 64);

			pipeline.stage(ProgramStage.PRE_TRANSLUCENT)
				.compute("hiz_downsample", "program/hiz_downsample", "main")
				.overrideObject("imgDst", textures.depthHizMinMax.name())
				.exportInt("mips", lodCount)
				.exportInt("numWorkGroups", workGroupsX * workGroupsY)
				.dispatch2D(workGroupsX, workGroupsY);
		}

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
