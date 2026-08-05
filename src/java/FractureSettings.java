import dev.irisshaders.aperture.api.PackSettings;
import dev.irisshaders.aperture.api.settings.OptionType;
import dev.irisshaders.aperture.api.settings.SettingsManager;
import dev.irisshaders.aperture.api.settings.SettingsScreen;

public class FractureSettings implements PackSettings {
	@Override
	public void createSettings(SettingsManager manager, SettingsScreen screen) {
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

		final var screenExposure = screen.child("exposure");
		screenExposure
			.option("AUTO_EXPOSURE_ENABLED", OptionType.boolType(true), false);
		screenExposure.option(
			"EXPOSURE_TARGET",
			OptionType.floatType(0.0f, 1.0f, 0.01f, 0.5f),
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
	}
}
