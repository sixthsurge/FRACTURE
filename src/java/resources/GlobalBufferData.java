package resources;
import dev.irisshaders.aperture.api.pipeline.FrameState;
import org.joml.Vector3d;
import org.joml.Vector3f;
import util.AtmosphereTransmittance;
import util.Util;

public record GlobalBufferData(
	Vector3f light_dir_world,
	Vector3f sun_dir_world,
	Vector3f moon_dir_world,
	Vector3f sun_radiosity,
	Vector3f moon_radiosity,
	Vector3f celestial_light_irradiance,
	float celestial_light_angular_radius
) {
	public static GlobalBufferData get(FrameState state) {
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
		// Color of sunlight in space, obtained from AM0 solar irradiance
		// spectrum from
		// https://www.nrel.gov/grid/solar-resource/spectra-astm-e490.html using
		// the CIE (2006) 2-deg LMS cone fundamentals
		final var sunRadiosity = new Vector3f(1.051f, 0.985f, 0.940f);

		final var moonRadiosity = new Vector3f(sunRadiosity).mul(0.01f);

		final boolean isNight = lightDirWorld.dot(moonDirWorld) < 0.0;

		final var celestialLightRadiosity
			= isNight ? sunRadiosity : moonRadiosity;

		var celestialLightIrradiance
			= new Vector3f(celestialLightRadiosity)
				  .mul(Util.vector3dToVector3f(
					  AtmosphereTransmittance.calculateTransmittance(
						  AtmosphereTransmittance.EARTH_PARAMS,
						  new Vector3d(
							  0.0,
							  AtmosphereTransmittance.EARTH_PARAMS
									  .planetRadius()
								  + 1.0,
							  0.0
						  ),
						  new Vector3d(state.uniforms()
										   .getFloat3("ap.celestial.position")
										   .normalize())
					  )
				  ));

		float celestialLightAngularRadius
			= state.uniforms().getFloat("ap.celestial.angle") > 0.5f
			? state.settings().getFloatValue("SUN_ANGULAR_RADIUS")
				* ((float) Math.TAU / 360.0f)
			: state.settings().getFloatValue("MOON_ANGULAR_RADIUS")
				* ((float) Math.TAU / 360.0f);

		return new GlobalBufferData(
			lightDirWorld,
			sunDirWorld,
			moonDirWorld,
			sunRadiosity,
			moonRadiosity,
			celestialLightIrradiance,
			celestialLightAngularRadius
		);
	}
}
