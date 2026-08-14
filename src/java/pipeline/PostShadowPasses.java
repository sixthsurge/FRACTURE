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
			.compute("fog/create_volume a", "program/fog/create_volume", "main")
			.dispatch3D(
				Math.ceilDiv(fogVolumeSizeX, 8),
				Math.ceilDiv(fogVolumeSizeY, 8),
				Math.ceilDiv(fogVolumeSizeZ, 4)
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

		pipeline.stage(ProgramStage.POST_SHADOW)
			.compute("fog/create_volume b", "program/fog/create_volume", "main")
			.dispatch3D(
				Math.ceilDiv(fogVolumeSizeX, 8),
				Math.ceilDiv(fogVolumeSizeY, 8),
				Math.ceilDiv(fogVolumeSizeZ, 4)
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
