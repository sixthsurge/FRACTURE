import dev.irisshaders.aperture.api.*;
import dev.irisshaders.aperture.api.objects.*;
import dev.irisshaders.aperture.api.pipeline.*;
import dev.irisshaders.aperture.api.renderer.*;
import pipeline.ObjectShaders;
import pipeline.PostRenderPasses;
import pipeline.PreRenderPasses;
import pipeline.PreTranslucentPasses;
import resources.Buffers;
import resources.Textures;

public class Fracture implements ShaderPack {
	Textures textures;
	Buffers buffers;

	@Override
	public void configurePipeline(Screen screen, PipelineConfig pipeline) {
		textures = new Textures(pipeline);
		buffers = new Buffers(pipeline);

		ObjectShaders.setupShadow(pipeline, textures);
		PreRenderPasses.setup(pipeline, screen, textures);
		ObjectShaders.setupOpaque(pipeline, textures);
		PreTranslucentPasses.setup(pipeline, screen, textures);
		ObjectShaders.setupTranslucent(pipeline, textures);
		PostRenderPasses.setup(pipeline, screen, textures);
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
	}
}
