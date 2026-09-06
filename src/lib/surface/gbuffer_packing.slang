public module gbuffer_packing;

import lib.util.encoding;
import lib.util.math;
import settings;

struct OpaqueGbuffer {
	float3 albedo;
	float3 flat_normal_world;
	float2 lightmap;
	uint mat_id;
	Conditional<float3, userSettings.LABPBR_SUPPORT_ENABLED>
		detail_normal_world;
	Conditional<float4, userSettings.LABPBR_SUPPORT_ENABLED> specular_map;
	Conditional<float, userSettings.LABPBR_SUPPORT_ENABLED> texture_ao;
	Conditional<bool, userSettings.LABPBR_SUPPORT_ENABLED> parallax_self_shadow;

	static OpaqueGbuffer unpack(uint4 packed) {
		float4 unpacked0 = unpackUnorm4x8ToFloat(packed.x);
		float4 unpacked1 = unpackUnorm4x8ToFloat(packed.y);

		OpaqueGbuffer unpacked;
		unpacked.albedo = unpacked0.xyz;
		unpacked.mat_id = uint(unpacked0.w * 255.0);
		unpacked.flat_normal_world = decode_octahedral(unpacked1.xy);
		unpacked.lightmap = unpacked1.zw;

		if (userSettings.LABPBR_SUPPORT_ENABLED) {
			float4 unpacked_z = unpack_unorm_arb(packed.z, uint4(12, 12, 7, 1));

			unpacked.detail_normal_world.set(decode_octahedral(unpacked_z.xy));
			unpacked.texture_ao.set(unpacked_z.z);
			unpacked.parallax_self_shadow.set(unpacked_z.w > 0.5);
			unpacked.specular_map.set(unpackUnorm4x8ToFloat(packed.w));
		}

		return unpacked;
	}

	uint4 pack() {
		uint4 packed;
		packed.x = packUnorm4x8(float4(albedo, float(mat_id) * rcp(255.0)));
		packed.y = packUnorm4x8(
			float4(encode_octahedral(flat_normal_world), lightmap)
		);

		if (userSettings.LABPBR_SUPPORT_ENABLED) {
			packed.z = pack_unorm_arb(
				float4(
					encode_octahedral(detail_normal_world.get().value),
					texture_ao.get().value,
					select(parallax_self_shadow.get().value, 1.0, 0.0)
				),
				uint4(12, 12, 7, 1)
			);
			packed.w = packUnorm4x8(specular_map.get().value);
		}

		return packed;
	}
}

// Only stores data needed for SSR and water rendering.
struct TranslucentGbuffer {
	float3 normal_world;
	int mat_id;
	float skylight;
	float2 specular_map_rg;
	// Used for hardcoded metals and biome-based water aborption.
	Optional<float3> albedo;

	static TranslucentGbuffer unpack(uint2 packed) {
		float4 unpacked0 = unpackUnorm4x8ToFloat(packed.x);
		float4 unpacked1 = unpackUnorm4x8ToFloat(packed.y);

		TranslucentGbuffer unpacked;
		unpacked.normal_world = decode_octahedral(unpacked0.xy);
		unpacked.skylight = unpacked0.z;
		unpacked.mat_id = int(unpacked0.w * 255.0);

		// Water or albedo metal.
		bool stores_albedo = any(unpacked1.zw >= EPS);

		if (stores_albedo) {
			unpacked.specular_map_rg = float2(unpacked1.x, 0.0);
			unpacked.albedo
				= saturate((unpacked1.yzw * (255.0 / 245.0) - (1.0 / 254.0)));
		} else {
			unpacked.specular_map_rg = unpacked1.xy;
			unpacked.albedo = none;
		}

		return unpacked;
	}

	uint2 pack() {
		uint2 packed;
		packed.x = packUnorm4x8(float4(
			encode_octahedral(normal_world),
			skylight,
			float(mat_id) * rcp(255.0)
		));
		if (let albedo_val = albedo) {
			// Water or hardcoded metal.
			packed.y = packUnorm4x8(float4(
				specular_map_rg.r,
				albedo_val * (254.0 / 255.0) + (1.0 / 255.0)
			));
		} else {
			packed.y = packUnorm4x8(float4(specular_map_rg, float2(0.0)));
		}
		return packed;
	}
}


