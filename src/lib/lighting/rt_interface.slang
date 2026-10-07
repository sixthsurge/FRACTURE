module rt_interface;

import aperture;
import lib.surface.material;
import lib.util.color;
import lib.util.math;
import rt_pipeline;
import settings;

Texture2D<float4> blockAtlasS;

public struct RayHit {
	public Material material;
	public float3 pos_scene;
	public float3 normal;
	public float opacity;
}

public interface IRayTracer {
	public Optional<RayHit> trace(Ray ray);
}

public struct HardwareRayTracer : IRayTracer {
	public Optional<RayHit> trace(Ray ray) {
		var query = HWRT.startQuery(
			ray.o,
			ray.d,
			0.001,
			max(ap.world.renderDistance, 1.0),
			HWRT.HitType.TERRAIN | HWRT.HitType.ENTITY,
			HWRT.RTFlags.NONE
		);
		while (query.proceed()) {
			let candidate = query.getCandidate();
			let hit = HWRT.decodeHit(candidate);
			let albedo
				= hit.albedo().sampleTexture(hit.getUV()) * hit.getColor();

			if (albedo.a > 0.1) {
				query.acceptCandidate();
			}
		}

		if (!query.hasHit()) {
			return none;
		}

		let hit_type = query.getCandidate().getHitType();
		let hit = HWRT.decodeHit(query.getHit());
		let pos_scene = hit.getPos();
		let normal_world = hit.getNormal();
		let uv = hit.getUV();
		let albedo = hit.albedo().sampleTexture(uv) * hit.getColor();
		var material = Material.get(srgb_eotf_inv(albedo.rgb), 0);

		if (userSettings.LABPBR_SUPPORT_ENABLED
			&& hit_type == HWRT.HitType.TERRAIN) {
			let specular_map = blockAtlasS.sampleNearest(uv);
			material.apply_specular_map(specular_map);
		}

		return RayHit(material, pos_scene, normal_world, albedo.a);
	}
}


