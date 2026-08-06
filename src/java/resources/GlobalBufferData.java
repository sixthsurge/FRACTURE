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
		var lightDirWorld
			= state.uniforms().getFloat3("ap.celestial.position").normalize();
		var sunDirWorld = state.uniforms()
							  .getFloat3("ap.celestial.sunPosition")
							  .normalize();
		var moonDirWorld = state.uniforms()
							   .getFloat3("ap.celestial.sunPosition")
							   .negate()
							   .normalize();
		var sunRadiosity = new Vector3f(1.0f);
		var moonRadiosity = new Vector3f(0.01f);

		final var celestialLightRadiosity
			= state.uniforms().getFloat("ap.celestial.angle") < 0.5
			? sunRadiosity
			: moonRadiosity;

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

		float celestialLightAngularRadius = state.uniforms().getFloat("ap.celestial.angle") > 0.5f ? 0.004f : 0.008f;

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
