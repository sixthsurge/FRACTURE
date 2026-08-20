import aperture;
import lib.buffer.exposure;
import lib.util.color;
import lib.util.filtering;
import lib.util.math;
import lib.util.space_conversion;

RWTexture2D<float4> tex_taa_output_current;
Texture2D<float4> tex_taa_output_prev;
Texture2D<float3> tex_scene;
ConstantBuffer<ExposureBuffer> buf_exposure;

// More aggressive neighborhood clipping method
// which further reduces ghosting but can
// introduce flickering artifacts
static const bool TAA_VARIANCE_CLIPPING = true;

// Reduces blur when moving quickly. Too much offcenter rejection
// results in aliasing and jittering in motion
static const float TAA_OFFCENTER_REJECTION = 0.25;

// Controls the impact of the
// "confidence-of-quality" factor on
// temporal upscaling. Tradeoff between
// image clarity and time taken to
// converge

static const float TAAU_CONFIDENCE_REJECTION = 5.0;

// Increases ghosting but reduces flickering
// caused by aggressive clipping.
static const float TAAU_FLICKER_REDUCTION = 1.0;

// TAAU is not yet implemented.
static const bool TAAU_ENABLED = false;
static const float TAAU_RENDER_SCALE = 1.0;

float3 min_of(float3 a, float3 b, float3 c, float3 d, float3 f) {
	return min(a, min(b, min(c, min(d, f))));
}

float3 max_of(float3 a, float3 b, float3 c, float3 d, float3 f) {
	return max(a, max(b, max(c, max(d, f))));
}

// Invertible tonemapping operator (Reinhard) applied before blending the
// current and previous frames Improves the appearance of emissive objects
float3 reinhard(float3 rgb) {
	rgb *= buf_exposure.value;
	return rgb / (rgb + 1.0);
}

float3 reinhard_inverse(float3 rgb) {
	rgb = rgb / (1.0 - rgb);
	return rgb / buf_exposure.value;
}

// Estimates the closest fragment in a 5x5 radius with 5 samples in a cross
// pattern Improves reprojection for objects in motion
float3 get_closest_fragment(int2 icoord0) {
	int2 icoord1 = icoord0 + int2(-2, -2);
	int2 icoord2 = icoord0 + int2(2, -2);
	int2 icoord3 = icoord0 + int2(-2, 2);
	int2 icoord4 = icoord0 + int2(2, 2);

	float depth0 = ap.depth[icoord0];
	float depth1 = ap.depth[icoord1];
	float depth2 = ap.depth[icoord2];
	float depth3 = ap.depth[icoord3];
	float depth4 = ap.depth[icoord4];

	float3 pos
		= depth0 > depth1 ? float3(icoord0, depth0) : float3(icoord1, depth1);
	float3 pos1
		= depth2 > depth3 ? float3(icoord2, depth2) : float3(icoord3, depth3);
	pos = pos.z > pos1.z ? pos : pos1;
	pos = pos.z > depth4 ? pos : float3(icoord4, depth4);

	return float3(
		(pos.xy + 0.5) * rcp(float2(ap.game.renderSize))
			* rcp(TAAU_RENDER_SCALE),
		pos.z
	);
}

// AABB clipping from "Temporal Reprojection Anti-Aliasing in INSIDE"
float3 clip_aabb(
	float3 history_color,
	float3 min_color,
	float3 max_color,
	out bool history_clipped
) {
	float3 p_clip = 0.5 * (max_color + min_color);
	float3 e_clip = 0.5 * (max_color - min_color);

	float3 v_clip = history_color - p_clip;
	float3 v_unit = v_clip / max(e_clip, 1e-3);
	float3 a_unit = abs(v_unit);
	float ma_unit = max_of(a_unit);
	history_clipped = ma_unit > 1.0;

	return history_clipped ? p_clip + v_clip / ma_unit : history_color;
}

float3 clip_aabb(float3 history_color, float3 min_color, float3 max_color) {
	bool history_clipped;
	return clip_aabb(history_color, min_color, max_color, history_clipped);
}

// Flicker reduction using the "distance to clamp" method from "High Quality
// Temporal Supersampling" by Brian Karis. Only used for TAAU
float get_flicker_reduction(
	float3 history_color,
	float3 min_color,
	float3 max_color
) {
	const float flicker_sensitivity = 5.0;

	float3 min_offset = (history_color - min_color);
	float3 max_offset = (max_color - history_color);

	float distance_to_clip = length(min(min_offset, max_offset))
		* flicker_sensitivity * buf_exposure.value;
	return saturate(distance_to_clip);
}

float3 neighborhood_clipping(
	int2 icoord,
	float3 current_color,
	float3 history_color,
	float distance_factor
) {
	float3 min_color, max_color;

	// Fetch 3x3 neighborhood
	// a b c
	// d e f
	// g h i
	float3 a = tex_scene[icoord + int2(-1, 1)];
	float3 b = tex_scene[icoord + int2(0, 1)];
	float3 c = tex_scene[icoord + int2(1, 1)];
	float3 d = tex_scene[icoord + int2(-1, 0)];
	float3 e = current_color;
	float3 f = tex_scene[icoord + int2(1, 0)];
	float3 g = tex_scene[icoord + int2(-1, -1)];
	float3 h = tex_scene[icoord + int2(0, -1)];
	float3 i = tex_scene[icoord + int2(1, -1)];

	// Convert to YCoCg
	// Clipping in a luminance-chrominance color space is superior because the
	// eyes are more sensitive to luminance than chrominance so an AABB where
	// luminance is one of the axes will result in less visible ghosting than
	// one which is not aligned to the luminance
	a = rgb_to_ycocg(reinhard(a));
	b = rgb_to_ycocg(reinhard(b));
	c = rgb_to_ycocg(reinhard(c));
	d = rgb_to_ycocg(reinhard(d));
	e = rgb_to_ycocg(e);
	f = rgb_to_ycocg(reinhard(f));
	g = rgb_to_ycocg(reinhard(g));
	h = rgb_to_ycocg(reinhard(h));
	i = rgb_to_ycocg(reinhard(i));

	// Soft minimum and maximum ("Hybrid Reconstruction Antialiasing")
	//        b         a b c
	// (min d e f + min d e f) / 2
	//        h         g h i
	min_color = min_of(b, d, e, f, h);
	min_color += min_of(min_color, a, c, g, i);
	min_color *= 0.5;

	max_color = max_of(b, d, e, f, h);
	max_color += max_of(max_color, a, c, g, i);
	max_color *= 0.5;

	if (TAA_VARIANCE_CLIPPING) {
		// Variance clipping ("An Excursion in Temporal Supersampling")
		float3 moments[2];
		moments[0] = (1.0 / 9.0) * (a + b + c + d + e + f + g + h + i);
		moments[1] = (1.0 / 9.0)
			* (a * a + b * b + c * c + d * d + e * e + f * f + g * g + h * h
			   + i * i);

		// Strictness parameter, higher gamma => more temporally stable but more
		// ghosting
		float gamma = lerp(0.75, 1.25, linstep(0.25, 1.0, distance_factor));

		float3 mu = moments[0];
		float3 sigma = sqrt(moments[1] - moments[0] * moments[0]);

		min_color = max(min_color, mu - gamma * sigma);
		max_color = min(max_color, mu + gamma * sigma);
	}

	// Perform AABB clipping in YCoCg space, which results in a tighter AABB
	// because luminance (Y) is separated from chrominance (CoCg) as its own
	// axis
	history_color = rgb_to_ycocg(history_color);
	history_color = clip_aabb(history_color, min_color, max_color);
	history_color = ycocg_to_rgb(history_color);

	return history_color;
}

[shader("compute")]
[numthreads(16, 16)]
void main(int2 icoord: SV_DispatchThreadID) {
	if (any(icoord >= ap.game.screenSize)) {
		return;
	}

	float2 ncoord = (float2(icoord) + 0.5) * rcp(float2(ap.game.renderSize));
	float3 closest_pos_screen = get_closest_fragment(icoord);

	float3 closest_view = screen_to_view(
		closest_pos_screen,
		ap.camera.unjitteredProjectionInv,
		false
	);
	float3 closest_pos_scene = view_to_scene(closest_view);

	float2 velocity = closest_pos_screen.xy
		- view_to_screen(
			  scene_to_view(
				  closest_pos_scene + ap.camera.position - ap.temporal.position,
				  ap.temporal.view
			  ),
			  ap.temporal.unjitteredProjection,
			  false,
		)
			  .xy;
	float2 ncoord_prev = ncoord - velocity;

	float3 history_color
		= tex_taa_output_prev.sample_catmull_rom_fast(ncoord_prev, 0, 0.6, )
			  .rgb;
	history_color = max0(history_color); // Eliminate NaNs in the history

	float pixel_age
		= tex_taa_output_prev[int2(ncoord_prev * float2(ap.game.renderSize))].a;
	pixel_age
		= max0(
			  pixel_age * float(all(saturate(ncoord_prev) == ncoord_prev)) + 1.0
		  )
		+ 1.0;

	// Distance factor to favour responsiveness closer to the camera and image
	// stability further away
	float distance_factor = 1.0 - exp2(-0.025 * length(closest_view));

	// Dynamic blend weight lending equal weight to all frames in the history,
	// drastically reducing time taken to converge when upscaling
	float blend_weight = lerp(0.35, 0.10, distance_factor);
	float alpha = max(1.0 / pixel_age, blend_weight);

	float3 current_color;

	if (!TAAU_ENABLED) {
		// Native resolution TAA
		current_color = tex_scene[icoord];

		// "Tonemapping" before applying TAA in order to perform the AA in SDR
		// This improves the result because the differences between the
		// luminances are closer to how they will be in the final output
		current_color = reinhard(current_color);
		history_color = reinhard(history_color);

		history_color = neighborhood_clipping(
			icoord,
			current_color,
			history_color,
			distance_factor
		);
	} else {
		/*
		// Temporal upscaling
		float2 pos = saturate(ncoord + ap.camera.jitter) * TAAU_RENDER_SCALE;

		Tuple<float3, float> current_sample
			= tex_scene.sample_catmull_rom(pos, 0);
		current_color = current_sample._0;
		// Confidence-of-quality factor, see "A Survey of
		// Temporal Antialiasing Techniques" section 5.1
		float confidence = current_sample._1;

		if (min_of(current_color) < 0.0) {
			// Fix negatives arising around very dark objects
			current_color = tex_scene.sampleLinear(pos);
		}

		current_color = reinhard(current_color);
		history_color = reinhard(history_color);

		// Interpolate AABB bounds across pixels
		float3 min_color = texture(colortex1, pos).rgb * 2.0 - 1.0;
		float3 max_color = texture(colortex2, pos).rgb * 2.0 - 1.0;

		bool history_clipped;
		history_color = rgb_to_ycocg(history_color);
		history_color
			= clip_aabb(history_color, min_color, max_color, history_clipped);
		float flicker_reduction = history_clipped
			? 0.0
			: get_flicker_reduction(history_color, min_color, max_color);
		history_color = ycocg_to_rgb(history_color);

		alpha *= pow(confidence, TAAU_CONFIDENCE_REJECTION);
		alpha *= 1.0 - TAAU_FLICKER_REDUCTION * flicker_reduction;
		*/
	}

	// Offcenter rejection from Jessie, which is originally by Zombye
	// Reduces blur in motion
	float2 pixel_offset = 1.0
		- abs(2.0 * fract(float2(ap.game.renderSize) * ncoord_prev) - 1.0);
	float offcenter_rejection
		= sqrt(pixel_offset.x * pixel_offset.y) * TAA_OFFCENTER_REJECTION
		+ (1.0 - TAA_OFFCENTER_REJECTION);

	alpha = 1.0 - alpha;
	alpha *= offcenter_rejection;
	alpha = 1.0 - alpha;

	current_color = lerp(history_color, current_color, alpha);
	current_color = reinhard_inverse(current_color);

	tex_taa_output_current[icoord]
		= float4(current_color, pixel_age * offcenter_rejection);
}


