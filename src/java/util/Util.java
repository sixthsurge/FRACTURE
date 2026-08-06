package util;

import org.joml.Vector3d;
import org.joml.Vector3f;

public class Util {
	public static Vector3f vector3dToVector3f(Vector3d v) {
		return new Vector3f((float) v.x, (float) v.y, (float) v.z);
	}
}
