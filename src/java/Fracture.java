import dev.irisshaders.aperture.api.ShaderPack;
import dev.irisshaders.aperture.api.objects.AddressMode;
import dev.irisshaders.aperture.api.objects.FilterMode;
import dev.irisshaders.aperture.api.objects.IBlockState;
import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.FrameState;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import dev.irisshaders.aperture.api.renderer.RendererConfig;
import org.joml.Vector4f;
import pipeline.ObjectShaders;
import pipeline.PostRenderPasses;
import pipeline.PostShadowPasses;
import pipeline.PreOverlayPasses;
import pipeline.PreRenderPasses;
import pipeline.PreTranslucentPasses;
import resources.Buffers;
import resources.Textures;
import util.ProgramFactory;

public class Fracture implements ShaderPack {
	Textures textures;
	Buffers buffers;

	@Override
	public void configurePipeline(Screen screen, PipelineConfig pipeline) {
		ProgramFactory factory = new ProgramFactory(pipeline, screen);

		textures = new Textures(pipeline, screen);
		buffers = new Buffers(pipeline);

		// Zero spdGlobalAtomic for FidelityFX SPD.
		pipeline.stage(ProgramStage.SCREEN_SETUP)
			.compute(
				"zero_spd_global_atomic",
				"program/lighting/hiz_downsample",
				"zero_spd_global_atomic"
			)
			.dispatch1D(1);

		PreRenderPasses.setup(pipeline, screen, factory, textures);
		ObjectShaders.setupShadow(pipeline, factory, textures);
		PostShadowPasses.setup(pipeline, screen, factory, textures);
		ObjectShaders.setupOpaque(pipeline, factory, textures);
		PreTranslucentPasses.setup(pipeline, screen, factory, textures);
		ObjectShaders.setupTranslucent(pipeline, factory, textures);
		PreOverlayPasses.setup(pipeline, screen, factory, textures);
		ObjectShaders.setupHand(pipeline, factory, textures);
		PostRenderPasses.setup(pipeline, screen, factory, textures);

		pipeline.sampler("sampler_linear_repeat")
			.addressMode(AddressMode.REPEAT)
			.magFilter(FilterMode.LINEAR)
			.minFilter(FilterMode.LINEAR)
			.create();
	}

	@Override
	public void configureRenderer(RendererConfig rendererConfig) {
		rendererConfig.setShadowCascades(
			rendererConfig.getSettings().getIntValue("SHADOW_CASCADE_COUNT")
		);
		rendererConfig.setShadowDistance(
			rendererConfig.getSettings().getIntValue("SHADOW_DISTANCE")
		);
		rendererConfig.setShadowResolution(
			rendererConfig.getSettings().getIntValue("SHADOW_RESOLUTION")
		);
		rendererConfig.setSunPathRotation(30);
	}

	@Override
	public void onNewFrame(FrameState state) {
		buffers.update(state);
		textures.updateReferences(state);
	}

	@Override
	public int setBlockId(IBlockState block) {
		final var id = block.getBlockId();
		if (id.path() == "water") {
			return 1;
		}
		if (block.hasTag("replaceable_by_trees") || block.hasTag("saplings")
			|| block.hasTag("flowers")) {
			return 2;
		}
		if (block.hasTag("leaves")) {
			return 3;
		}
		return 0;
	}
}
