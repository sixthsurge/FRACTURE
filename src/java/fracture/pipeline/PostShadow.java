package fracture.pipeline;

import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import fracture.Resources;
import fracture.util.PipelineBuilder;

public class PostShadow {
	public static void setup(PipelineBuilder builder, Resources resources) {
		builder.setStage(ProgramStage.POST_SHADOW);

		final var fogVolumeSizeX
			= builder.settings().getIntValue("FOG_VOLUME_SIZE_X");
		final var fogVolumeSizeY
			= builder.settings().getIntValue("FOG_VOLUME_SIZE_Y");
		final var fogVolumeSizeZ
			= builder.settings().getIntValue("FOG_VOLUME_SIZE_Z");

		builder.compute3d(
			"fog/create_volume",
			"program/atmospherics/fog/create_volume",
			"main",
			fogVolumeSizeX,
			fogVolumeSizeY,
			fogVolumeSizeZ,
			8,
			8,
			4
		);

		builder.compute2d(
			"fog/integrate_volume",
			"program/atmospherics/fog/integrate_volume",
			"main",
			fogVolumeSizeX,
			fogVolumeSizeY,
			16,
			16
		);
	}
}
