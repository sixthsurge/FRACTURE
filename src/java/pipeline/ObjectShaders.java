package pipeline;

import dev.irisshaders.aperture.api.objects.ObjectShaderBuilder;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramUsage;
import java.util.function.Function;
import resources.Textures;

public class ObjectShaders {
	private record ObjectShaderUsage(ProgramUsage usage, String constant) {}

	public static void setupOpaque(PipelineConfig pipeline, Textures textures) {
		final var usages = new ObjectShaderUsage[] {
			new ObjectShaderUsage(ProgramUsage.BASIC, "USAGE_BASIC"),
		};
		createObjectShaders((ProgramUsage usage) -> {
			return pipeline.object(usage, "program/object/opaque", "Object")
				.writes("gbuffer", textures.gbufferSolid);
		}, usages);
	}

	public static void
	setupTranslucent(PipelineConfig pipeline, Textures textures) {
		final var usages = new ObjectShaderUsage[] {
			new ObjectShaderUsage(
				ProgramUsage.TRANSLUCENT,
				"USAGE_TRANSLUCENT"
			),
			new ObjectShaderUsage(
				ProgramUsage.HAND,
				"USAGE_HAND"
			),
			new ObjectShaderUsage(
				ProgramUsage.EMISSIVE,
				"USAGE_EMISSIVE"
			),
		};
		createObjectShaders((ProgramUsage usage) -> {
			return pipeline
				.object(usage, "program/object/translucent", "Object")
				.writes("color", textures.scene.front())
				.writes("gbuffer", textures.gbufferTranslucent);
		}, usages);
	}

	public static void setupShadow(PipelineConfig pipeline, Textures textures) {
		if (pipeline.settings().getBoolValue("SHADOW_ENABLED")) {
			if (pipeline.settings().getBoolValue("RSM_ENABLED")) {
				pipeline
					.object(
						ProgramUsage.SHADOW,
						"program/object/shadow_color",
						"Object"
					)
					.writes("color_and_normal", textures.shadowColor);
			} else {
				pipeline.object(
					ProgramUsage.SHADOW,
					"program/object/shadow",
					"Object"
				);
			}

			final var translucentShadowUsages = new ProgramUsage[] {
				ProgramUsage.SHADOW_TERRAIN_TRANSLUCENT,
				ProgramUsage.SHADOW_ENTITY_TRANSLUCENT,
				ProgramUsage.SHADOW_BLOCK_ENTITY_TRANSLUCENT,
				ProgramUsage.SHADOW_PARTICLES_TRANSLUCENT
			};
			for (var usage : translucentShadowUsages) {
				pipeline.object(usage, "program/object/shadow_color", "Object")
					.writes("color_and_normal", textures.shadowColor);
			}
		}
	}

	// Use `createObjectShaderBuilder` to create one object shader per usage. In
	// each program, define constants for each usage string as their index, and
	// define USAGE_CURRENT to be the same index as the current usage.
	private static void createObjectShaders(
		Function<ProgramUsage, ObjectShaderBuilder> createObjectShaderBuilder,
		ObjectShaderUsage[] usages
	) {
		for (int i = 0; i < usages.length; ++i) {
			ObjectShaderBuilder builder
				= createObjectShaderBuilder.apply(usages[i].usage);

			builder = builder.exportInt("USAGE_CURRENT", i);
			for (int j = 0; j < usages.length; ++j) {
				builder = builder.exportInt(usages[j].constant, j);
			}
		}
	}
}
