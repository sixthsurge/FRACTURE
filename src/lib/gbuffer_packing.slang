public module gbuffer_packing;

import lib.util.encoding;

struct GbufferData {
	float3 albedo;
	float3 flat_normal_world;
	float2 lightmap;
	uint block_id;
	float3 detail_normal_world;
	float4 specular_map;

	static GbufferData unpack(uint4 packed) {
		float4 unpacked0 = unpackUnorm4x8ToFloat(packed.x);
		float4 unpacked1 = unpackUnorm4x8ToFloat(packed.y);

		GbufferData data;
		data.albedo = unpacked0.xyz;
		data.block_id = uint(unpacked0.w * 255.0);
		data.flat_normal_world = decode_octahedral(unpacked1.xy);
		data.lightmap = unpacked1.zw;
		data.detail_normal_world
			= decode_octahedral(unpackUnorm2x16ToFloat(packed.z));
		data.specular_map = unpackUnorm4x8ToFloat(packed.w);
		return data;
	}

	uint4 pack() {
		return uint4(
			packUnorm4x8(float4(albedo, float(block_id) / 255.0)),
			packUnorm4x8(
				float4(encode_octahedral(flat_normal_world), lightmap)
			),
			packUnorm2x16(encode_octahedral(detail_normal_world)),
			packUnorm4x8(specular_map)
		);
	}
}


