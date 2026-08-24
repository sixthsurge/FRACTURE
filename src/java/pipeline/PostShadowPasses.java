package pipeline;

import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import resources.Textures;
import util.ProgramFactory;

public class PostShadowPasses {
	public static void setup(
		PipelineConfig pipeline,
		Screen screen,
		ProgramFactory factory,
		Textures textures
	) {
		factory.setCurrentStage(pipeline.stage(ProgramStage.POST_SHADOW));

		final var fogVolumeSizeX
			= pipeline.settings().getIntValue("FOG_VOLUME_SIZE_X");
		final var fogVolumeSizeY
			= pipeline.settings().getIntValue("FOG_VOLUME_SIZE_Y");
		final var fogVolumeSizeZ
			= pipeline.settings().getIntValue("FOG_VOLUME_SIZE_Z");

		factory
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

		factory
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

		factory.compute2d(
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
