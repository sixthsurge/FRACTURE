package fracture;
import dev.irisshaders.aperture.api.pipeline.FrameState;
import fracture.util.Util;
import org.joml.Vector2f;
import org.joml.Vector3f;

public record GlobalBufferData(
	Vector2f taa_jitter,
	float world_age,
	float sun_angle,
	Vector3f light_dir_world,
	Vector3f sun_dir_world,
	Vector3f moon_dir_world,
	Vector3f light_dir_view,
	Vector3f sun_dir_view,
	Vector3f moon_dir_view,
	Vector3f sun_radiosity,
	Vector3f moon_radiosity,
	Vector3f celestial_light_irradiance,
	Vector3f ambient_irradiance,
	float celestial_light_angular_radius
) {
	public static GlobalBufferData get(FrameState state, Dimension dimension) {
		final var frameCounter
			= state.uniforms().getInt("ap.timing.frameCounter");
		final var renderSize = state.uniforms().getInt2("ap.game.renderSize");
		final var cameraView = state.uniforms().getFloat4x4("ap.camera.view");

		final var worldAge
			= ((float) (state.uniforms().getInt("ap.world.day") % 128)
				   * 24000.0f
			   + (float) state.uniforms().getInt("ap.world.time"))
			/ 20.0f;

		final var taaJitter = state.settings().getBoolValue("TAA_ENABLED")
			? (Util.r2(frameCounter).sub(new Vector2f(0.5f)))
				  .div(new Vector2f(renderSize.x, renderSize.y))
			: new Vector2f(0.0f);

		final var lightDirWorld
			= state.uniforms().getFloat3("ap.celestial.position").normalize();
		final var sunDirWorld = state.uniforms()
									.getFloat3("ap.celestial.sunPosition")
									.normalize();
		final var moonDirWorld
			= state.uniforms()
				  .getFloat3("ap.celestial.sunPosition")
				  .negate()
				  .normalize();

		final var isDay = lightDirWorld.dot(moonDirWorld) < 0.0;
		final var sunAngle = state.uniforms().getFloat("ap.celestial.angle")
			+ (isDay ? 0.0f : 0.5f);

		final var sunRadiosity = dimension.getSunRadiosity(state);
		final var moonRadiosity = dimension.getMoonRadiosity(state);

		final var celestialLightIrradiance
			= dimension.getCelestialLightIrradiance(state);
		final var ambientIrradiance = dimension.getAmbientIrradiance(state);
		final var celestialLightAngularRadius
			= dimension.getCelestialLightAngularRadius(state);

		return new GlobalBufferData(
			taaJitter,
			worldAge,
			sunAngle,
			lightDirWorld,
			sunDirWorld,
			moonDirWorld,
			cameraView.transformDirection(new Vector3f(lightDirWorld)),
			cameraView.transformDirection(new Vector3f(sunDirWorld)),
			cameraView.transformDirection(new Vector3f(moonDirWorld)),
			sunRadiosity,
			moonRadiosity,
			celestialLightIrradiance,
			ambientIrradiance,
			celestialLightAngularRadius
		);
	}
}
