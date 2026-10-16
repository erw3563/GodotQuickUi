shader_type canvas_item;
render_mode unshaded;
uniform sampler2D source_a : filter_linear, repeat_disable;
uniform sampler2D source_b : filter_linear, repeat_disable;
uniform bool premultiplied_a = true;
uniform bool premultiplied_b = true;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float fold_span : hint_range(0.05, 0.95) = 0.70;
uniform float bend : hint_range(-0.2, 0.2) = 0.025;
uniform bool reverse_direction = false;
uniform bool swap_inputs = false;
varying vec4 canvas_tint;
void vertex() { canvas_tint = COLOR; }
vec4 clean_sample(vec2 uv, bool use_b) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { return vec4(0.0); }
	vec4 color;
	bool premultiplied;
	if (use_b) { color = texture(source_b, uv); premultiplied = premultiplied_b; }
	else { color = texture(source_a, uv); premultiplied = premultiplied_a; }
	if (color.a <= 0.00001) { return vec4(0.0); }
	if (premultiplied) { color.rgb /= color.a; }
	return color;
}
void fragment() {
	vec4 result;
	if (progress <= 0.0) { result = clean_sample(UV, swap_inputs); }
	else if (progress >= 1.0) { result = clean_sample(UV, !swap_inputs); }
	else {
		float x = reverse_direction ? 1.0 - UV.x : UV.x;
		float local_phase = clamp((progress - x * fold_span) / (1.0 - fold_span), 0.0, 1.0);
		float smooth_phase = local_phase * local_phase * (3.0 - 2.0 * local_phase);
		float squash = abs(cos(3.14159265359 * smooth_phase));
		float center = 0.5 + bend * sin(6.28318530718 * smooth_phase);
		vec2 sample_uv = vec2(UV.x, (UV.y - center) / max(squash, 0.001) + 0.5);
		bool use_b = (local_phase >= 0.5) != swap_inputs;
		result = clean_sample(sample_uv, use_b);
		// Collapse continuously to zero coverage, with finite sampling at the seam.
		result.a *= smoothstep(0.0, 0.008, squash);
	}
	COLOR = result * canvas_tint;
	if (COLOR.a <= 0.00001) { COLOR = vec4(0.0); }
}
