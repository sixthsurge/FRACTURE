package fracture.pipeline;

import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import fracture.Resources;
import fracture.util.PipelineBuilder;

public class PostRender {
	public static void setup(PipelineBuilder builder, Resources resources) {
		builder.setStage(ProgramStage.POST_RENDER);

		setupExposure(builder, resources);

		String nextPassInput = null;
		if (builder.settings().getBoolValue("TAA_ENABLED")) {
			builder
				.windowSizedCompute("taa", "program/post/taa", "main", 16, 16)
				.overrideObject(
					"tex_scene",
					resources.textures().scene.front().name()
				);
			nextPassInput = resources.textures().taaOutputCurrent.name();
		} else {
			nextPassInput = resources.textures().scene.front().name();
		}

		setupBloom(builder, resources, nextPassInput);

		if (builder.settings().getBoolValue("TEST_VXRT")) {
			builder.windowSizedCompute(
				"test_vxrt",
				"program/lighting/voxel_data/test",
				"main",
				16,
				16
			);
		}

		builder.pipeline()
			.combinationPass("program/post/combination")
			.overrideObject("tex_input", nextPassInput)
			.overrideObject(
				"tex_bloom",
				resources.textures().bloom.front().name()
			);
	}

	private static void
	setupExposure(PipelineBuilder builder, Resources resources) {
		if (!builder.settings().getBoolValue("AUTO_EXPOSURE_ENABLED")) {
			return;
		}

		builder
			.compute(
				"exposure/clear_histogram",
				"program/post/exposure/clear_histogram",
				"main"
			)
			.dispatch1D(1);

		builder
			.compute2d(
				"exposure/build_histogram",
				"program/post/exposure/build_histogram",
				"main",
				Math.ceilDiv(builder.screen().renderWidth(), 2),
				Math.ceilDiv(builder.screen().renderHeight(), 2),
				16,
				16
			)
			.overrideObject(
				"tex_scene",
				resources.textures().scene.front().name()
			);

		builder
			.compute(
				"exposure/calculate_exposure",
				"program/post/exposure/calculate_exposure",
				"main"
			)
			.dispatch1D(1);
	}

	private static void setupBloom(
		PipelineBuilder builder,
		Resources resources,
		String sourceTexture
	) {
		if (!builder.settings().getBoolValue("BLOOM_ENABLED")) {
			return;
		}

		final var maxLod = (int) Math.ceil(
			Math.log(Math.max(
				builder.screen().windowWidth(),
				builder.screen().windowHeight()
			))
			/ Math.log(2.0)
		);
		final var tileCount = Math.min(
			builder.settings().getIntValue("BLOOM_TILE_COUNT"),
			maxLod
		);

		// Downsampling

		for (int srcLod = 0; srcLod < tileCount - 1; srcLod++) {
			// Read from sourceTexture for lod 0 (avoid initial copy)
			String srcTex = srcLod == 0
				? sourceTexture
				: resources.textures().bloom.front().name();
			int destMipScale = Math.powExact(2, srcLod + 1);

			builder
				.compute2d(
					"bloom/downsample " + srcLod,
					"program/post/bloom/downsample",
					"main",
					Math.ceilDiv(builder.screen().windowWidth(), destMipScale),
					Math.ceilDiv(builder.screen().windowHeight(), destMipScale),
					16,
					16
				)
				.overrideObject(
					"dest",
					resources.textures().bloom.back().name()
				)
				.overrideObject("input", srcTex)
				.exportInt("INPUT_LOD", srcLod);
			resources.textures().bloom.flip();
		}
		if ((tileCount & 1) == 0) {
			resources.textures().bloom.flip();
		}

		// Blur

		final int workGroupSize = 64;

		for (int lod = 0; lod < tileCount; lod++) {
			// Read from sourceTexture for lod 0 (avoid initial copy)
			final var srcTex = lod == 0
				? sourceTexture
				: resources.textures().bloom.front().name();
			final var mipScale = Math.powExact(2, lod);

			builder
				.compute2d(
					"bloom/blur horizontal " + lod,
					"program/post/bloom/blur",
					"horizontal_main",
					Math.ceilDiv(builder.screen().windowWidth(), mipScale),
					Math.ceilDiv(builder.screen().windowHeight(), mipScale),
					workGroupSize,
					1
				)
				.overrideObject("input", srcTex)
				.overrideObject(
					"dest",
					resources.textures().bloom.back().name()
				)
				.exportInt("LOD", lod);
			resources.textures().bloom.flip();

			builder
				.compute2d(
					"bloom/blur vertical " + lod,
					"program/post/bloom/blur",
					"vertical_main",
					Math.ceilDiv(builder.screen().windowWidth(), mipScale),
					Math.ceilDiv(builder.screen().windowHeight(), mipScale),
					1,
					workGroupSize
				)
				.overrideObject(
					"input",
					resources.textures().bloom.front().name()
				)
				.overrideObject(
					"dest",
					resources.textures().bloom.back().name()
				)
				.exportInt("LOD", lod);
		}

		// Upsampling
		// Final upsample from 1 to 0 is performed in the program where bloom is
		// applied (save unneeded write).

		for (int dstLod = tileCount - 2; dstLod >= 1; dstLod--) {
			// For the first tile, smaller input comes from back too.
			final var smallerInputTex = dstLod == tileCount - 2
				? resources.textures().bloom.back()
				: resources.textures().bloom.front();
			final var destMipScale = Math.powExact(2, dstLod);

			builder
				.compute2d(
					"bloom/upsample " + dstLod,
					"program/post/bloom/upsample",
					"main",
					Math.ceilDiv(builder.screen().windowWidth(), destMipScale),
					Math.ceilDiv(builder.screen().windowHeight(), destMipScale),
					16,
					16
				)
				.overrideObject(
					"dest",
					resources.textures().bloom.back().name()
				)
				.overrideObject("input_smaller", smallerInputTex.name())
				.overrideObject(
					"input_bigger",
					resources.textures().bloom.front().name()
				)
				.exportInt("DST_LOD", dstLod);
			resources.textures().bloom.flip();
		}
	}
}
