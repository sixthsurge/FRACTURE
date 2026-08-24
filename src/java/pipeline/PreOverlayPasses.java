package pipeline;

import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import resources.Textures;
import util.ProgramFactory;

public class PreOverlayPasses {
	public static void setup(
		PipelineConfig pipeline,
		Screen screen,
		ProgramFactory factory,
		Textures textures
	) {
		factory.setCurrentStage(pipeline.stage(ProgramStage.PRE_OVERLAY));

		setupHiZ(pipeline, screen, factory, textures);

		factory
			.renderSizedCompute(
				"specular",
				"program/lighting/specular",
				"main",
				16,
				16
			)
			.overrideObject("tex_scene_write", textures.scene.back().name())
			.overrideObject("tex_scene", textures.scene.front().name());
		textures.scene.flip();
	}

	private static void setupHiZ(
		PipelineConfig pipeline,
		Screen screen,
		ProgramFactory factory,
		Textures textures
	) {
		final var maxLod = (int) Math.ceil(
			Math.log(Math.max(screen.windowWidth(), screen.windowHeight()))
			/ Math.log(2.0)
		);
		final var lodCount = Math.min(maxLod, 11);
		final var workGroupsX = Math.ceilDiv(screen.renderWidth(), 64);
		final var workGroupsY = Math.ceilDiv(screen.renderHeight(), 64);

		factory
			.compute(
				"hiz_downsample",
				"program/lighting/hiz_downsample",
				"main"
			)
			.overrideObject("imgDst", textures.depthHizMinMax.name())
			.exportInt("mips", lodCount)
			.exportInt("numWorkGroups", workGroupsX * workGroupsY)
			.dispatch2D(workGroupsX, workGroupsY);
	}
}
