import dev.irisshaders.aperture.api.*;
import dev.irisshaders.aperture.api.objects.*;
import dev.irisshaders.aperture.api.pipeline.*;
import dev.irisshaders.aperture.api.renderer.*;
import util.Flipper;

public class Fracture implements ShaderPack {
    @Override
    public void configurePipeline(Screen screen, PipelineConfig pipeline) {
        final var sceneTex 
            = pipeline
                .texture2D("tex_scene", TextureFormat.RG11B10_UFLOAT)
                .renderSize()
                .create();

        final var packedGbufferDataTex 
            = pipeline
                .texture2D("tex_packed_gbuffer_data", TextureFormat.RG32_UINT)
                .renderSize()
                .create();

        pipeline.object(ProgramUsage.BASIC, "program/object/basic", "BasicObject")
            .writes("packed_gbuffer_data", packedGbufferDataTex);

        pipeline.stage(ProgramStage.PRE_RENDER)
            .composite(
                "deferred_shading", 
                "program/pre_translucent/deferred_shading", 
                "main"
            ).writes("radiance", sceneTex) ;

        pipeline.combinationPass("program/combination");
    }

    @Override
    public void configureRenderer(RendererConfig rendererConfig) {
        
    }
}