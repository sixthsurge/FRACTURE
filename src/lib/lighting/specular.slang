module specular;

import aperture;
import lib.atmospherics.atmosphere;
import lib.lighting.brdf;
import lib.lighting.ssrt;
import lib.surface.material;
import lib.toggles;
import lib.util.encoding;
import lib.util.filtering;
import lib.util.math;
import lib.util.random;
import lib.util.space_conversion;
import rt_pipeline;

import lib.util.debug;

RWTexture2D<float4> tex_specular_temporal_1;
RWTexture2D<float4> tex_specular_temporal_2;
Texture2D<float4> tex_specular_temporal_1_prev;
Texture2D<float4> tex_specular_temporal_2_prev;
Texture2D<float> tex_noise_blue;
Texture2D<float3> tex_scene;
Texture2D<float4> tex_sky_map;

namespace specular {
public struct TemporalData {
	public float3 reflection_over_fresnel;
	public float pixel_age;
	public float2 normal_enc;
	public float depth;
	public float roughness;

	public static TemporalData empty() {
		return TemporalData(float3(0.0), 0.0, float2(0.5), 0.0, 0.0);
	}

	public static Optional<TemporalData> load(float2 uv) {
		if (any(saturate(uv) != uv)) {
			return none;
		}

		float4 h0
			= tex_specular_temporal_1_prev.sample_catmull_rom_fast(uv, 0, 0.0);
		float4 h1 = tex_specular_temporal_2_prev.sampleNearestLevel(uv, 0);
		if (any(isnan(h0)) || any(isnan(h1))) {
			return none;
		}

		return TemporalData(h0.rgb, h0.w, h1.xy, h1.z, h1.w);
	}

	public void store(int2 icoord) {
		tex_specular_temporal_1[icoord]
			= float4(reflection_over_fresnel, pixel_age);
		tex_specular_temporal_2[icoord] = float4(normal_enc, depth, roughness);
	}
}

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

float3 reproject_reflection(
	float3 pos_world,
	float3 dir_world,
	float NoV,
	float roughness,
	float average_hit_distance
) {
	// Virtual motion.
	pos_world += dir_world * average_hit_distance
		* get_specular_dominant_factor(NoV, roughness);

	float3 pos = pos_world - ap.temporal.position;
	pos = scene_to_view(pos, ap.temporal.view);
	pos = view_to_screen(pos, ap.temporal.projection, false);
	return pos;
}

// Source: Ray Tracing Gem II Listing 49-2.
float compute_parallax(float3 x, float3 x_prev, float3 camera_delta) {
	float3 v = normalize(x);
	float3 v_prev = normalize(x_prev - camera_delta);
	float cos_a = saturate(dot(v, v_prev));
	return sqrt(1.0 - pow2(cos_a)) / max(cos_a, 1e-6);
}

// Source: Ray Tracing Gens II Listing 49-5.
float get_specular_dominant_factor(float NoV, float roughness) {
	float a = 0.298475 * log(39.4115 - 39.0029 * roughness);
	float f = pow(saturate(1.0 - NoV), 10.8649) * (1.0 - a) + a;
	return saturate(f);
}

TemporalData accumulate_rough_reflection(
	inout float3 reflection,
	Material material,
	float3 pos_screen,
	float3 pos_view,
	float3 pos_world,
	float3 dir_world,
	float3 normal_world,
	float average_hit_distance,
	float NoV,
	int2 icoord,
) {
	let pos_prev_screen = reproject_reflection(
		pos_world,
		dir_world,
		NoV,
		material.roughness,
		average_hit_distance
	);
	let f = calculate_fresnel(material, dot(-dir_world, normal_world));
	let rcp_f = select(f == 0.0, 0.0, rcp(f));

	if (let temporal = TemporalData.load(pos_prev_screen.xy)) {
		const float DEPTH_REJECTION_STRENGTH = 64.0;

		let max_accumulated_frames
			= 40.0 * (linstep(0.0, 0.5, (material.roughness)));

		// Depth rejection
		float view_norm = rlength(pos_view);
		float z0 = screen_to_view_depth(pos_screen.z);
		float z1 = screen_to_view_depth(temporal.depth);
		float depth_weight
			= exp2(-abs(z0 - z1) * DEPTH_REJECTION_STRENGTH * NoV * view_norm);

		// Normal rejection
		float normal_weight = pow(
			max0(dot(decode_octahedral(temporal.normal_enc), normal_world)),
			128
		);

		let pixel_age = min(
			temporal.pixel_age * depth_weight * normal_weight,
			max_accumulated_frames
		);

		let history_weight = pixel_age / (pixel_age + 1.0);
		reflection = max0(lerp(
			reflection,
			temporal.reflection_over_fresnel * f,
			history_weight
		));

		return TemporalData(
			reflection * rcp_f,
			pixel_age + 1.0,
			encode_octahedral(normal_world),
			pos_screen.z,
			material.roughness,
		);
	} else {
		return TemporalData(
			reflection * rcp_f,
			0.0,
			encode_octahedral(normal_world),
			pos_screen.z,
			material.roughness,
		);
	}
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
	float NoV = -dot(dir_world, normal_world);

	tracer.init(pos_screen, pos_view, pos_world);

	float3 reflection;
	TemporalData temporal_data;

	if (TOGGLE_ROUGH_SPECULAR && WaveActiveAnyTrue(material.roughness > 0.01)) {
		float average_hit_distance;
		reflection = calculate_rough_reflection(
			tracer,
			material,
			icoord,
			dir_world,
			normal_world,
			sky_visibility,
			average_hit_distance
		);

		// Accumulation.
		temporal_data = accumulate_rough_reflection(
			reflection,
			material,
			pos_screen,
			pos_view,
			pos_world,
			dir_world,
			normal_world,
			average_hit_distance,
			NoV,
			icoord
		);
	} else {
		reflection = calculate_mirror_reflection(
			tracer,
			material,
			dir_world,
			normal_world,
			sky_visibility
		);
		temporal_data = TemporalData.empty();
		temporal_data = TemporalData(
			float3(0.0),
			0.0,
			encode_octahedral(normal_world),
			pos_screen.z,
			material.roughness,
		);
	}

	temporal_data.store(icoord);

	return reflection;
}

float3 calculate_rough_reflection<Tracer>(
	Tracer tracer,
	Material material,
	int2 icoord,
	float3 dir_world,
	float3 normal_world,
	float sky_visibility,
	out float average_hit_distance
)
	where Tracer : ISpecularTracer {
	const int RAY_COUNT = 2;

	float3x3 tbn = make_tbn_matrix(normal_world);
	float3 tangent_dir = mul(tbn, dir_world);

	float NoV = -dot(normal_world, dir_world);
	float alpha_squared = pow2(material.roughness);
	float g1 = g1_smith_ggx(NoV, alpha_squared);

	float3 reflection = float3(0.0);

	ReflectionSampler sampler;
	sampler.init(icoord, RAY_COUNT);

	average_hit_distance = 0.0;
	float w_sum = EPS;

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

		float NoL = dot(normal_world, ray_dir_world);
		if (NoL < EPS) {
			continue;
		}

		float MoV = -dot(microfacet_normal, dir_world);
		float3 fresnel = calculate_fresnel(material, MoV);
		if (all(fresnel < 1e-2)) {
			continue;
		}

		float g2 = g2_smith_ggx(NoL, NoV, alpha_squared);

		float hit_distance;
		reflection += get_radiance_along_ray(
						  tracer,
						  ray_dir_world,
						  sky_visibility,
						  hit_distance
					  )
			* fresnel * (g2 / g1);

		average_hit_distance += hit_distance;
		w_sum += step(EPS, average_hit_distance);
	}

	average_hit_distance /= w_sum;

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

	float hit_distance;
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
	out float hit_distance
)
	where Tracer : ISpecularTracer {
	if (let hit = tracer.trace(ray_dir_world)) {
		hit_distance = hit.distance;
		return hit.radiance;
	} else {
		hit_distance = 0.0;
		return atmosphere.lookup_sky_radiance(tex_sky_map, ray_dir_world).rgb
			* sky_visibility * float(ray_dir_world.y > 0.0);
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

public struct HardwareRtTracer {
	public float3 ray_origin_world;

	[mutating]
	public void init(
		float3 ray_origin_screen,
		float3 ray_origin_view,
		float3 ray_origin_world
	) {
		this.ray_origin_world = ray_origin_world;
	}

	public Optional<SpecularHit> trace(float3 ray_dir_world) { return none; }
}
}


