public module color;

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


