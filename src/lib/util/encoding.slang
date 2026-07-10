public module encoding;

vector<float, N> sign_nonzero<uint N>(vector<float, N> x) {
	return select(x >= 0, vector<float, N>(1.0), vector<float, N>(-1.0), );
}

// Octahedral unit vector encoding.
// Source: http://jcgt.org/published/0003/02/01/
float2 encode_octahedral(float3 v) {
	// Project the sphere onto the octahedron, and then onto the xy plane.
	float2 p = v.xy * (1.0 / (abs(v.x) + abs(v.y) + abs(v.z)));

	// Reflect the folds of the lower hemisphere over the diagonals.
	p = v.z <= 0.0 ? ((1.0 - abs(p.yx)) * sign_nonzero(p)) : p;

	// Scale to [0, 1].
	return 0.5 * p + 0.5;
}

float3 decode_octahedral(float2 e) {
	// Scale to [-1, 1].
	e = 2.0 * e - 1.0;

	// Extract Z component.
	float3 v = float3(e.xy, 1.0 - abs(e.x) - abs(e.y));

	// Reflect the folds of the lower hemisphere over the diagonals.
	if (v.z < 0) {
		v.xy = (1.0 - abs(v.yx)) * sign_nonzero(v.xy);
	}

	return normalize(v);
}


