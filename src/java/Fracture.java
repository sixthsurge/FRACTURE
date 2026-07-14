import dev.irisshaders.aperture.api.*;
import dev.irisshaders.aperture.api.objects.*;
import dev.irisshaders.aperture.api.pipeline.*;
import dev.irisshaders.aperture.api.renderer.*;
import dev.irisshaders.aperture.api.settings.SettingsManager;
import org.joml.Vector3f;
import util.Flipper;

public class Fracture implements ShaderPack {
	class Settings {
		boolean shadowEnabled;
		int shadowCascadeCount;
		int shadowResolution;
		int shadowDistance;

		Settings(SettingsManager settings) {
			shadowEnabled = settings.getBoolValue("SHADOW_ENABLED");
			shadowCascadeCount = settings.getIntValue("SHADOW_CASCADE_COUNT");
			shadowResolution = settings.getIntValue("SHADOW_RESOLUTION");
			shadowDistance = settings.getIntValue("SHADOW_DISTANCE");
		}
	}

	public record GlobalBufferData(Vector3f light_dir_world) {}

	MappedBuffer<GlobalBufferData> globalBuffer;

	int divideRoundingUp(int num, int denom) {
		return (num + denom - 1) / denom;
	}

	@Override
	public void configurePipeline(Screen screen, PipelineConfig pipeline) {
		final var settings = new Settings(pipeline.settings());

		final var sceneTex
			= pipeline.texture2D("tex_scene", TextureFormat.RG11B10_UFLOAT)
				  .renderSize()
				  .create();

		final var packedGbufferDataTex
			= pipeline
				  .texture2D("tex_packed_gbuffer_data", TextureFormat.RG32_UINT)
				  .renderSize()
				  .create();

		final var hiZDepthTexWidth = (screen.renderWidth() + 1) / 2;
		final var hiZDepthTexHeight = (screen.renderHeight() + 1) / 2;
		final var hiZDepthTex
			= pipeline.texture2D("tex_depth_hiz", TextureFormat.R16_SFLOAT)
				  .size(hiZDepthTexWidth, hiZDepthTexHeight)
				  .usesMipmaps()
				  .create();

		globalBuffer
			= pipeline.mappedBuffer("buf_global", GlobalBufferData.class);

		pipeline
			.object(ProgramUsage.BASIC, "program/object/basic", "BasicObject")
			.writes("packed_gbuffer_data", packedGbufferDataTex);

		pipeline
			.object(
				ProgramUsage.TRANSLUCENT,
				"program/object/translucent",
				"TranslucentObject"
			)
			.writes("color", sceneTex);

		if (settings.shadowEnabled) {
			pipeline.object(
				ProgramUsage.SHADOW,
				"program/object/shadow",
				"ShadowObject"
			);
		}

		final var hiZMipCount = (int) Math.ceil(
			Math.log(Math.min(hiZDepthTexWidth, hiZDepthTexHeight))
			/ Math.log(2)
		);
		for (int dstLod = -1; dstLod < hiZMipCount; dstLod++) {
			pipeline.stage(ProgramStage.PRE_TRANSLUCENT)
				.compute(
					"hiz_downsample_" + dstLod,
					"program/hiz_downsample",
					"main"
				)
				.dispatch2D(
					divideRoundingUp(hiZDepthTexWidth, 8),
					divideRoundingUp(hiZDepthTexHeight, 8)
				)
				.exportInt("LOD_DST", dstLod);
		}

		pipeline.stage(ProgramStage.PRE_TRANSLUCENT)
			.composite("deferred_shading", "program/deferred_shading", "main")
			.writes("radiance", sceneTex);

		pipeline.combinationPass("program/combination");
	}

	@Override
	public void configureRenderer(RendererConfig rendererConfig) {
		final var settings = new Settings(rendererConfig.getSettings());

		rendererConfig.setShadowCascades(settings.shadowCascadeCount);
		rendererConfig.setShadowDistance(settings.shadowDistance);
		rendererConfig.setShadowResolution(settings.shadowResolution);
		rendererConfig.setSunPathRotation(30);
	}

	@Override
	public void onNewFrame(FrameState state) {
		globalBuffer.write(new GlobalBufferData(
			state.uniforms().getFloat3("ap.celestial.position").normalize()
		));
	}
}
