package util;

import org.joml.Vector2d;
import org.joml.Vector3d;

public class AtmosphereTransmittance {
	// Port of the atmosphere transmittance calculation to the CPU side, for
	// precalculating the sunlight colour on the ground to pass to the shaders.

	public record AtmosphereParameters(
		double planetRadius,
		double thickness,
		Vector2d scaleHeights,
		Vector3d rayleighCoeff,
		Vector3d mieCoeff,
		Vector3d ozoneCoeff
	) {}

	public static final AtmosphereParameters EARTH_PARAMS
		= new AtmosphereParameters(
			6371e3,
			110e3,
			new Vector2d(8.4e3, 1.25e3),
			new Vector3d(5.8, 13.6, 33.1).mul(1e-6),
			new Vector3d(4.4).mul(1e-6),
			new Vector3d(0.65, 1.88, 0.085).mul(1e-6)
		);

	private static Vector2d
	intersectSphere(Vector3d rayOrigin, Vector3d rayDir, double sphereRadius) {
		double b = rayOrigin.dot(rayDir);
		double discriminant
			= b * b - rayOrigin.dot(rayOrigin) + sphereRadius * sphereRadius;

		if (discriminant < 0.0) {
			return new Vector2d(-1.0);
		}

		discriminant = Math.sqrt(discriminant);
		return new Vector2d(-b).add(new Vector2d(-discriminant, discriminant));
	}

	private static Vector3d
	calculateAtmosphereDensity(AtmosphereParameters params, double r) {
		double altitude = r - params.planetRadius;

		double rlh = Math.exp(-altitude / params.scaleHeights.x);
		double mie = Math.exp(-altitude / params.scaleHeights.y);

		// Source for ozone density curve: Jessie in shaderLABS.
		double altitudeKm = altitude * 1e-3f;
		double o1 = 12.5 * Math.exp((1.0 / 8.0) * (0.0 - altitudeKm));
		double o2 = 30.0
			* Math.exp(
				(1.0 / 80.0) * (18.0 - altitudeKm) * (altitudeKm - 18.0)
			);
		double o3 = 75.0
			* Math.exp(
				(1.0 / 50.0) * (23.5 - altitudeKm) * (altitudeKm - 23.5)
			);
		double o4 = 50.0
			* Math.exp(
				(1.0 / 150.0) * (30.0 - altitudeKm) * (altitudeKm - 30.0)
			);
		double ozone = 7.428e-3 * (o1 + o2 + o3 + o4);

		return new Vector3d(rlh, mie, ozone);
	}

	public static Vector3d calculateTransmittance(
		AtmosphereParameters params,
		Vector3d rayOrigin,
		Vector3d rayDir
	) {
		final int stepCount = 32;

		double planetDist
			= intersectSphere(rayOrigin, rayDir, params.planetRadius).x;
		if (planetDist >= 0.0) return new Vector3d(0.0);
		double rayLength
			= intersectSphere(
				  rayOrigin,
				  rayDir,
				  params.planetRadius + params.thickness
			)
				  .y;

		Vector3d rayStep = new Vector3d(rayDir).mul(rayLength / (stepCount - 1));
		Vector3d rayPos = rayOrigin;

		// Integrating extinction using trapezium rule.
		Vector3d airmass = new Vector3d(0.0);
		for (int i = 0; i < stepCount; ++i) {
			double w = (i == 0 || i == stepCount - 1) ? 0.5 : 1.0;
			airmass.add(
				calculateAtmosphereDensity(params, rayPos.length()).mul(w)
			);
			rayPos.add(rayStep);
		}
		airmass.mul(rayLength / (double) (stepCount - 1));

		Vector3d extinction = new Vector3d(params.rayleighCoeff).mul(airmass.x)
								  .add(new Vector3d(params.mieCoeff).mul(airmass.y))
								  .add(new Vector3d(params.ozoneCoeff).mul(airmass.z));

		return new Vector3d(
			Math.exp(-extinction.x),
			Math.exp(-extinction.y),
			Math.exp(-extinction.z)
		);
	}
}
