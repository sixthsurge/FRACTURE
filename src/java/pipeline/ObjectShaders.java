package pipeline;

import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramUsage;
import resources.Textures;

public class ObjectShaders {
	public static void setupOpaque(PipelineConfig pipeline, Textures textures) {
		pipeline
			.object(ProgramUsage.BASIC, "program/object/basic", "BasicObject")
			.writes("packed_gbuffer_data", textures.packedGbufferData);

		pipeline
			.object(ProgramUsage.TERRAIN_SOLID, "program/object/terrain", "TerrainObject")
			.writes("packed_gbuffer_data", textures.packedGbufferData);
	}

	public static void
	setupTranslucent(PipelineConfig pipeline, Textures textures) {
		pipeline
			.object(
				ProgramUsage.TRANSLUCENT,
				"program/object/translucent",
				"TranslucentObject"
			)
			.writes("color", textures.scene.back())
			.overrideObject("tex_scene", textures.scene.front().name());
		textures.scene.flip();
	}

	public static void setupShadow(PipelineConfig pipeline, Textures textures) {
		if (pipeline.settings().getBoolValue("SHADOW_ENABLED")) {
			pipeline.object(
				ProgramUsage.SHADOW,
				"program/object/shadow",
				"ShadowObject"
			);
		}
	}
}
