shader_type canvas_item;
render_mode unshaded;
uniform sampler2D source_a : filter_linear, repeat_disable;
uniform sampler2D source_b : filter_linear, repeat_disable;
uniform bool premultiplied_a = true;
uniform bool premultiplied_b = true;
uniform float progress = 0.0;
uniform int band_count = 20;
uniform float stagger = 0.70;
uniform bool reverse_stagger = false;
uniform bool reverse_rotation = false;
uniform bool swap_inputs = false;
uniform float shading = 0.22;
uniform float display_width = 560.0;
varying vec4 canvas_tint;
void vertex() {
	canvas_tint = COLOR;
	// Expand geometry around the artwork to cover rotating cube corners.
	VERTEX.x = (VERTEX.x - display_width * 0.5) * 1.42 + display_width * 0.5;
}
vec4 sample_face(vec2 uv, bool incoming) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { return vec4(0.0); }
	bool use_b = incoming != swap_inputs;
	vec4 result;
	bool premultiplied;
	if (use_b) { result = texture(source_b, uv); premultiplied = premultiplied_b; }
	else { result = texture(source_a, uv); premultiplied = premultiplied_a; }
	if (result.a <= 0.00001) { return vec4(0.0); }
	if (premultiplied) { result.rgb /= result.a; }
	return result;
}
void fragment() {
	float x = (UV.x - 0.5) * 1.42;
	vec4 result = vec4(0.0);
	if (progress <= 0.0) { result = sample_face(vec2(x + 0.5, UV.y), false); }
	else if (progress >= 1.0) { result = sample_face(vec2(x + 0.5, UV.y), true); }
	else {
		float band = min(floor(UV.y * float(band_count)), float(band_count - 1));
		float order = band_count > 1 ? band / float(band_count - 1) : 0.0;
		if (reverse_stagger && band_count > 1) { order = 1.0 - order; }
		float delay = band_count > 1 ? stagger : 0.0;
		float phase = clamp((progress - order * delay) / (1.0 - delay), 0.0, 1.0);
		phase = phase * phase * (3.0 - 2.0 * phase);
		float angle = phase * 1.57079632679;
		float c = cos(angle);
		float s = sin(angle);
		float rx = reverse_rotation ? -x : x;
		float edge = (s - c) * 0.5;
		bool incoming = rx < edge;
		float u;
		float facing;
		if (incoming) {
			u = (rx + 0.5 * c) / max(s, 0.00001) + 0.5;
			facing = s;
		} else {
			u = (rx - 0.5 * s) / max(c, 0.00001) + 0.5;
			facing = c;
		}
		if (reverse_rotation) { u = 1.0 - u; }
		result = sample_face(vec2(u, UV.y), incoming);
		result.rgb *= 1.0 - shading * (1.0 - facing);
		// Suppress numerical ghost faces at exactly edge-on angles.
		if (facing < 0.00001) { result = vec4(0.0); }
	}
	COLOR = result * canvas_tint;
	if (COLOR.a <= 0.00001) { COLOR = vec4(0.0); }
}
