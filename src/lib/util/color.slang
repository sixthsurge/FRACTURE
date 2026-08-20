public module color;

import lib.util.math;

static const float3 LUMINANCE_WEIGHTS_REC709 = float3(0.2126, 0.7152, 0.0722);
static const float3 PRIMARY_WAVELENGTHS_REC709 = float3(660.0, 550.0, 440.0);

// Approx. convert linear -> sRGB.
// Source: Jodie in shaderLABS #snippets.
float3 srgb_eotf(float3 linear) {
	return 1.14374 * (-0.126893 * linear + sqrt(linear));
}

// Approx. convert sRGB -> linear.
// Source:
// https://chilliant.blogspot.com/2012/08/srgb-approximations-for-hlsl.html
float3 srgb_eotf_inv(float3 srgb) {
	return srgb * (srgb * (srgb * 0.305306011 + 0.682171111) + 0.012522878);
}

// Source:
// https://en.wikipedia.org/wiki/YCoCg#Conversion_with_the_RGB_color_model
float3 rgb_to_ycocg(float3 rgb) {
	const float3x3 CM
		= float3x3(0.25, 0.5, 0.25, 0.5, 0.0, -0.5, -0.25, 0.5, -0.25);
	return mul(CM, rgb);
}

float3 ycocg_to_rgb(float3 ycocg) {
	float tmp = ycocg.x - ycocg.z;
	return float3(tmp + ycocg.y, ycocg.x + ycocg.z, tmp - ycocg.y);
}

// Calculate the colour of a blackbody emitter from its temperature according to
// Planck's law. Source:
// https://github.com/Jessie-LC/open-source-utility-code/blob/main/advanced/blackbody.glsl
float3 blackbody(float temperature) {
	const float3 LAMBDA = PRIMARY_WAVELENGTHS_REC709;
	const float3 LAMBDA2 = LAMBDA * LAMBDA;
	const float3 LAMBDA5 = LAMBDA2 * LAMBDA2 * LAMBDA;

	const float H = 6.63e-16; // Planck constant
	const float K = 1.38e-5; // Boltzmann constant
	const float C = 3.0e17; // Speed of light

	const float3 A = LAMBDA5 / (2.0 * H * C * C);
	const float3 B = (H * C) / (K * LAMBDA);
	float3 d = exp(B / temperature);

	float3 rgb = A * d - A;
	return min_of(rgb) / rgb;
}


