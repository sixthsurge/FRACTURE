package fracture.pipeline;

import dev.irisshaders.aperture.api.pipeline.ProgramStage;
import fracture.Resources;
import fracture.Textures;
import fracture.util.PipelineBuilder;
import org.joml.Vector4f;

public class PreRender {
	public static void setup(PipelineBuilder builder, Resources resources) {
		builder.setStage(ProgramStage.PRE_RENDER);

		if (builder.settings().getBoolValue("DEBUG")) {
			builder.pipeline()
				.stage(ProgramStage.PRE_RENDER)
				.clearTo(new Vector4f(0.0f), resources.textures().debug);
		}

		if (resources.toggles().vxrtData && false) {
			builder.compute3d(
				"vxrt/clear_face_data",
				"program/lighting/voxel_data/clear_face_data",
				"main",
				builder.settings().getIntValue("VOXEL_RT_VOLUME_SIZE_X") * 6,
				builder.settings().getIntValue("VOXEL_RT_VOLUME_SIZE_Y"),
				builder.settings().getIntValue("VOXEL_RT_VOLUME_SIZE_Z"),
				8,
				8,
				4
			);
		}

		setupAtmosphere(builder, resources);

		builder.compute("gen_sky_sh", "program/lighting/gen_sky_sh", "main")
			.dispatch1D(1);
	}

	private static void
	setupAtmosphere(PipelineBuilder builder, Resources resources) {
		builder.compute2d(
			"atmosphere/gen_transmittance_lut",
			"program/volumetrics/atmosphere/gen_transmittance_lut",
			"main",
			Textures.ATMOSPHERE_TRANSMITTANCE_LUT_WIDTH,
			Textures.ATMOSPHERE_TRANSMITTANCE_LUT_HEIGHT,
			16,
			16
		);

		builder.compute2d(
			"atmosphere/gen_multiscatter_lut",
			"program/volumetrics/atmosphere/gen_multiscatter_lut",
			"main",
			Textures.ATMOSPHERE_MULTISCATTER_LUT_WIDTH,
			Textures.ATMOSPHERE_MULTISCATTER_LUT_HEIGHT,
			8,
			8
		);

		builder.compute2d(
			"atmosphere/gen_sky_view_lut",
			"program/volumetrics/atmosphere/gen_sky_view_lut",
			"main",
			Textures.ATMOSPHERE_SKY_VIEW_LUT_WIDTH,
			Textures.ATMOSPHERE_SKY_VIEW_LUT_HEIGHT,
			16,
			16
		);

		if (builder.settings().getBoolValue("ATMOSPHERE_AP_LUT_ENABLED")) {
			builder.compute3d(
				"atmosphere/gen_aerial_perspective_lut",
				"program/volumetrics/atmosphere/gen_aerial_perspective_lut",
				"main",
				Textures.ATMOSPHERE_AP_LUT_WIDTH,
				Textures.ATMOSPHERE_AP_LUT_HEIGHT,
				Textures.ATMOSPHERE_AP_LUT_DEPTH,
				4,
				4,
				4
			);
		}
	}
}
