public module space_conversion;

import aperture;

import lib.util.math;

enum HandleJitter {
	True,
	False,
}

float3 screen_to_view(
	float3 pos_screen,
	HandleJitter handle_jitter,
	float4x4 proj_inv = ap.camera.projection,
) {
	float3 pos_ndc = pos_screen * 2.0 - 1.0;
	// FIXME When TAA is implemented, subtract jitter here.
	return project_and_divide(proj_inv, pos_ndc);
}

float screen_to_view_depth(
	float depth,
	float4x4 proj_inv = ap.camera.projection,
) {
	depth = depth * 2.0 - 1.0;
	float2 zw = depth * proj_inv[2].zw + proj_inv[3].zw;
	return -zw.x / zw.y;
}

float3 view_to_screen(float4x4 proj, float3 pos_view, bool handle_jitter) {
	float3 pos_ndc = project_and_divide(proj, pos_view);
	// FIXME When TAA is implemented, subtract jitter here.
	return pos_ndc * 0.5 + 0.5;
}

float3 view_to_screen(float3 pos_view, bool handle_jitter) {
	return view_to_screen(ap.camera.projection, pos_view, handle_jitter);
}

float view_to_screen_depth(float depth, float4x4 proj = ap.camera.projection) {
	float2 zw = -depth * proj[2].zw + proj[3].zw;
	return (zw.x / zw.y) * 0.5 + 0.5;
}

float3 view_to_scene(float3 pos_view, float4x4 view_inv = ap.camera.viewInv) {
	return transform(view_inv, pos_view);
}

float3 scene_to_view(float3 pos_scene, float4x4 view = ap.camera.view) {
	return transform(view, pos_scene);
}


