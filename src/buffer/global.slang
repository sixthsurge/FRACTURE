public module common;

struct GlobalBuffer {
	float3 light_dir_world;
}

/// Buffer full of goodies that are useful everywhere.
ConstantBuffer<GlobalBuffer> buf_global;


