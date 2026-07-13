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


