public module gbuffer_packing;

import lib.util.encoding;
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

		SolidGbuffer data;
		data.albedo = unpacked0.xyz;
		data.mat_id = uint(unpacked0.w * 255.0);
		data.flat_normal_world = decode_octahedral(unpacked1.xy);
		data.lightmap = unpacked1.zw;

		if (userSettings.LABPBR_SUPPORT_ENABLED) {
			data.detail_normal_world
				= decode_octahedral(unpackUnorm2x16ToFloat(packed.z));
			data.specular_map = unpackUnorm4x8ToFloat(packed.w);
		}

		return data;
	}

	uint4 pack() {
		uint4 packed;
		packed.x = packUnorm4x8(float4(albedo, float(mat_id) / 255.0));
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


