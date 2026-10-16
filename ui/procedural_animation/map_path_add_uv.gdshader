shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec2 uv_offset = vec2(0.0);
uniform bool repeat_u = true;
uniform bool repeat_v = false;
varying vec4 vertex_color;

void vertex() {
	vertex_color = COLOR;
}

void fragment() {
	vec2 sample_uv = UV + uv_offset;
	if (repeat_u) { sample_uv.x = fract(sample_uv.x); }
	if (repeat_v) { sample_uv.y = fract(sample_uv.y); }
	COLOR = texture(TEXTURE, sample_uv) * vertex_color;
}
