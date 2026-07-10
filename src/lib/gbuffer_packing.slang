public module gbuffer_packing;

import lib.util.encoding;

struct GbufferData {
	float3 albedo;
	float3 normal_world;
	float2 lightmap;
	uint block_id;

	static GbufferData unpack(uint2 packed) {
		float4 unpacked0 = unpackUnorm4x8ToFloat(packed.x);
		float4 unpacked1 = unpackUnorm4x8ToFloat(packed.y);

		GbufferData data;
		data.albedo = unpacked0.xyz;
		data.block_id = uint(unpacked0.w * 255.0);
		data.normal_world = decode_octahedral(unpacked1.xy);
		data.lightmap = unpacked1.zw;
		return data;
	}

	uint2 pack() {
		return uint2(
			packUnorm4x8(float4(albedo, float(block_id) / 255.0)),
			packUnorm4x8(float4(encode_octahedral(normal_world), lightmap))
		);
	}
}


