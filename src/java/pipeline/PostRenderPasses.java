package pipeline;

import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import resources.Textures;
import util.ProgramFactory;

public class PostRenderPasses {
	public static void setup(
		PipelineConfig pipeline,
		Screen screen,
		ProgramFactory factory,
		Textures textures
	) {
		factory.setCurrentStage(pipeline.stage(ProgramStage.POST_RENDER));

		setupExposure(pipeline, screen, factory, textures);

		String nextPassInput = null;
		if (pipeline.settings().getBoolValue("TAA_ENABLED")) {
			factory
				.windowSizedCompute("taa", "program/post/taa", "main", 16, 16)
				.overrideObject("tex_scene", textures.scene.front().name());
			nextPassInput = textures.taaOutputCurrent.name();
		} else {
			nextPassInput = textures.scene.front().name();
		}

		setupBloom(pipeline, screen, factory, textures, nextPassInput);

		if (pipeline.settings().getBoolValue("TEST_VXRT")) {
			factory.windowSizedCompute(
				"test_vxrt",
				"program/lighting/voxel_data/test",
				"main",
				16,
				16
			);
		}

		pipeline.combinationPass("program/post/combination")
			.overrideObject("tex_input", nextPassInput)
			.overrideObject("tex_bloom", textures.bloom.front().name());
	}

	private static void setupExposure(
		PipelineConfig pipeline,
		Screen screen,
		ProgramFactory factory,
		Textures textures
	) {
		if (!pipeline.settings().getBoolValue("AUTO_EXPOSURE_ENABLED")) {
			return;
		}

		factory
			.compute(
				"exposure/clear_histogram",
				"program/post/exposure/clear_histogram",
				"main"
			)
			.dispatch1D(1);

		factory
			.compute2d(
				"exposure/build_histogram",
				"program/post/exposure/build_histogram",
				"main",
				Math.ceilDiv(screen.renderWidth(), 2),
				Math.ceilDiv(screen.renderHeight(), 2),
				16,
				16
			)
			.overrideObject("tex_scene", textures.scene.front().name());

		factory
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
		ProgramFactory factory,
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

			factory
				.compute2d(
					"bloom/downsample " + srcLod,
					"program/post/bloom/downsample",
					"main",
					Math.ceilDiv(screen.windowWidth(), destMipScale),
					Math.ceilDiv(screen.windowHeight(), destMipScale),
					16,
					16
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

			factory
				.compute2d(
					"bloom/blur horizontal " + lod,
					"program/post/bloom/blur",
					"horizontal_main",
					Math.ceilDiv(screen.windowWidth(), mipScale),
					Math.ceilDiv(screen.windowHeight(), mipScale),
					workGroupSize,
					1
				)
				.overrideObject("input", srcTex)
				.overrideObject("dest", textures.bloom.back().name())
				.exportInt("LOD", lod);
			textures.bloom.flip();

			factory
				.compute2d(
					"bloom/blur vertical " + lod,
					"program/post/bloom/blur",
					"vertical_main",
					Math.ceilDiv(screen.windowWidth(), mipScale),
					Math.ceilDiv(screen.windowHeight(), mipScale),
					1,
					workGroupSize
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

			factory
				.compute2d(
					"bloom/upsample " + dstLod,
					"program/post/bloom/upsample",
					"main",
					Math.ceilDiv(screen.windowWidth(), destMipScale),
					Math.ceilDiv(screen.windowHeight(), destMipScale),
					16,
					16
				)
				.overrideObject("dest", textures.bloom.back().name())
				.overrideObject("input_smaller", smallerInputTex.name())
				.overrideObject("input_bigger", textures.bloom.front().name())
				.exportInt("DST_LOD", dstLod);
			textures.bloom.flip();
		}
	}
}
