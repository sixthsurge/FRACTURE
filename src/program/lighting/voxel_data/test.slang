import aperture;
import lib.lighting.celestial;
import lib.lighting.emission;
import lib.lighting.shadow;
import lib.lighting.vxrt.trace;
import lib.util.debug;
import lib.util.math;
import lib.util.space_conversion;
import settings;

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID) {
	if (!userSettings.DEBUG) {
		printf("'TEST_VXRT' mode requires DEBUG mode to be visible.");
	}

	float2 ncoord = (icoord + 0.5) / ap.game.screenSize;
	float3 dir_view = normalize(screen_to_view(float3(ncoord, 1.0)));
	float3 dir_world = mul(float3x3(ap.camera.viewInv), dir_view);

	float3 color = float3(0.0);
	float3 tint;
	if (let hit = vxrt.trace(Ray(ap.camera.position, dir_world), 64, tint)) {
		color = hit.material.albedo * tint;

		shadow.Result shadow_result = shadow.calculate_simple(
			hit.pos_world - ap.camera.position,
			hit.normal,
		);

		float3 bounce_radiance
			= calculate_celestial_light(
				  hit.material,
				  shadow_result,
				  hit.pos_world - ap.camera.position,
				  dir_world,
				  hit.normal,
				  hit.normal
			  )
			+ calculate_emission(hit.material.emission);
		if (ncoord.x < 0.5) {
			color = bounce_radiance;
		}
	}

	debug.show(icoord, color);
}


