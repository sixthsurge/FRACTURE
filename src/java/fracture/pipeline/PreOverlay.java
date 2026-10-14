package fracture.pipeline;

import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import fracture.Resources;
import fracture.Textures;
import fracture.util.PipelineBuilder;

public class PreOverlay {
	public static void setup(PipelineBuilder builder, Resources resources) {
		builder.setStage(ProgramStage.PRE_OVERLAY);

		setupHiZ(builder, resources);

		if (resources.toggles().roughSpecular) {
			final var roughSpecularRes = Textures.getRoughSpecularResolution(
				builder.screen(),
				builder.settings()
			);

			builder
				.compute2d(
					"specular/rough",
					"program/lighting/specular/rough",
					"main",
					roughSpecularRes.x,
					roughSpecularRes.y,
					16,
					16
				)
				.overrideObject(
					"tex_scene",
					resources.textures().scene.front().name()
				);

			builder.compute2d(
				"specular/recurrent_filter",
				"program/lighting/specular/recurrent_filter",
				"main",
				roughSpecularRes.x,
				roughSpecularRes.y,
				16,
				16
			);
		}
		builder
			.renderSizedCompute(
				"specular/smooth_and_water",
				"program/lighting/specular/mirror_and_water",
				"main",
				16,
				16
			)
			.overrideObject(
				"tex_scene_write",
				resources.textures().scene.back().name()
			)
			.overrideObject(
				"tex_scene",
				resources.textures().scene.front().name()
			);
		resources.textures().scene.flip();
	}

	private static void setupHiZ(PipelineBuilder builder, Resources resources) {
		final var maxLod = (int) Math.ceil(
			Math.log(Math.max(
				builder.screen().windowWidth(),
				builder.screen().windowHeight()
			))
			/ Math.log(2.0)
		);
		final var lodCount = Math.min(maxLod, 11);
		final var workGroupsX
			= Math.ceilDiv(builder.screen().renderWidth(), 64);
		final var workGroupsY
			= Math.ceilDiv(builder.screen().renderHeight(), 64);

		builder
			.compute(
				"hiz_downsample",
				"program/lighting/hiz_downsample",
				"main"
			)
			.overrideObject(
				"imgDst",
				resources.textures().depthHizMinMax.name()
			)
			.exportInt("mips", lodCount)
			.exportInt("numWorkGroups", workGroupsX * workGroupsY)
			.dispatch2D(workGroupsX, workGroupsY);
	}
}
