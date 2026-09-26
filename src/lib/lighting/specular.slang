module specular;

import aperture;
import lib.atmospherics.atmosphere;
import lib.lighting.brdf;
import lib.lighting.ssrt;
import lib.surface.material;
import lib.toggles;
import lib.util.math;
import lib.util.random;
import lib.util.space_conversion;

Texture2D<float> tex_noise_blue;
Texture2D<float3> tex_scene;
Texture2D<float4> tex_sky_map;

namespace specular {
interface ISamplingMethod {
	[mutating]
	void init(int2 icoord, int ray_count);
	[mutating]
	float2 sample(int i);
}

// Sampling scheme using PCG random.
struct PcgSampler : ISamplingMethod {
	PcgRandom random;

	[mutating]
	void init(int2 icoord, int ray_count) {
		random = PcgRandom(pixel_seed(icoord));
	}

	[mutating]
	float2 sample(int i) { return random.next_float2(); }
}

// Sampling scheme using 2D blue noise and Rn sequence.
struct RnBlueNoiseSampler : ISamplingMethod {
	float2 dither;

	[mutating]
	void init(int2 icoord, int ray_count) {
		dither = float2(
			tex_noise_blue[icoord & 511],
			tex_noise_blue[(icoord + 43) & 511]
		);
		dither = r2(ap.timing.frameCounter * ray_count, dither);
	}

	[mutating]
	float2 sample(int i) { return r2(i, dither); }
}

struct ReflectionSampler : ISamplingMethod = RnBlueNoiseSampler;

public struct SpecularHit {
	public float3 radiance;
	public float distance;
}

public interface ISpecularTracer {
	[mutating]
	void init(
		float3 ray_origin_screen,
		float3 ray_origin_view,
		float3 ray_origin_world
	);

	Optional<SpecularHit> trace(float3 ray_dir_world);
}

public float3 calculate_reflection<Tracer>(
	Tracer tracer,
	Material material,
	int2 icoord,
	float3 pos_screen,
	float3 pos_view,
	float3 pos_world,
	float3 dir_world,
	float3 normal_world,
	float skylight
)
	where Tracer : ISpecularTracer {
	float sky_visibility = pow2(skylight);

	tracer.init(pos_screen, pos_view, pos_world);

	if (TOGGLE_ROUGH_SPECULAR && WaveActiveAnyTrue(material.roughness > 0.01)) {
		return calculate_rough_reflection(
			tracer,
			material,
			icoord,
			dir_world,
			normal_world,
			sky_visibility
		);
	}

	return calculate_mirror_reflection(
		tracer,
		material,
		dir_world,
		normal_world,
		sky_visibility
	);
}

float3 calculate_rough_reflection<Tracer>(
	Tracer tracer,
	Material material,
	int2 icoord,
	float3 dir_world,
	float3 normal_world,
	float sky_visibility
)
	where Tracer : ISpecularTracer {
	const int RAY_COUNT = 4;

	float3x3 tbn = make_tbn_matrix(normal_world);
	float3 tangent_dir = mul(tbn, dir_world);

	float3 reflection = float3(0.0);

	ReflectionSampler sampler;
	sampler.init(icoord, RAY_COUNT);

	for (int ray = 0; ray < RAY_COUNT; ++ray) {
		float3 microfacet_normal = mul(
			sample_ggx_vndf(
				-tangent_dir,
				material.roughness,
				sampler.sample(ray)
			),
			tbn
		);

		float3 ray_dir_world = reflect(dir_world, microfacet_normal);

		float MoL = dot(microfacet_normal, ray_dir_world);
		float MoV = -dot(microfacet_normal, dir_world);

		float3 fresnel = calculate_fresnel(material, MoV);
		if (all(fresnel < 1e-2)) {
			continue;
		}

		float alpha_squared = pow2(material.roughness);
		float g1 = g1_smith_ggx(MoV, alpha_squared);
		float g2 = g2_smith_ggx(MoL, MoV, alpha_squared);

		Optional<float> hit_distance;
		reflection += get_radiance_along_ray(
						  tracer,
						  ray_dir_world,
						  sky_visibility,
						  hit_distance
					  )
			* fresnel * (g2 / g1);
	}

	return reflection * rcp(float(RAY_COUNT));
}

float3 calculate_mirror_reflection<Tracer>(
	Tracer tracer,
	Material material,
	float3 dir_world,
	float3 normal_world,
	float sky_visibility
)
	where Tracer : ISpecularTracer {
	float3 fresnel = calculate_fresnel(material, -dot(dir_world, normal_world));
	if (all(fresnel < 1e-2)) {
		return float3(0.0);
	}

	float3 ray_dir_world = reflect(dir_world, normal_world);

	Optional<float> hit_distance;
	return get_radiance_along_ray(
			   tracer,
			   ray_dir_world,
			   sky_visibility,
			   hit_distance
		   )
		* fresnel;
}

float3 get_radiance_along_ray<Tracer>(
	Tracer tracer,
	float3 ray_dir_world,
	float sky_visibility,
	out Optional<float> hit_distance
)
	where Tracer : ISpecularTracer {
	if (let hit = tracer.trace(ray_dir_world)) {
		hit_distance = hit.distance;
		return hit.radiance;
	} else {
		hit_distance = none;
		return atmosphere.lookup_sky_radiance(tex_sky_map, ray_dir_world).rgb
			* sky_visibility;
	}
}

public struct HiZScreenSpaceTracer : ISpecularTracer {
	public float3 ray_origin_screen;
	public float3 ray_origin_view;

	[mutating]
	public void init(
		float3 ray_origin_screen,
		float3 ray_origin_view,
		float3 ray_origin_world
	) {
		this.ray_origin_screen = ray_origin_screen;
		this.ray_origin_view = ray_origin_view;
	}

	public Optional<SpecularHit> trace(float3 ray_dir_world) {
		float3 ray_dir_view = mul(float3x3(ap.camera.view), ray_dir_world);
		Ray ray = Ray(
			ray_origin_screen,
			ssrt.screen_space_ray_direction(
				ray_origin_screen,
				ray_origin_view,
				ray_dir_view
			)
		);

		if (let hit_pos_screen = ssrt.trace_hiz(
				ray,
				ssrt.screen_space_ray_length(ray),
				ssrt.thickness_heuristic(ray_dir_view, ray.d)
			)) {
			float3 hit_pos_view = screen_to_view(hit_pos_screen);
			return SpecularHit(
				tex_scene.sampleLinear(hit_pos_screen.xy),
				distance(ray_origin_view, hit_pos_view)
			);
		} else {
			return none;
		}
	}
}
}


