shader_type canvas_item;
render_mode unshaded;

uniform sampler2D source_image : filter_linear, repeat_disable;
uniform sampler2D mask_image : filter_linear, repeat_disable;
uniform bool has_source = false;
uniform bool has_mask = false;
uniform bool effect_enabled = true;
uniform bool source_premultiplied = false;
uniform vec4 replacement_color : source_color = vec4(1.0, 0.02, 0.11, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform vec2 output_size = vec2(1.0);
uniform vec2 mask_position = vec2(0.5);
uniform vec2 mask_size = vec2(1.0);
uniform float mask_rotation = 0.0;
varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
}

void fragment() {
	vec4 source = texture(source_image, UV);
	if (source_premultiplied) {
		source.rgb = source.a > 0.000001 ? source.rgb / source.a : vec3(0.0);
	}
	vec2 pixel = (UV - mask_position) * output_size;
	float c = cos(mask_rotation);
	float s = sin(mask_rotation);
	vec2 local = vec2(c * pixel.x + s * pixel.y, -s * pixel.x + c * pixel.y);
	vec2 mask_uv = local / max(output_size * mask_size, vec2(0.0001)) + vec2(0.5);
	float inside = step(0.0, mask_uv.x) * step(mask_uv.x, 1.0) * step(0.0, mask_uv.y) * step(mask_uv.y, 1.0);
	float coverage = texture(mask_image, mask_uv).a * inside * strength * replacement_color.a;
	if (!effect_enabled || !has_mask) { coverage = 0.0; }
	// Mask alpha weights RGB replacement; source alpha owns output coverage.
	COLOR = vec4(mix(source.rgb, replacement_color.rgb, coverage), source.a) * item_modulate;
	if (!has_source) { COLOR = vec4(0.0); }
}
