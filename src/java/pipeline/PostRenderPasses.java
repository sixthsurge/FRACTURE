package pipeline;

import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import resources.Textures;

public class PostRenderPasses {
	public static void
	setup(PipelineConfig pipeline, Screen screen, Textures textures) {
		pipeline.stage(ProgramStage.POST_RENDER)
			.compute("specular", "program/specular", "main")
			.dispatch2D(
				Math.ceilDiv(screen.renderWidth(), 16),
				Math.ceilDiv(screen.renderHeight(), 16)
			)
			.overrideObject("tex_scene_write", textures.scene.back().name())
			.overrideObject("tex_scene", textures.scene.front().name());
		textures.scene.flip();

		setupExposure(pipeline, screen, textures);

		String nextPassInput = null;
		if (pipeline.settings().getBoolValue("TAA_ENABLED")) {
			pipeline.stage(ProgramStage.POST_RENDER)
				.compute("taa", "program/post/taa", "main")
				.dispatch2D(
					Math.ceilDiv(screen.windowWidth(), 16),
					Math.ceilDiv(screen.windowHeight(), 16)
				)
				.overrideObject("tex_scene", textures.scene.front().name());
			nextPassInput = textures.taaOutputCurrent.name();
		} else {
			nextPassInput = textures.scene.front().name();
		}

		setupBloom(pipeline, screen, textures, nextPassInput);

		pipeline.combinationPass("program/post/combination")
			.overrideObject("tex_input", nextPassInput)
			.overrideObject("tex_bloom", textures.bloom.front().name());
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
		String sourceTexture
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
			String srcTex
				= srcLod == 0 ? sourceTexture : textures.bloom.front().name();
			int destMipScale = Math.powExact(2, srcLod + 1);

			pipeline.stage(ProgramStage.POST_RENDER)
				.compute(
					"bloom/downsample " + srcLod,
					"program/post/bloom/downsample",
					"main"
				)
				.dispatch2D(
					Math.ceilDiv(screen.windowWidth(), 16 * destMipScale),
					Math.ceilDiv(screen.windowHeight(), 16 * destMipScale)
				)
				.overrideObject("dest", textures.bloom.back().name())
				.overrideObject("input", srcTex)
				.exportInt("INPUT_LOD", srcLod);
			textures.bloom.flip();
		}
		if ((tileCount & 1) == 0) {
			textures.bloom.flip();
		}

		// Blur

		final int workGroupSize = 64;

		for (int lod = 0; lod < tileCount; lod++) {
			// Read from sourceTexture for lod 0 (avoid initial copy)
			final var srcTex
				= lod == 0 ? sourceTexture : textures.bloom.front().name();
			final var mipScale = Math.powExact(2, lod);

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
				.overrideObject("input", srcTex)
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
		}

		// Upsampling
		// Final upsample from 1 to 0 is performed in the program where bloom is
		// applied (save unneeded write).

		for (int dstLod = tileCount - 2; dstLod >= 1; dstLod--) {
			// For the first tile, smaller input comes from back too.
			final var smallerInputTex = dstLod == tileCount - 2
				? textures.bloom.back()
				: textures.bloom.front();
			final var destMipScale = Math.powExact(2, dstLod);

			pipeline.stage(ProgramStage.POST_RENDER)
				.compute(
					"bloom/upsample " + dstLod,
					"program/post/bloom/upsample",
					"main"
				)
				.dispatch2D(
					Math.ceilDiv(screen.windowWidth(), 16 * destMipScale),
					Math.ceilDiv(screen.windowHeight(), 16 * destMipScale)
				)
				.overrideObject("dest", textures.bloom.back().name())
				.overrideObject("input_smaller", smallerInputTex.name())
				.overrideObject("input_bigger", textures.bloom.front().name())
				.exportInt("DST_LOD", dstLod);
			textures.bloom.flip();
		}
	}
}
