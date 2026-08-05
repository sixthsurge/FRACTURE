import dev.irisshaders.aperture.api.*;
import dev.irisshaders.aperture.api.objects.*;
import dev.irisshaders.aperture.api.pipeline.*;
import dev.irisshaders.aperture.api.renderer.*;
import dev.irisshaders.aperture.api.settings.SettingsManager;
import org.joml.Vector3f;
import util.Flipper;

public class Fracture implements ShaderPack {
	public record GlobalBufferData(
		Vector3f light_dir_world,
		Vector3f sun_dir_world,
		Vector3f moon_dir_world
	) {}

	MappedBuffer<GlobalBufferData> globalBuffer;

	@Override
	public void configurePipeline(Screen screen, PipelineConfig pipeline) {
		final var sceneTexA
			= pipeline.texture2D("tex_scene_a", TextureFormat.RG11B10_UFLOAT)
				  .renderSize()
				  .create();
		final var sceneTexB
			= pipeline.texture2D("tex_scene_b", TextureFormat.RG11B10_UFLOAT)
				  .renderSize()
				  .create();
		final var sceneTex = new Flipper<>(sceneTexA, sceneTexB);

		final var packedGbufferDataTex
			= pipeline
				  .texture2D("tex_packed_gbuffer_data", TextureFormat.RG32_UINT)
				  .renderSize()
				  .create();

		final var atmosphereTransmittanceTex
			= pipeline
				  .texture2D(
					  "tex_atmosphere_transmittance_lut",
					  TextureFormat.RG11B10_UFLOAT
				  )
				  .size(256, 64)
				  .create();

		final var atmosphereMultiscatterTex
			= pipeline
				  .texture2D(
					  "tex_atmosphere_multiscatter_lut",
					  TextureFormat.RGBA16_SFLOAT
				  )
				  .size(32, 32)
				  .create();

		final var atmosphereSkyViewTex
			= pipeline
				  .texture2D(
					  "tex_atmosphere_sky_view",
					  TextureFormat.RG11B10_UFLOAT
				  )
				  .size(512, 256)
				  .create();

		pipeline.texture2D("tex_exposure_histogram", TextureFormat.R32_UINT)
			.size(256, 1)
			.create();

		globalBuffer
			= pipeline.mappedBuffer("buf_global", GlobalBufferData.class);

		pipeline.buffer("buf_exposure", 12);

		pipeline
			.object(ProgramUsage.BASIC, "program/object/basic", "BasicObject")
			.writes("packed_gbuffer_data", packedGbufferDataTex);

		if (pipeline.settings().getBoolValue("SHADOW_ENABLED")) {
			pipeline.object(
				ProgramUsage.SHADOW,
				"program/object/shadow",
				"ShadowObject"
			);
		}

		pipeline.stage(ProgramStage.PRE_RENDER)
			.composite(
				"atmosphere/transmittance_lut",
				"program/atmosphere",
				"transmittance_lut_main"
			)
			.writes("transmittance", atmosphereTransmittanceTex);

		pipeline.stage(ProgramStage.PRE_RENDER)
			.composite(
				"atmosphere/multiscatter_lut",
				"program/atmosphere",
				"multiscatter_lut_main"
			)
			.writes("multiscatter_energy", atmosphereMultiscatterTex);

		pipeline.stage(ProgramStage.PRE_RENDER)
			.composite(
				"atmosphere/sky_view",
				"program/atmosphere",
				"sky_view_main"
			)
			.writes("sky_radiance", atmosphereSkyViewTex);

		pipeline.stage(ProgramStage.PRE_TRANSLUCENT)
			.composite("deferred_shading", "program/deferred_shading", "main")
			.writes("radiance", sceneTex.back());

		// Must have scene data in front and back for translucent passes to read
		// and write sceneTex.
		pipeline.stage(ProgramStage.PRE_TRANSLUCENT)
			.copy(sceneTex.back(), sceneTex.front());

		pipeline
			.object(
				ProgramUsage.TRANSLUCENT,
				"program/object/translucent",
				"TranslucentObject"
			)
			.writes("color", sceneTex.back())
			.overrideObject("tex_scene", sceneTex.front().name());
		sceneTex.flip();

		pipeline.stage(ProgramStage.POST_RENDER)
			.compute(
				"exposure/clear_histogram",
				"program/exposure/clear_histogram",
				"main"
			)
			.dispatch1D(1);

		pipeline.stage(ProgramStage.POST_RENDER)
			.compute(
				"exposure/build_histogram",
				"program/exposure/build_histogram",
				"main"
			)
			.dispatch2D(
				Math.ceilDiv(screen.renderWidth(), 32),
				Math.ceilDiv(screen.renderHeight(), 32)
			)
			.overrideObject("tex_scene", sceneTex.front().name());

		pipeline.stage(ProgramStage.POST_RENDER)
			.compute(
				"exposure/calculate_exposure",
				"program/exposure/calculate_exposure",
				"main"
			)
			.dispatch1D(1);

		pipeline.combinationPass("program/combination")
			.overrideObject("tex_scene", sceneTex.front().name());
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
		globalBuffer.write(new GlobalBufferData(
			state.uniforms().getFloat3("ap.celestial.position").normalize(),
			state.uniforms().getFloat3("ap.celestial.sunPosition").normalize(),
			state.uniforms()
				.getFloat3("ap.celestial.sunPosition")
				.negate()
				.normalize()
		));
	}
}
