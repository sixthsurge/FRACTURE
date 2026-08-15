package pipeline;

import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramUsage;
import resources.Textures;

public class ObjectShaders {
	public static void setupOpaque(PipelineConfig pipeline, Textures textures) {
		pipeline
			.object(ProgramUsage.BASIC, "program/object/basic", "BasicObject")
			.writes("gbuffer", textures.gbufferSolid);
	}

	public static void
	setupTranslucent(PipelineConfig pipeline, Textures textures) {
		pipeline
			.object(
				ProgramUsage.TRANSLUCENT,
				"program/object/translucent",
				"TranslucentObject"
			)
			.writes("color", textures.scene.front())
			.writes("gbuffer", textures.gbufferTranslucent);
	}

	public static void setupShadow(PipelineConfig pipeline, Textures textures) {
		if (pipeline.settings().getBoolValue("SHADOW_ENABLED")) {
			pipeline.object(
				ProgramUsage.SHADOW,
				"program/object/shadow",
				"ShadowObject"
			);

			final var translucentShadowUsages = new ProgramUsage[] {
				ProgramUsage.SHADOW_TERRAIN_TRANSLUCENT,
				ProgramUsage.SHADOW_ENTITY_TRANSLUCENT,
				ProgramUsage.SHADOW_BLOCK_ENTITY_TRANSLUCENT,
				ProgramUsage.SHADOW_PARTICLES_TRANSLUCENT
			};
			for (var usage : translucentShadowUsages) {
				pipeline
					.object(
						usage,
						"program/object/shadow_translucent",
						"ShadowObject"
					)
					.writes("color", textures.shadowColor);
			}
		}
	}
}
