package fracture;

import dev.irisshaders.aperture.api.objects.ResourceId;
import dev.irisshaders.aperture.api.pipeline.FrameState;
import fracture.util.AtmosphereTransmittance;
import fracture.util.PipelineBuilder;
import fracture.util.Util;
import org.joml.Vector3d;
import org.joml.Vector3f;

public interface Dimension {
	public boolean hasAtmosphere();
	public boolean hasCelestialLight();
	public boolean hasClouds();

	public default Vector3f getAmbientIrradiance(FrameState state) {
		return new Vector3f(0.0f);
	};

	public default Vector3f getSunRadiosity(FrameState state) {
		return new Vector3f(0.0f);
	}

	public default Vector3f getMoonRadiosity(FrameState state) {
		return new Vector3f(0.0f);
	}

	public default Vector3f getCelestialLightIrradiance(FrameState state) {
		return new Vector3f(0.0f);
	};

	public default float getCelestialLightAngularRadius(FrameState state) {
		return 0.0f;
	}

	public static Dimension getDimension(ResourceId dimension) {
		if (dimension.namespace() == "minecraft"
			&& dimension.path() == "overworld") {
			return new Overworld();
		} else {
			return new Generic();
		}
	}

	public static void
	addGlobalExports(Dimension dimension, PipelineBuilder builder) {
		builder.exportBoolGlobally(
			"DIM_HAS_ATMOSPHERE",
			dimension.hasAtmosphere()
		);
		builder.exportBoolGlobally(
			"DIM_HAS_CELESTIAL_LIGHT",
			dimension.hasCelestialLight()
		);
		builder.exportBoolGlobally("DIM_HAS_CLOUDS", dimension.hasClouds());
	}

	public class Generic implements Dimension {
		@Override
		public boolean hasAtmosphere() {
			return true;
		}

		@Override
		public boolean hasCelestialLight() {
			return false;
		}

		@Override
		public boolean hasClouds() {
			return false;
		}

		@Override
		public Vector3f getAmbientIrradiance(FrameState state) {
			return Util.srgbEotfInv(
				Util.swizzleXyz(state.uniforms().getFloat4("ap.world.fogColor"))
			);
		}
	}

	public class Overworld implements Dimension {
		@Override
		public boolean hasAtmosphere() {
			return true;
		}

		@Override
		public boolean hasCelestialLight() {
			return true;
		}

		@Override
		public boolean hasClouds() {
			return true;
		}

		@Override
		public Vector3f getSunRadiosity(FrameState state) {
			// Color of sunlight in space, obtained from AM0 solar irradiance
			// spectrum from
			// https://www.nrel.gov/grid/solar-resource/spectra-astm-e490.html
			// using the CIE (2006) 2-deg LMS cone fundamentals
			return new Vector3f(1.051f, 0.985f, 0.940f);
		}

		@Override
		public Vector3f getMoonRadiosity(FrameState state) {
			return getSunRadiosity(state).mul(
				new Vector3f(0.001f, 0.004f, 0.003f)
			);
		}

		@Override
		public Vector3f getAmbientIrradiance(FrameState state) {
			return new Vector3f(0.0005f).mul(
				1.0f - state.uniforms().getFloat2("ap.camera.brightness").y()
			);
		}

		@Override
		public Vector3f getCelestialLightIrradiance(FrameState state) {
			final var lightDirWorld = state.uniforms()
										  .getFloat3("ap.celestial.position")
										  .normalize();
			final var moonDirWorld
				= state.uniforms()
					  .getFloat3("ap.celestial.sunPosition")
					  .negate()
					  .normalize();
			final var isDay = lightDirWorld.dot(moonDirWorld) < 0.0;

			final var celestialLightRadiosity
				= isDay ? getSunRadiosity(state) : getMoonRadiosity(state);

			return celestialLightRadiosity.mul(Util.vector3dToVector3f(
				AtmosphereTransmittance.calculateTransmittance(
					AtmosphereTransmittance.EARTH_PARAMS,
					new Vector3d(
						0.0,
						AtmosphereTransmittance.EARTH_PARAMS.planetRadius()
							+ 1.0,
						0.0
					),
					new Vector3d(state.uniforms()
									 .getFloat3("ap.celestial.position")
									 .normalize())
				)
			));
		}

		@Override
		public float getCelestialLightAngularRadius(FrameState state) {
			final var lightDirWorld = state.uniforms()
										  .getFloat3("ap.celestial.position")
										  .normalize();
			final var moonDirWorld
				= state.uniforms()
					  .getFloat3("ap.celestial.sunPosition")
					  .negate()
					  .normalize();
			final var isDay = lightDirWorld.dot(moonDirWorld) < 0.0;

			return isDay ? state.settings().getFloatValue("SUN_ANGULAR_RADIUS")
					* ((float) Math.TAU / 360.0f)
						 : state.settings().getFloatValue("MOON_ANGULAR_RADIUS")
					* ((float) Math.TAU / 360.0f);
		}
	}
}
