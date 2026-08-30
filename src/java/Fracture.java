import dev.irisshaders.aperture.api.ShaderPack;
import dev.irisshaders.aperture.api.objects.AddressMode;
import dev.irisshaders.aperture.api.objects.FilterMode;
import dev.irisshaders.aperture.api.objects.IBlockState;
import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.FrameState;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.renderer.RendererConfig;
import fracture.Buffers;
import fracture.FeatureToggles;
import fracture.Resources;
import fracture.Textures;
import fracture.pipeline.ObjectShaders;
import fracture.pipeline.PostRender;
import fracture.pipeline.PostShadow;
import fracture.pipeline.PreOverlay;
import fracture.pipeline.PreRender;
import fracture.pipeline.PreTranslucent;
import fracture.pipeline.ScreenSetup;
import fracture.util.BlockMapping;
import fracture.util.PipelineBuilder;

public class Fracture implements ShaderPack {
	private Resources resources;
	private BlockMapping blockMapping;

	@Override
	public void configurePipeline(Screen screen, PipelineConfig pipeline) {
		blockMapping = new BlockMapping();
		setupBlockMapping(blockMapping);

		setupSamplers(pipeline);

		final var toggles = new FeatureToggles(pipeline);
		final var textures = new Textures(pipeline, screen, toggles);
		final var buffers = new Buffers(pipeline);

		final var builder = new PipelineBuilder(pipeline, screen);
		toggles.addGlobalExports(builder);
		blockMapping.addGlobalExports(builder);

		resources = new Resources(textures, buffers, toggles);

		ScreenSetup.setup(builder, resources);
		PreRender.setup(builder, resources);
		ObjectShaders.setupShadow(builder, resources);
		PostShadow.setup(builder, resources);
		ObjectShaders.setupOpaque(builder, resources);
		PreTranslucent.setup(builder, resources);
		ObjectShaders.setupTranslucent(builder, resources);
		PreOverlay.setup(builder, resources);
		ObjectShaders.setupHand(builder, resources);
		PostRender.setup(builder, resources);
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
		resources.buffers().update(state);
		resources.textures().updateReferences(state);
	}

	@Override
	public int setBlockId(IBlockState block) {
		return blockMapping.getBlockId(block);
	}

	private void setupBlockMapping(BlockMapping blockMapping) {
		blockMapping.material("MAT_WATER").id("minecraft:water");

		blockMapping.material("MAT_PLANTS")
			.tag("minecraft:replaceable_by_trees")
			.tag("minecraft:saplings")
			.tag("minecraft:flowers");

		blockMapping.material("MAT_LEAVES").tag("minecraft:leaves");
	}

	private void setupSamplers(PipelineConfig pipeline) {
		pipeline.sampler("sampler_linear_repeat")
			.addressMode(AddressMode.REPEAT)
			.magFilter(FilterMode.LINEAR)
			.minFilter(FilterMode.LINEAR)
			.create();
	}
}
