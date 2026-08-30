package fracture;

import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import fracture.util.PipelineBuilder;

// Holds flags for whether certain features should be enabled.
public class FeatureToggles {
	public final boolean vxrtData;

	public FeatureToggles(PipelineConfig pipeline) {
		vxrtData = pipeline.settings().getBoolValue("PTGI_ENABLED")
			|| pipeline.settings().getBoolValue("TEST_VXRT");
	}

	public void addGlobalExports(PipelineBuilder factory) {
		factory.exportBoolGlobally("TOGGLE_VXRT_DATA", vxrtData);
	}
}
