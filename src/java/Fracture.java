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

	public record GlobalBufferData(Vector3f light_dir_view) {}

	MappedBuffer<GlobalBufferData> globalBuffer;

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

		globalBuffer
			= pipeline.mappedBuffer("buf_global", GlobalBufferData.class);

		pipeline
			.object(ProgramUsage.BASIC, "program/object/basic", "BasicObject")
			.writes("packed_gbuffer_data", packedGbufferDataTex);

		if (settings.shadowEnabled) {
			pipeline.object(
				ProgramUsage.SHADOW,
				"program/object/shadow",
				"ShadowObject"
			);
		}

		pipeline.stage(ProgramStage.PRE_TRANSLUCENT)
			.composite(
				"deferred_shading",
				"program/pre_translucent/deferred_shading",
				"main"
			)
			.writes("radiance", sceneTex)
			.exportBool("SHADOW_ENABLED", settings.shadowEnabled)
			.exportInt("CASCADE_COUNT", settings.shadowCascadeCount);

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
