public module data;

import aperture;
import lib.lighting.brdf;
import lib.lighting.celestial;
import lib.lighting.emission;
import lib.lighting.vxrt.trace;
import lib.surface.material;
import lib.util.color;
import lib.util.encoding;
import lib.util.math;
import lib.util.random;
import lib.util.sampling;
import lib.volumetrics.atmosphere;

internal Texture2D<float3> tex_atmosphere_sky_view;

namespace restir_gi {
static const int BOUNCE_COUNT = 1;

struct Sample {
	float3 radiance = float3(0.0);
	float3 visible_pos_world = float3(0.0);
	float3 visible_normal_world = float3(0.0);
	float3 sample_pos_world = float3(0.0);
	float3 sample_normal_world = float3(0.0);
	uint random_seed = 0;

	float cos_theta() {
		float3 v = sample_pos_world - visible_pos_world;
		return dot(visible_normal_world, v) * rlength(v);
	}
}

struct Reserviour {
	Sample sample;
	float w; // Weight sum
	float M; // Number of samples
	float W; // Sample weight (eq. 7)

	[mutating]
	void init(Sample initial_sample, float w_sample) {
		sample = initial_sample;
		w = w_sample;
		M = 1.0;
		W = 0.0;
	}

	[mutating]
	void load(
		Texture2D<float4> tex1,
		Texture2D<float4> tex2,
		Texture2D<float4> tex3,
		Texture2D<float4> tex4,
		int2 icoord,
	) {
		float4 s1 = tex1[icoord];
		float4 s2 = tex2[icoord];
		float4 s3 = tex3[icoord];
		float4 s4 = tex4[icoord];

		sample.radiance = s1.xyz;
		sample.sample_pos_world = s2.xyz;
		sample.visible_pos_world = s3.xyz;
		sample.sample_normal_world = decode_octahedral(s4.xy);
		sample.visible_normal_world = decode_octahedral(s4.zw);
		w = s1.w;
		W = s2.w;
		M = s3.w;
	}

	void store(
		RWTexture2D<float4> tex1,
		RWTexture2D<float4> tex2,
		RWTexture2D<float4> tex3,
		RWTexture2D<float4> tex4,
		int2 icoord,
	) {
		float4 store1 = float4(sample.radiance, w);
		float4 store2 = float4(sample.sample_pos_world, W);
		float4 store3 = float4(sample.visible_pos_world, M);
		float4 store4 = float4(
			encode_octahedral(sample.sample_normal_world),
			encode_octahedral(sample.visible_normal_world)
		);
		tex1[icoord] = store1;
		tex2[icoord] = store2;
		tex3[icoord] = store3;
		tex4[icoord] = store4;
	}

	[mutating]
	void
	update<Random>(Random random, Sample sample_new, float w_new, float M_max)
		where Random : IRandom {
		M += 1.0;
		float M_clamped = min(M, M_max);
		w = w * ((M_clamped) / M) + w_new;
		M = M_clamped;

		if (random.next_float() < w_new / w) {
			sample.radiance = sample_new.radiance;
			sample.sample_pos_world = sample_new.sample_pos_world;
			sample.visible_pos_world = sample_new.visible_pos_world;
			sample.sample_normal_world = sample_new.sample_normal_world;
			sample.visible_normal_world = sample_new.visible_normal_world;
			sample.random_seed = sample_new.random_seed;
		}
	}

	[mutating]
	void merge<Random>(Random random, Reserviour r, float p_hat)
		where Random : IRandom {
		float M_0 = M;
		update(random, r.sample, p_hat * r.W * r.M, 200);
		M = M_0 + r.M;
	}
}

// Path tracing.
// Diffuse only for now.
Sample initial_sample(
	int random_seed,
	Material material,
	float3 ray_origin_world,
	float3 ray_dir,
	float3 flat_normal_world,
	float3 detail_normal_world,
) {
	const int INTERSECTION_STEPS = 50;

	PcgRandom random = PcgRandom(random_seed);

	float3 sample_point = float3(0.0, 0.0, 0.0);
	float3 sample_normal = float3(0.0, 1.0, 0.0);

	float3 current_pos = ray_origin_world;
	Material current_material = material;
	float3 current_flat_normal = flat_normal_world;
	float3 current_detail_normal = detail_normal_world;
	float3 incoming_dir = ray_dir;

	// First bounce.
	float3 ray_dir = sample_cos_weighted_hemisphere(
		current_detail_normal,
		random.next_float2()
	);
	if (dot(ray_dir, current_flat_normal) < EPS) {
		ray_dir = -ray_dir;
	}

	bool hit_sky = false;
	float3 sample_radiance;
	float3 tint;
	if (let hit
		= vxrt.trace(Ray(current_pos, ray_dir), INTERSECTION_STEPS, tint)) {
		sample_radiance
			= calculate_celestial_light<true>(
				  hit.material,
				  hit.pos_world - ap.camera.position,
				  ray_dir,
				  hit.normal,
				  hit.normal,
				  random.next_float()
			  )
			+ calculate_emission(hit.material.emission);
		current_pos = hit.pos_world;
		current_flat_normal = hit.normal;
		current_detail_normal = hit.normal;
		current_material = hit.material;

		sample_point = current_pos;
		sample_normal = current_flat_normal;
	} else {
		sample_radiance
			= atmosphere.lookup_sky_radiance(tex_atmosphere_sky_view, ray_dir);

		// hit is far away lol.
		sample_point = ray_dir * 1000.0;
	}

	tint = sqrt(sqrt(tint));
	sample_radiance *= tint;
	incoming_dir = ray_dir;

	/*
	// Subsequent bounces.
	float3 throughput = tint;

	for (int bounce = 1; bounce < BOUNCE_COUNT && !hit_sky; ++bounce) {
		float3 ray_dir = sample_cos_weighted_hemisphere(
			current_detail_normal,
			random.next_float2()
		);
		if (dot(ray_dir, current_flat_normal) < EPS) {
			ray_dir = -ray_dir;
		}

		float3 brdf_over_pdf = current_material.albedo;

		float3 bounce_radiance;
		float3 tint = float3(1.0);
		if (let hit
			= vxrt.trace(Ray(current_pos, ray_dir), INTERSECTION_STEPS, tint)) {
			bounce_radiance
				= calculate_celestial_light<true>(
					  hit.material,
					  hit.pos_world - ap.camera.position,
					  ray_dir,
					  hit.normal,
					  hit.normal,
					  random.next_float()
				  )
				+ calculate_emission(hit.material.emission);
			current_pos = hit.pos_world;
			current_flat_normal = hit.normal;
			current_detail_normal = hit.normal;
			current_material = hit.material;
		} else {
			bounce_radiance = atmosphere.lookup_sky_radiance(
				tex_atmosphere_sky_view,
				ray_dir
			);
			hit_sky = true;
		}

		tint = sqrt(sqrt(tint));
		sample_radiance += bounce_radiance * throughput * brdf_over_pdf * tint;
		throughput *= brdf_over_pdf * tint;
		incoming_dir = ray_dir;
	}
	*/

	Sample s;
	s.radiance = max0(sample_radiance);
	s.sample_pos_world = sample_point;
	s.sample_normal_world = sample_normal;
	s.visible_pos_world = ray_origin_world;
	s.visible_normal_world = detail_normal_world;
	s.random_seed = random_seed;
	return s;
}

float target_function(Sample s) {
	return dot(s.radiance, LUMINANCE_WEIGHTS_REC709);
}
}


