package fracture.pipeline;

import dev.irisshaders.aperture.api.objects.ObjectShaderBuilder;
import dev.irisshaders.aperture.api.pipeline.ProgramUsage;
import fracture.Resources;
import fracture.util.PipelineBuilder;
import java.util.function.Function;

public class ObjectShaders {
	private record ObjectShaderUsage(ProgramUsage usage, String constant) {}

	public static void
	setupOpaque(PipelineBuilder builder, Resources resources) {
		final var usages = new ObjectShaderUsage[] {
			new ObjectShaderUsage(ProgramUsage.BASIC, "USAGE_BASIC"),
			new ObjectShaderUsage(
				ProgramUsage.TERRAIN_SOLID,
				"USAGE_TERRAIN_SOLID"
			),
			new ObjectShaderUsage(
				ProgramUsage.TERRAIN_CUTOUT,
				"USAGE_TERRAIN_CUTOUT"
			),
		};
		createObjectShaders((ProgramUsage usage) -> {
			return builder.object(usage, "program/object/opaque", "Object")
				.writes("gbuffer", resources.textures().gbufferOpaque);
		}, usages);
	}

	public static void
	setupTranslucent(PipelineBuilder builder, Resources resources) {
		final var usages = new ObjectShaderUsage[] {
			new ObjectShaderUsage(
				ProgramUsage.TRANSLUCENT,
				"USAGE_TRANSLUCENT"
			),
			new ObjectShaderUsage(
				ProgramUsage.TERRAIN_TRANSLUCENT,
				"USAGE_TERRAIN_TRANSLUCENT"
			),
			new ObjectShaderUsage(ProgramUsage.EMISSIVE, "USAGE_EMISSIVE"),
		};
		createObjectShaders((ProgramUsage usage) -> {
			return builder.object(usage, "program/object/translucent", "Object")
				.writes("color", resources.textures().scene.front())
				.writes("gbuffer", resources.textures().gbufferTranslucent);
		}, usages);
	}

	public static void setupHand(PipelineBuilder builder, Resources resources) {
		final var usages = new ObjectShaderUsage[] {
			new ObjectShaderUsage(ProgramUsage.HAND, "USAGE_HAND"),
			new ObjectShaderUsage(
				ProgramUsage.TRANSLUCENT_HAND,
				"USAGE_TRANSLUCENT_HAND"
			),
		};
		createObjectShaders((ProgramUsage usage) -> {
			return builder.object(usage, "program/object/hand", "Object")
				.writes("color", resources.textures().scene.front());
		}, usages);
	}

	public static void
	setupShadow(PipelineBuilder builder, Resources resources) {
		if (builder.settings().getBoolValue("SHADOW_ENABLED")) {
			if (builder.settings().getBoolValue("RSM_ENABLED")) {
				builder
					.object(
						ProgramUsage.SHADOW,
						"program/object/shadow_opaque_rsm",
						"Object"
					)
					.writes("data", resources.textures().shadowRsmData);
			} else {
				builder.object(
					ProgramUsage.SHADOW,
					"program/object/shadow_opaque",
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
				builder
					.object(
						usage,
						"program/object/shadow_translucent",
						"Object"
					)
					.writes("color", resources.textures().shadowColor);
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
