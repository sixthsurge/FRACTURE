package pipeline;

import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import resources.Textures;

public class PostShadowPasses {
	public static void
	setup(PipelineConfig pipeline, Screen screen, Textures textures) {
		final var fogVolumeSizeX
			= pipeline.settings().getIntValue("FOG_VOLUME_SIZE_X");
		final var fogVolumeSizeY
			= pipeline.settings().getIntValue("FOG_VOLUME_SIZE_Y");
		final var fogVolumeSizeZ
			= pipeline.settings().getIntValue("FOG_VOLUME_SIZE_Z");

		pipeline.stage(ProgramStage.POST_SHADOW)
			.compute("fog/create_volume", "program/fog/create_volume", "main")
			.dispatch3D(
				Math.ceilDiv(fogVolumeSizeX, 8),
				Math.ceilDiv(fogVolumeSizeY, 8),
				Math.ceilDiv(fogVolumeSizeZ, 4)
			);

		pipeline.stage(ProgramStage.POST_SHADOW)
			.compute(
				"fog/integrate_volume",
				"program/fog/integrate_volume",
				"main"
			)
			.dispatch3D(
				Math.ceilDiv(fogVolumeSizeX, 16),
				Math.ceilDiv(fogVolumeSizeY, 16),
				1
			);
	}
}
