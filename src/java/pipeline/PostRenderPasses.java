package pipeline;

import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.objects.Texture2D;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import resources.Textures;

public class PostRenderPasses {
	public static void
	setup(PipelineConfig pipeline, Screen screen, Textures textures) {
		pipeline.stage(ProgramStage.POST_RENDER)
			.composite("temp_fog", "program/temp_fog", "main")
			.overrideObject("tex_scene", textures.scene.front().name())
			.writes("radiance", textures.scene.back());
		textures.scene.flip();

		setupExposure(pipeline, screen, textures);
		setupBloom(pipeline, screen, textures, textures.scene.front());

		pipeline.combinationPass("program/post/combination")
			.overrideObject("tex_scene", textures.scene.front().name());
	}

	private static void
	setupExposure(PipelineConfig pipeline, Screen screen, Textures textures) {
		if (!pipeline.settings().getBoolValue("AUTO_EXPOSURE_ENABLED")) {
			return;
		}

		pipeline.stage(ProgramStage.POST_RENDER)
			.compute(
				"exposure/clear_histogram",
				"program/post/exposure/clear_histogram",
				"main"
			)
			.dispatch1D(1);

		pipeline.stage(ProgramStage.POST_RENDER)
			.compute(
				"exposure/build_histogram",
				"program/post/exposure/build_histogram",
				"main"
			)
			.dispatch2D(
				Math.ceilDiv(screen.renderWidth(), 32),
				Math.ceilDiv(screen.renderHeight(), 32)
			)
			.overrideObject("tex_scene", textures.scene.front().name());

		pipeline.stage(ProgramStage.POST_RENDER)
			.compute(
				"exposure/calculate_exposure",
				"program/post/exposure/calculate_exposure",
				"main"
			)
			.dispatch1D(1);
	}

	private static void setupBloom(
		PipelineConfig pipeline,
		Screen screen,
		Textures textures,
		Texture2D sourceTexture
	) {
		if (!pipeline.settings().getBoolValue("BLOOM_ENABLED")) {
			return;
		}

		final var maxLod = (int) Math.ceil(
			Math.log(Math.max(screen.windowWidth(), screen.windowHeight()))
			/ Math.log(2.0)
		);
		final var tileCount = Math.min(
			pipeline.settings().getIntValue("BLOOM_TILE_COUNT"),
			maxLod
		);

		// Downsampling

		for (int srcLod = 0; srcLod < tileCount - 1; srcLod++) {
			// Read from sourceTexture for lod 0 (avoid initial copy)
			Texture2D srcTex
				= srcLod == 0 ? sourceTexture : textures.bloom.front();

			pipeline.stage(ProgramStage.POST_RENDER)
				.composite(
					"bloom/downsample " + srcLod,
					"program/post/bloom/downsample",
					"main"
				)
				.writes("downsampled", textures.bloom.front(), srcLod + 1)
				.overrideObject("input", srcTex.name())
				.overrideObject("dest", textures.bloom.front().name())
				.exportInt("INPUT_LOD", srcLod);
		}

		// Blur

		final int workGroupSize = 64;

		for (int lod = 0; lod < tileCount; lod++) {
			// Read from sourceTexture for lod 0 (avoid initial copy)
			Texture2D srcTex
				= lod == 0 ? sourceTexture : textures.bloom.front();
			int mipScale = Math.powExact(2, lod);

			pipeline.stage(ProgramStage.POST_RENDER)
				.compute(
					"bloom/blur horizontal " + lod,
					"program/post/bloom/blur",
					"horizontal_main"
				)
				.dispatch2D(
					Math.ceilDiv(
						screen.windowWidth(),
						workGroupSize * mipScale
					),
					Math.ceilDiv(screen.windowHeight(), mipScale)
				)
				.overrideObject("input", srcTex.name())
				.overrideObject("dest", textures.bloom.back().name())
				.exportInt("LOD", lod);
			textures.bloom.flip();

			pipeline.stage(ProgramStage.POST_RENDER)
				.compute(
					"bloom/blur vertical " + lod,
					"program/post/bloom/blur",
					"vertical_main"
				)
				.dispatch2D(
					Math.ceilDiv(screen.windowWidth(), mipScale),
					Math.ceilDiv(
						screen.windowHeight(),
						workGroupSize * mipScale
					)
				)
				.overrideObject("input", textures.bloom.front().name())
				.overrideObject("dest", textures.bloom.back().name())
				.exportInt("LOD", lod);
			textures.bloom.flip();
		}

		// Upsampling
		// Final upsample from 1 to 0 is performed in the program where bloom is
		// applied (save unneeded write).

		for (int dstLod = tileCount - 2; dstLod >= 1; dstLod--) {
			pipeline.stage(ProgramStage.POST_RENDER)
				.composite(
					"bloom/upsample " + dstLod,
					"program/post/bloom/upsample",
					"main"
				)
				.writes("upsampled", textures.bloom.back(), dstLod)
				.exportInt("DST_LOD", dstLod)
				.overrideObject("input", textures.bloom.front().name());

			textures.bloom.flip();
		}
	}
}
