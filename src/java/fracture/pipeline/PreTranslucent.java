package fracture.pipeline;

import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import fracture.Resources;
import fracture.Textures;
import fracture.util.PipelineBuilder;

public class PreTranslucent {
	public static void setup(PipelineBuilder builder, Resources resources) {
		builder.setStage(ProgramStage.PRE_TRANSLUCENT);

		if (resources.toggles().clouds) {
			final var cloudsRenderScale
				= builder.settings().getFloatValue("CLOUDS_RENDER_SCALE");
			final var cloudsRenderWidth = (int) Math.ceil(
				builder.screen().renderWidth() * cloudsRenderScale
			);
			final var cloudsRenderHeight = (int) Math.ceil(
				builder.screen().renderHeight() * cloudsRenderScale
			);

			builder.compute2d(
				"clouds/render",
				"program/atmospherics/clouds/render",
				"main",
				cloudsRenderWidth,
				cloudsRenderHeight,
				16,
				16
			);

			builder.renderSizedCompute(
				"clouds/filter",
				"program/atmospherics/clouds/filter",
				"main",
				16,
				16
			);
		}

		final var indirectRes = Textures.getIndirectLightingResolution(
			builder.screen(),
			builder.settings()
		);

		if (builder.settings().getBoolValue("RESTIR_GI_ENABLED")) {
			builder.compute2d(
				"restir_gi/initial_sample_temporal_reuse",
				"program/lighting/restir_gi/initial_sample_temporal_reuse",
				"main",
				indirectRes.x,
				indirectRes.y,
				16,
				16
			);

			builder.compute2d(
				"restir_gi/spatial_reuse",
				"program/lighting/restir_gi/spatial_reuse",
				"main",
				indirectRes.x,
				indirectRes.y,
				16,
				16
			);
		}

		builder.compute2d(
			"indirect/main",
			"program/lighting/indirect/main",
			"main",
			indirectRes.x,
			indirectRes.y,
			16,
			16
		);

		builder.compute2d(
			"indirect/recurrent_filter",
			"program/lighting/indirect/recurrent_filter",
			"main",
			indirectRes.x,
			indirectRes.y,
			16,
			16
		);

		builder
			.renderSizedCompute(
				"shade_solid",
				"program/lighting/shade_solid",
				"main",
				16,
				16
			)
			.overrideObject(
				"tex_scene_write",
				resources.textures().scene.back().name()
			);
		resources.textures().scene.flip();
	}
}
