package fracture;

import dev.irisshaders.aperture.api.objects.ResourceId;
import fracture.util.PipelineBuilder;

public class Dimension {
	public final boolean hasAtmosphere;
	public final boolean hasCelestialLight;
	public final boolean hasClouds;

	public Dimension(ResourceId id) {
		String namespace = id.namespace();
		String path = id.path();

		if (namespace == "minecraft" && path == "overworld") {
			hasAtmosphere = true;
			hasCelestialLight = true;
			hasClouds = true;
		} else {
			hasAtmosphere = true;
			hasCelestialLight = false;
			hasClouds = false;
		}
	}

	public void addGlobalExports(PipelineBuilder builder) {
		builder.exportBoolGlobally("DIM_HAS_ATMOSPHERE", hasAtmosphere);
		builder.exportBoolGlobally(
			"DIM_HAS_CELESTIAL_LIGHT",
			hasCelestialLight
		);
		builder.exportBoolGlobally("DIM_HAS_CLOUDS", hasClouds);
	}
}
