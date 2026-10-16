shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// SubViewport texture RGB is premultiplied and is consumed directly.
uniform sampler2D source_texture : filter_linear, repeat_disable;
uniform vec4 layer_colors[4] : source_color;
uniform int layer_count = 2;
uniform vec2 layer_step = vec2(7.0, 3.5);
uniform bool preserve_source_color = true;
uniform vec4 front_tint : source_color = vec4(1.0);
varying vec4 item_tint;
void vertex() { item_tint = COLOR; }
vec4 source_at(vec2 uv) {
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) return vec4(0.0);
	return texture(source_texture, uv);
}
vec4 over(vec4 front, vec4 back) { return front + back * (1.0 - front.a); }
void fragment() {
	vec4 result = vec4(0.0);
	// At most 4 bands, 25 taps each, with <=1 source-pixel spacing for continuous coverage.
	int samples = min(24, int(ceil(length(layer_step))));
	for (int layer = 3; layer >= 0; layer--) {
		if (layer >= layer_count || samples == 0) continue;
		float coverage = 0.0;
		for (int tap = 0; tap <= 24; tap++) {
			if (tap > samples) break;
			float distance_along = float(layer) + float(tap) / float(samples);
			coverage = max(coverage, source_at(UV - layer_step * distance_along * TEXTURE_PIXEL_SIZE).a);
		}
		vec4 tint = layer_colors[layer];
		float alpha = coverage * tint.a;
		result = over(vec4(tint.rgb * alpha, alpha), result);
	}
	vec4 front = source_at(UV);
	if (!preserve_source_color) front = vec4(front_tint.rgb * front.a * front_tint.a, front.a * front_tint.a);
	result = over(front, result);
	COLOR = vec4(result.rgb * item_tint.rgb * item_tint.a, result.a * item_tint.a);
}
