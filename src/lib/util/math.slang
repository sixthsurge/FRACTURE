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

vector<float, N> max0<uint N>(vector<float, N> x) { return max(0.0, x); }

vector<float, N> min1<uint N>(vector<float, N> x) { return min(1.0, x); }

T pow2<T>(T x)
	where T : IArithmetic { return x * x; }
T pow3<T>(T x)
	where T : IArithmetic { return x * x * x; }

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

vector<float, N> linstep<uint N>(
	vector<float, N> min,
	vector<float, N> max,
	vector<float, N> x,
) {
	return saturate((x - min) / (max - min));
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


