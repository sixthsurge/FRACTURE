public module space_conversion;

import aperture;

import lib.util.math;

float3
screen_to_view(float3 pos_screen, float4x4 proj_inv = ap.camera.projectionInv) {
	pos_screen.xy = pos_screen.xy * 2.0 - 1.0;
	return project_and_divide(proj_inv, pos_screen);
}

float screen_to_view_depth(
	float depth,
	float4x4 proj_inv = ap.camera.projectionInv,
) {
	float2 zw = depth * proj_inv[2].zw + proj_inv[3].zw;
	return -zw.x / zw.y;
}

float3 view_to_screen(float3 pos_view, float4x4 proj = ap.camera.projection) {
	float3 pos_screen = project_and_divide(proj, pos_view);
	pos_screen.xy = pos_screen.xy * 2.0 - 1.0;
	return pos_screen;
}

float view_to_screen_depth(float depth, float4x4 proj = ap.camera.projection) {
	float2 zw = -depth * proj[2].zw + proj[3].zw;
	return zw.x / zw.y;
}

float3 view_to_scene(float3 pos_view, float4x4 view_inv = ap.camera.viewInv) {
	return transform(view_inv, pos_view);
}

float3 scene_to_view(float3 pos_scene, float4x4 view = ap.camera.view) {
	return transform(view, pos_scene);
}


