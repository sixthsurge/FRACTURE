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

		final var screenShadow = screen.child("shadow");
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

		final var screenFog = screen.child("fog");
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

		final var screenSky = screen.child("sky");
		screenSky.option(
			"SUN_ANGULAR_RADIUS",
			OptionType.floatType(0.1f, 10.0f, 0.05f, 0.5f),
			false
		);
		screenSky.option(
			"MOON_ANGULAR_RADIUS",
			OptionType.floatType(0.1f, 10.0f, 0.05f, 2.5f),
			false
		);

		final var screenBloom = screen.child("bloom");
		screenBloom.option("BLOOM_ENABLED", OptionType.boolType(true), false);
		screenBloom.option(
			"BLOOM_INTENSITY",
			OptionType.floatType(0.0f, 1.0f, 0.01f, 0.10f),
			true
		);
		screenBloom
			.option("BLOOM_TILE_COUNT", OptionType.intType(1, 12, 1, 7), false);

		final var screenExposure = screen.child("exposure");
		screenExposure
			.option("AUTO_EXPOSURE_ENABLED", OptionType.boolType(true), false);
		screenExposure.option(
			"EXPOSURE_TARGET_A",
			OptionType.floatType(0.0f, 1.0f, 0.01f, 0.25f),
			true
		);
		screenExposure.option(
			"EXPOSURE_TARGET_B",
			OptionType.floatType(0.0f, 1.0f, 0.01f, 0.75f),
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

		final var screenAgx = screen.child("agx");
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
