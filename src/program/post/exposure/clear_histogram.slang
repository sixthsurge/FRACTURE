import settings;

RWTexture2D<uint> tex_exposure_histogram;

[shader("compute")]
[numthreads(256)]
void main(int3 id: SV_DispatchThreadID) {
	tex_exposure_histogram.Store(id.xy, 0);
}


