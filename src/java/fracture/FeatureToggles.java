package fracture;

import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import fracture.util.PipelineBuilder;

// Holds flags for whether certain features should be enabled.
public class FeatureToggles {
	public final boolean shadow;
	public final boolean rsm;
	public final boolean clouds;
	public final boolean roughSpecular;
	public final boolean vxrtData;

	public FeatureToggles(PipelineConfig pipeline, Dimension dimension) {
		shadow = pipeline.settings().getBoolValue("SHADOW_ENABLED")
			&& dimension.hasCelestialLight;

		rsm = pipeline.settings().getBoolValue("RSM_ENABLED")
			&& dimension.hasCelestialLight;

		clouds = pipeline.settings().getBoolValue("CLOUDS_ENABLED")
			&& dimension.hasClouds;

		roughSpecular
			= pipeline.settings().getBoolValue("LABPBR_SUPPORT_ENABLED")
			&& pipeline.settings().getBoolValue("REFLECTIONS_ENABLED");

		vxrtData = pipeline.settings().getBoolValue("REFERENCE_PT_ENABLED")
			|| pipeline.settings().getBoolValue("RESTIR_GI_ENABLED")
			|| pipeline.settings().getBoolValue("TEST_VXRT");
	}

	public void addGlobalExports(PipelineBuilder factory) {
		factory.exportBoolGlobally("TOGGLE_SHADOW", shadow);
		factory.exportBoolGlobally("TOGGLE_RSM", rsm);
		factory.exportBoolGlobally("TOGGLE_CLOUDS", clouds);
		factory.exportBoolGlobally("TOGGLE_ROUGH_SPECULAR", roughSpecular);
		factory.exportBoolGlobally("TOGGLE_VXRT_DATA", vxrtData);
	}
}
