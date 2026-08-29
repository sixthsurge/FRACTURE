package resources;

import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import util.ProgramFactory;

// Holds flags for whether certain features should be enabled.
public record FeatureToggles(boolean vxrtData) {
	public static FeatureToggles get(PipelineConfig pipeline) {
		final var vxrtData = pipeline.settings().getBoolValue("PTGI_ENABLED")
			|| pipeline.settings().getBoolValue("TEST_VXRT");

		return new FeatureToggles(vxrtData);
	}

	public void addGlobalExports(ProgramFactory factory) {
		factory.exportBoolGlobally("TOGGLE_VXRT_DATA", vxrtData);
	}
}
