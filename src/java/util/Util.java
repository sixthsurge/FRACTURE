package util;

import org.joml.Vector2f;
import org.joml.Vector3d;
import org.joml.Vector3f;

public class Util {
	public static Vector3f vector3dToVector3f(Vector3d v) {
		return new Vector3f((float) v.x, (float) v.y, (float) v.z);
	}

	public static double frac(double f) { return f - Math.floor(f); }

	// http://extremelearning.com.au/unreasonable-effectiveness-of-quasirandom-sequences/
	public static Vector2f r2(int i) {
		return new Vector2f(
			(float) frac(1.3247179572 * (double) i + 0.5),
			(float) frac(1.7548776662 * (double) i + 0.5)
		);
	}
}
