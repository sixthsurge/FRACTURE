package fracture.pipeline;

import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import fracture.Resources;
import fracture.util.PipelineBuilder;

public class PreTranslucent {
	public static void setup(PipelineBuilder builder, Resources resources) {
		builder.setStage(ProgramStage.PRE_TRANSLUCENT);

		builder.compute2d(
			"gtao_rsm",
			"program/lighting/gtao_rsm",
			"main",
			Math.ceilDiv(builder.screen().renderWidth(), 2),
			Math.ceilDiv(builder.screen().renderHeight(), 2),
			16,
			16
		);

		if (builder.settings().getBoolValue("RSM_ENABLED")) {
			builder.compute2d(
				"filter_rsm",
				"program/lighting/filter_rsm",
				"main",
				Math.ceilDiv(builder.screen().renderWidth(), 2),
				Math.ceilDiv(builder.screen().renderHeight(), 2),
				16,
				16
			);
		}

		if (builder.settings().getBoolValue("RESTIR_GI_ENABLED")) {
			builder.renderSizedCompute(
				"restir_gi/initial_sample_temporal_reuse",
				"program/lighting/restir_gi/initial_sample_temporal_reuse",
				"main",
				16,
				16
			);

			builder.renderSizedCompute(
				"restir_gi/spatial_reuse",
				"program/lighting/restir_gi/spatial_reuse",
				"main",
				16,
				16
			);
		}

		builder
			.renderSizedCompute(
				"shade_solid",
				"program/lighting/deferred_lighting",
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
