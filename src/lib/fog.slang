public module fog;

import aperture;
import lib.buffer.sky_sh;
import lib.lighting.shadow;
import lib.util.math;
import lib.util.phase_functions;
import lib.util.space_conversion;
import settings;

ConstantBuffer<SkyShBuffer> buf_sky_sh;

namespace fog {
struct FogMedia<int NUM_SCATTERING_PARTICLE_KINDS> {
	float3 scattering[NUM_SCATTERING_PARTICLE_KINDS];
	float3 extinction;
	float3 emission;
}

struct FogParticipation {
	float3 added_light;
	float3 extinction;

	float3 apply(float3 radiance) {
		return radiance * exp(-extinction) + added_light;
	}
}

interface IFogProfile {
	static const int NUM_SCATTERING_PARTICLE_KINDS;
	static FogMedia<NUM_SCATTERING_PARTICLE_KINDS>
	calculate_local_media(float3 pos_world, float segment_length);
	static float phase_function[NUM_SCATTERING_PARTICLE_KINDS](
		float cos_theta,
		float anisotropy_scale
	);
	static float
	distance_to_volume_end(float3 ray_origin_world, float3 ray_dir_world);
}

struct OverworldProfile : IFogProfile {
	static const int NUM_SCATTERING_PARTICLE_KINDS = 2;
	static const float3 RLH_SCATTERING_COEFF
		= float3(0.3, 0.5, 1.0) * float3(0.0002);
	static const float3 RLH_EXTINCTION_COEFF
		= float3(0.3, 0.5, 1.0) * float3(0.0002);
	static const float3 MIE_SCATTERING_COEFF
		= float3(0.9, 0.9, 0.9) * float3(0.0001);
	static const float3 MIE_EXTINCTION_COEFF
		= float3(1.0, 1.0, 1.0) * float3(0.0001);
	static const float BOTTOM_PLANE_ALTITUDE = 0.0;
	static const float TOP_PLANE_ALTITUDE = 320.0;

	static FogMedia<NUM_SCATTERING_PARTICLE_KINDS>
	calculate_local_media(float3 pos_world, float segment_length) {
		const float SEA_LEVEL = 63.0;
		const float RLH_SCALE_HEIGHT = 40.0;
		const float MIE_SCALE_HEIGHT = 10.0;

		float2 density = exp(-max0(pos_world.y - SEA_LEVEL)
							 / float2(RLH_SCALE_HEIGHT, MIE_SCALE_HEIGHT))
			* segment_length;
		density.y
			/= max(linstep(0.0, 0.66, buf_global.sun_dir_world.y), 0.05) * 0.9
			+ 0.1;

		return FogMedia<NUM_SCATTERING_PARTICLE_KINDS>(
			{ RLH_SCATTERING_COEFF * density.x,
			  MIE_SCATTERING_COEFF * density.y },
			RLH_EXTINCTION_COEFF * density.x + MIE_EXTINCTION_COEFF * density.y,
			float3(0.0),
		);
	}

	static float phase_function[NUM_SCATTERING_PARTICLE_KINDS](
		float cos_theta,
		float anisotropy_scale
	) {
		return {
			ISOTROPIC_PHASE,
			lerp(
				henyey_greenstein_phase(cos_theta, 0.5 * anisotropy_scale),
				ISOTROPIC_PHASE,
				0.5
			),
		};
	}

	static float
	distance_to_volume_end(float3 ray_origin_world, float3 ray_dir_world) {
		return fog_volume_far();
	}
}

FogParticipation calculate_local_participation<FogProfile>(
	float3 pos_world,
	float3 ray_dir_world,
	float segment_length
)
	where FogProfile : IFogProfile {
	float3 pos_shadow_view
		= transform(ap.celestial.view, pos_world - ap.camera.position);

	float celestial_light_visibility = 1.0;
	if (let proj = shadow.project_shadow(pos_shadow_view)) {
		celestial_light_visibility = ap.opaqueShadow.compare(
			proj.pos_shadow_screen.xy,
			proj.cascade,
			proj.pos_shadow_screen.z
		);
	}

	FogMedia<FogProfile.NUM_SCATTERING_PARTICLE_KINDS> local_media
		= FogProfile.calculate_local_media(pos_world, segment_length);

	float3 step_transmittance = exp(-local_media.extinction);
	float3 step_transmitted_fraction
		= (1.0 - step_transmittance) / max(local_media.extinction, EPS);

	float3 step_added_light = local_media.emission;
	float anistropy_scale = 1.0;
	float scattering_scale = 1.0;

	float3 irradiance_celestial
		= buf_global.celestial_light_irradiance * celestial_light_visibility;
	float3 irradiance_ambient = buf_sky_sh.irradiance_up;

	[unroll]
	for (int ms_iter = 0; ms_iter < 4; ++ms_iter) {
		float phase_functions[FogProfile.NUM_SCATTERING_PARTICLE_KINDS]
			= FogProfile.phase_function(
				dot(ray_dir_world, buf_global.light_dir_world),
				anistropy_scale
			);

		[unroll]
		for (int particle_kind = 0;
			 particle_kind < FogProfile.NUM_SCATTERING_PARTICLE_KINDS;
			 ++particle_kind) {
			step_added_light += local_media.scattering[particle_kind]
				* step_transmitted_fraction * scattering_scale
				* (irradiance_celestial * phase_functions[particle_kind]
				   + irradiance_ambient * ISOTROPIC_PHASE);
		}
		scattering_scale *= 0.5;
		anistropy_scale *= 0.5;
	}

	return FogParticipation(step_added_light, local_media.extinction);
}

// Not optimized at all; for use in comparison with froxel method.
FogParticipation raymarch<FogProfile>(
	float3 ray_origin_world,
	float3 ray_dir_world,
	float distance_to_terrain,
	float dither,
)
	where FogProfile : IFogProfile {
	const int STEP_COUNT = 40;

	float ray_length = min(
		distance_to_terrain,
		FogProfile.distance_to_volume_end(ray_origin_world, ray_dir_world),
	);
	float step_length = ray_length / float(STEP_COUNT);

	float3 ray_step_world = ray_dir_world * step_length;
	float3 ray_pos_world = ray_origin_world + dither * ray_step_world;

	float3 added_light = float3(0.0);
	float3 extinction = float3(0.0);

	for (int i = 0; i < STEP_COUNT; ++i) {
		FogParticipation local_participation
			= calculate_local_participation<FogProfile>(
				ray_pos_world,
				ray_dir_world,
				step_length
			);

		added_light += local_participation.added_light
			* exp(-(extinction + local_participation.extinction));
		extinction += local_participation.extinction;
		ray_pos_world += ray_step_world;
	}

	return FogParticipation(added_light, extinction);
}

float fog_volume_far() { return ap.world.renderDistance; }

float3 project_fog_volume(float3 pos_screen, float3 pos_view) {
	float z = sqrt(sqrt(sqrt(length(pos_view) / fog_volume_far())));
	return float3(pos_screen.xy, z);
}

float3 unproject_fog_volume(float3 ncoord) {
	float z = pow2(pow4(ncoord.z)) * fog_volume_far() + EPS;
	float3 ps = float3(ncoord.xy, 1.0);
	float3 pv = screen_to_view(ps);
	return normalize(pv) * z;
}

FogParticipation lookup_fog_participation(
	Texture3D<float3> tex_light,
	Texture3D<float3> tex_extinction,
	float3 pos_screen,
	float3 pos_view,
) {
	int w, h, d;
	tex_light.GetDimensions(w, h, d);

	float3 uv = get_uv_from_unit_range(
		project_fog_volume(pos_screen, pos_view),
		float3(w, h, d)
	);
	float3 light = tex_light.Sample(apt_linearSampler, uv);
	float3 extinction = tex_extinction.Sample(apt_linearSampler, uv);

	return FogParticipation(light, extinction);
}

// Lookup only light or extinction.
float3 lookup_fog(Texture3D<float3> tex, float3 pos_screen, float3 pos_view, ) {
	int w, h, d;
	tex.GetDimensions(w, h, d);

	float3 uv = get_uv_from_unit_range(
		project_fog_volume(pos_screen, pos_view),
		float3(w, h, d)
	);
	return tex.Sample(apt_linearSampler, uv);
}
}


