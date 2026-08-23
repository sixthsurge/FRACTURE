package pipeline;

import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import resources.Textures;

public class PreOverlayPasses {
	public static void
	setup(PipelineConfig pipeline, Screen screen, Textures textures) {
		setupHiZ(pipeline, screen, textures);

		pipeline.stage(ProgramStage.PRE_OVERLAY)
			.compute("specular", "program/lighting/specular", "main")
			.dispatch2D(
				Math.ceilDiv(screen.renderWidth(), 16),
				Math.ceilDiv(screen.renderHeight(), 16)
			)
			.overrideObject("tex_scene_write", textures.scene.back().name())
			.overrideObject("tex_scene", textures.scene.front().name());
		textures.scene.flip();
	}

	private static void
	setupHiZ(PipelineConfig pipeline, Screen screen, Textures textures) {
		final var maxLod = (int) Math.ceil(
			Math.log(Math.max(screen.windowWidth(), screen.windowHeight()))
			/ Math.log(2.0)
		);
		final var lodCount = Math.min(maxLod, 11);
		final var workGroupsX = Math.ceilDiv(screen.renderWidth(), 64);
		final var workGroupsY = Math.ceilDiv(screen.renderHeight(), 64);

		pipeline.stage(ProgramStage.PRE_OVERLAY)
			.compute("hiz_downsample", "program/lighting/hiz_downsample", "main")
			.overrideObject("imgDst", textures.depthHizMinMax.name())
			.exportInt("mips", lodCount)
			.exportInt("numWorkGroups", workGroupsX * workGroupsY)
			.dispatch2D(workGroupsX, workGroupsY);
	}
}
