public module gbuffer_packing;

import lib.util.encoding;
import lib.util.math;
import settings;

struct SolidGbuffer {
	float3 albedo;
	float3 flat_normal_world;
	float2 lightmap;
	uint mat_id;
	Conditional<float3, userSettings.LABPBR_SUPPORT_ENABLED>
		detail_normal_world;
	Conditional<float4, userSettings.LABPBR_SUPPORT_ENABLED> specular_map;

	static SolidGbuffer unpack(uint4 packed) {
		float4 unpacked0 = unpackUnorm4x8ToFloat(packed.x);
		float4 unpacked1 = unpackUnorm4x8ToFloat(packed.y);

		SolidGbuffer unpacked;
		unpacked.albedo = unpacked0.xyz;
		unpacked.mat_id = uint(unpacked0.w * 255.0);
		unpacked.flat_normal_world = decode_octahedral(unpacked1.xy);
		unpacked.lightmap = unpacked1.zw;

		if (userSettings.LABPBR_SUPPORT_ENABLED) {
			unpacked.detail_normal_world.set(
				decode_octahedral(unpackUnorm2x16ToFloat(packed.z))
			);
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
			packed.z = packUnorm2x16(
				encode_octahedral(detail_normal_world.get().value)
			);
			packed.w = packUnorm4x8(specular_map.get().value);
		}

		return packed;
	}
}

// Only stores data needed for reflection and refraction.
// Albedo is not stored so albedo metals are unsupported for translucents.
struct TranslucentGbuffer {
	float3 normal_world;
	int mat_id;
	float skylight;
	Conditional<float2, userSettings.LABPBR_SUPPORT_ENABLED> specular_map_rg;
	Conditional<Optional<float3>, userSettings.LABPBR_SUPPORT_ENABLED>
		albedo_for_albedo_metals;

	static TranslucentGbuffer unpack(uint2 packed) {
		float4 unpacked0 = unpackUnorm4x8ToFloat(packed.x);

		TranslucentGbuffer unpacked;
		unpacked.normal_world = decode_octahedral(unpacked0.xy);
		unpacked.skylight = unpacked0.z;
		unpacked.mat_id = int(unpacked0.w * 255.0);

		if (userSettings.LABPBR_SUPPORT_ENABLED) {
			float4 unpacked1 = unpackUnorm4x8ToFloat(packed.y);
			float f0 = 0.0;
			bool is_albedo_metal = any(unpacked1.zw >= EPS);

			if (is_albedo_metal) {
				unpacked.specular_map_rg.set(float2(unpacked1.x, 0.0));
				unpacked.albedo_for_albedo_metals.set(
					saturate((unpacked1.yzw * (255.0 / 245.0) - (1.0 / 254.0)))
				);
			} else {
				unpacked.specular_map_rg.set(unpacked1.xy);
				unpacked.albedo_for_albedo_metals.set(none);
			}
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
		if (userSettings.LABPBR_SUPPORT_ENABLED) {
			if (let metal_f0 = albedo_for_albedo_metals.get().value) {
				packed.y = packUnorm4x8(float4(
					specular_map_rg.get().value.r,
					metal_f0 * (254.0 / 255.0) + (1.0 / 255.0)
				));
			} else {
				packed.y = packUnorm4x8(
					float4(specular_map_rg.get().value, float2(0.0))
				);
			}
		}
		return packed;
	}
}


