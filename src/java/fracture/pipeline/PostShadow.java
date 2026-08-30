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

		builder
			.compute3d(
				"fog/create_volume a",
				"program/volumetrics/fog/create_volume",
				"main",
				fogVolumeSizeX,
				fogVolumeSizeY,
				fogVolumeSizeZ,
				8,
				8,
				4
			)
			.exportInt("ACTIVE_FRAME", 0)
			.overrideObject("tex_fog_volume_light", "tex_fog_volume_light_a")
			.overrideObject(
				"tex_fog_volume_extinction",
				"tex_fog_volume_extinction_a"
			)
			.overrideObject(
				"tex_fog_volume_light_prev",
				"tex_fog_volume_light_b"
			)
			.overrideObject(
				"tex_fog_volume_extinction_prev",
				"tex_fog_volume_extinction_b"
			);

		builder
			.compute3d(
				"fog/create_volume b",
				"program/volumetrics/fog/create_volume",
				"main",
				fogVolumeSizeX,
				fogVolumeSizeY,
				fogVolumeSizeZ,
				8,
				8,
				4
			)
			.exportInt("ACTIVE_FRAME", 1)
			.overrideObject("tex_fog_volume_light", "tex_fog_volume_light_b")
			.overrideObject(
				"tex_fog_volume_extinction",
				"tex_fog_volume_extinction_b"
			)
			.overrideObject(
				"tex_fog_volume_light_prev",
				"tex_fog_volume_light_a"
			)
			.overrideObject(
				"tex_fog_volume_extinction_prev",
				"tex_fog_volume_extinction_a"
			);

		builder.compute2d(
			"fog/integrate_volume",
			"program/volumetrics/fog/integrate_volume",
			"main",
			fogVolumeSizeX,
			fogVolumeSizeY,
			16,
			16
		);
	}
}
