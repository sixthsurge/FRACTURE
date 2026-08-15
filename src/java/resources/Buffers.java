package resources;

import dev.irisshaders.aperture.api.objects.MappedBuffer;
import dev.irisshaders.aperture.api.pipeline.FrameState;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;

public class Buffers {
	private MappedBuffer<GlobalBufferData> globalBuffer;

	public Buffers(PipelineConfig pipeline) {
		globalBuffer
			= pipeline.mappedBuffer("buf_global", GlobalBufferData.class);

		pipeline.buffer("buf_exposure", 4 * 4); // float, float, int, int
		pipeline.buffer("buf_sky_sh", 10 * 4 * 4); // float3[9], float3

		// For FidelityFX-SPD.
		pipeline.buffer("spdGlobalAtomic", 4);
	}

	public void update(FrameState frame) {
		globalBuffer.write(GlobalBufferData.get(frame));
	}
}
