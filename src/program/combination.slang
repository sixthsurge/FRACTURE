import aperture;
import lib.post.tonemapping;

Texture2D tex_scene;

[shader("pixel")]
float4 main(float2 coord: SV_Position) {
	int2 icoord = int2(coord);

	float3 color = tex_scene[icoord].rgb;

	color = tonemap_hejl_burgess(color);
	// NB: do not need to apply sRGB EOTF as this is built into Hejl-Burgess.

	return float4(color, 1.0);
}


