import dev.irisshaders.aperture.api.PackSettings;
import dev.irisshaders.aperture.api.settings.OptionType;
import dev.irisshaders.aperture.api.settings.SettingsManager;
import dev.irisshaders.aperture.api.settings.SettingsScreen;

public class FractureSettings implements PackSettings {
	@Override
	public void createSettings(SettingsManager manager, SettingsScreen screen) {
		screen.option(
			"LABPBR_SUPPORT_ENABLED",
			OptionType.boolType(false),
			false
		);

		final var screenLighting = screen.child("lighting");

		final var screenShadow = screenLighting.child("shadow");
		screenShadow.option("SHADOW_ENABLED", OptionType.boolType(true), false);
		screenShadow.option(
			"SHADOW_CASCADE_COUNT",
			OptionType.intType(1, 16, 1, 4),
			false
		);
		screenShadow.option(
			"SHADOW_RESOLUTION",
			OptionType.intType(512, 4096, 512, 2048),
			false
		);
		screenShadow.option(
			"SHADOW_DISTANCE",
			OptionType.intType(16, 1024, 16, 160),
			false
		);

		final var screenGtao = screenLighting.child("gtao");
		screenGtao.option("GTAO_ENABLED", OptionType.boolType(true), false);
		screenGtao
			.option("GTAO_SLICE_COUNT", OptionType.intType(1, 64, 1, 2), false);
		screenGtao.option(
			"GTAO_HORIZON_STEP_COUNT",
			OptionType.intType(1, 64, 1, 4),
			false
		);
		screenGtao.option(
			"GTAO_RADIUS",
			OptionType.floatType(0.25f, 16.0f, 0.25f, 4.0f),
			true
		);

		final var screenRsm = screenLighting.child("rsm");
		screenRsm.option("RSM_ENABLED", OptionType.boolType(true), false);
		screenRsm
			.option("RSM_STEP_COUNT", OptionType.intType(1, 64, 1, 12), false);
		screenRsm.option(
			"RSM_RADIUS",
			OptionType.floatType(0.25f, 16.0f, 0.25f, 4.0f),
			true
		);
		screenRsm.option(
			"RSM_DISTANCE_FALLOFF",
			OptionType.floatType(0.01f, 1.0f, 0.1f, 0.25f),
			true
		);

		final var screenAtmospherics = screen.child("atmospherics");

		final var screenFog = screenAtmospherics.child("fog");
		screenFog.option(
			"FOG_VOLUME_SIZE_X",
			OptionType.intType(32, 512, 16, 240),
			false
		);
		screenFog.option(
			"FOG_VOLUME_SIZE_Y",
			OptionType.intType(32, 512, 16, 128),
			false
		);
		screenFog.option(
			"FOG_VOLUME_SIZE_Z",
			OptionType.intType(16, 128, 16, 64),
			false
		);
		screenFog.option(
			"ATMOSPHERE_AP_LUT_ENABLED",
			OptionType.boolType(false),
			false
		);

		final var screenSky = screenAtmospherics.child("sky");
		screenSky.option(
			"SUN_ANGULAR_RADIUS",
			OptionType.floatType(0.1f, 10.0f, 0.05f, 0.5f),
			false
		);
		screenSky.option(
			"MOON_ANGULAR_RADIUS",
			OptionType.floatType(0.1f, 10.0f, 0.05f, 8.0f),
			false
		);

		final var screenPost = screen.child("post");

		final var screenTaa = screenPost.child("taa");
		screenTaa.option("TAA_ENABLED", OptionType.boolType(true), false);

		final var screenBloom = screenPost.child("bloom");
		screenBloom.option("BLOOM_ENABLED", OptionType.boolType(true), false);
		screenBloom.option(
			"BLOOM_INTENSITY",
			OptionType.floatType(0.0f, 1.0f, 0.01f, 0.10f),
			true
		);
		screenBloom
			.option("BLOOM_TILE_COUNT", OptionType.intType(1, 12, 1, 7), false);

		final var screenExposure = screenPost.child("exposure");
		screenExposure
			.option("AUTO_EXPOSURE_ENABLED", OptionType.boolType(true), false);
		screenExposure.option(
			"EXPOSURE_TARGET_A",
			OptionType.floatType(0.0f, 1.0f, 0.01f, 0.25f),
			true
		);
		screenExposure.option(
			"EXPOSURE_TARGET_B",
			OptionType.floatType(0.0f, 1.0f, 0.01f, 0.90f),
			true
		);
		screenExposure.option(
			"MANUAL_EXPOSURE_VALUE",
			OptionType.floatType(0.0f, 1024.0f, 1.0f, 8.0f),
			true
		);
		screenExposure.option(
			"DISPLAY_LUMINANCE_HISTOGRAM",
			OptionType.boolType(false),
			false
		);

		final var screenAgx = screenPost.child("agx");
		screenAgx.option(
			"AGX_OFFSET_R",
			OptionType.floatType(-1.0f, 1.0f, 0.01f, 0.0f),
			true
		);
		screenAgx.option(
			"AGX_OFFSET_G",
			OptionType.floatType(-1.0f, 1.0f, 0.01f, 0.0f),
			true
		);
		screenAgx.option(
			"AGX_OFFSET_B",
			OptionType.floatType(-1.0f, 1.0f, 0.01f, 0.0f),
			true
		);
		screenAgx.option(
			"AGX_SLOPE_R",
			OptionType.floatType(0.0f, 2.0f, 0.01f, 1.0f),
			true
		);
		screenAgx.option(
			"AGX_SLOPE_G",
			OptionType.floatType(0.0f, 2.0f, 0.01f, 1.0f),
			true
		);
		screenAgx.option(
			"AGX_SLOPE_B",
			OptionType.floatType(0.0f, 2.0f, 0.01f, 1.0f),
			true
		);
		screenAgx.option(
			"AGX_POWER_R",
			OptionType.floatType(0.0f, 2.0f, 0.01f, 1.1f),
			true
		);
		screenAgx.option(
			"AGX_POWER_G",
			OptionType.floatType(0.0f, 2.0f, 0.01f, 1.1f),
			true
		);
		screenAgx.option(
			"AGX_POWER_B",
			OptionType.floatType(0.0f, 2.0f, 0.01f, 1.1f),
			true
		);
		screenAgx.option(
			"AGX_SAT",
			OptionType.floatType(0.0f, 2.0f, 0.01f, 1.1f),
			true
		);
	}
}
