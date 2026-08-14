public module math;

static const float EPS = 1e-6;
static const float E = exp(1.0);
static const float PI = acos(-1.0);
static const float TAU = 2.0 * PI;
static const float HALF_PI = 0.5 * PI;
static const float RCP_PI = 1.0 / PI;
static const float DEGREE = TAU / 360.0;
static const float GOLDEN_RATIO = 0.5 + 0.5 * sqrt(5.0);
static const float GOLDEN_ANGLE = TAU / GOLDEN_RATIO / GOLDEN_RATIO;

T max0<T>(T x)
	where T : IArithmetic { return max(T(0), x); }

T min1<T>(T x)
	where T : IArithmetic { return min(T(1), x); }

T min_of<T>(vector<T, 2> v)
	where T : IArithmetic { return min(v.x, v.y); }
T min_of<T>(vector<T, 3> v)
	where T : IArithmetic { return min(v.x, min(v.y, v.z)); }
T min_of<T>(vector<T, 4> v)
	where T : IArithmetic { return min(v.x, min(v.y, min(v.z, v.w))); }

T max_of<T>(vector<T, 2> v)
	where T : IArithmetic { return max(v.x, v.y); }
T max_of<T>(vector<T, 3> v)
	where T : IArithmetic { return max(v.x, max(v.y, v.z)); }
T max_of<T>(vector<T, 4> v)
	where T : IArithmetic { return max(v.x, max(v.y, max(v.z, v.w))); }

T pow2<T>(T x)
	where T : IArithmetic { return x * x; }
T pow3<T>(T x)
	where T : IArithmetic { return x * x * x; }
T pow4<T>(T x)
	where T : IArithmetic {
	x = x * x;
	return x * x;
}
T pow5<T>(T x)
	where T : IArithmetic {
	T x2 = x * x;
	return x2 * x2 * x;
}

float pow_3_over_2(float x) { return x * sqrt(x); }

float2 diagonal(float2x2 m) { return float2(m[0].x, m[1].y); }

float3 diagonal(float3x3 m) { return float3(m[0].x, m[1].y, m[2].z); }

float4 diagonal(float4x4 m) { return float4(m[0].x, m[1].y, m[2].z, m[3].w); }

float3 transform(float4x4 m, float3 pos) {
	return mul(float3x3(m), pos) + float3(m[0].w, m[1].w, m[2].w);
}

float4 project(float4x4 m, float3 pos) {
	return float4(m[0].x, m[1].y, m[2].z, m[3].z) * pos.xyzz
		+ float4(m[0].w, m[1].w, m[2].w, m[3].w);
}

float3 project_and_divide(float4x4 m, float3 pos) {
	float4 homogenous = project(m, pos);
	return homogenous.xyz / homogenous.w;
}

float3 project_ortho(float4x4 m, float3 pos) {
	return diagonal(m).xyz * pos + m[3].xyz;
}

// Faster alternative to acos
// Source:
// https://seblagarde.wordpress.com/2014/12/01/inverse-trigonometric-functions-gpu-optimization-for-amd-gcn-architecture/#more-3316
// Max relative error: 3.9 * 10^-4
// Max absolute error: 6.1 * 10^-4
// Polynomial degree: 2
float fast_acos(float x) {
	const float C0 = 1.57018;
	const float C1 = -0.201877;
	const float C2 = 0.0464619;

	float res = (C2 * abs(x) + C1) * abs(x) + C0; // p(x)
	res *= sqrt(1.0 - abs(x));

	return x >= 0 ? res : PI - res; // Undo range reduction.
}

float linstep(float min, float max, float x, ) {
	return saturate((x - min) / (max - min));
}

vector<float, N> linstep<uint N>(
	vector<float, N> min,
	vector<float, N> max,
	vector<float, N> x,
) {
	return saturate((x - min) / (max - min));
}

// Can be used similarly to sqrt() to shape a signal on [0, 1]
T dampen<T>(T x)
	where T : IArithmetic {
	x = min(max(x, T(0)), T(1));
	return x * (T(2) - x);
}

// Can be used similarly to pow() to shape a signal
//
// amount := lifting amount [-1.0, inf]
//
// amount = 0 -> identity
// amount < 0 -> increase signal contrast (power > 1)
// amount > 0 -> reduce signal contrast (power < 1)
T lift<T>(T x, T amount)
	where T : IArithmetic { return (x + x * amount) / (T(1) + x * amount); }

// Smoothing function used by smoothstep.
// Zero derivative at zero and one.
T cubic_smooth<T>(T x)
	where T : IArithmetic { return pow2(x) * (T(3) - T(2) * x); }

// Similar to the above, but even smoother with a zero second derivative at zero
// and one.
T quintic_smooth<T>(T x)
	where T : IArithmetic { return pow3(x) * (x * (x * T(6) - T(15)) + T(10)); }

T get_uv_from_unit_range<T>(T values, T res)
	where T : IArithmetic {
	return values * (T(1) - T(1) / res) + ((T(1) / T(2)) / res);
}

T get_unit_range_from_uv<T>(T uv, T res)
	where T : IArithmetic {
	return (uv - (T(1) / T(2)) / res) / (T(1) - T(1) / res);
}

struct Ray {
	float3 o;
	float3 d;

	float3 at(float t) { return o + d * t; }
}


