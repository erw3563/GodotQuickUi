shader_type canvas_item;
render_mode unshaded;

uniform int cell_count = 0;
uniform vec2 centers[8];
uniform float radii[8];
uniform float join_strength : hint_range(0.0, 1.0) = 0.0;
uniform float connection_range = 260.0;
uniform float neck_radius = 0.0;
uniform float surface_softness = 0.0;
uniform vec4 fill_color : source_color = vec4(0.07, 0.78, 0.82, 1.0);
uniform vec4 outline_color : source_color = vec4(1.0);
uniform float outline_width = 0.0;
uniform float opacity = 1.0;
varying vec2 local_point;

void vertex() {
	local_point = VERTEX;
}

float soft_union(float a, float b, float k) {
	if (k <= 0.00001) { return min(a, b); }
	float h = max(k - abs(a - b), 0.0) / k;
	return min(a, b) - h * h * k * 0.25;
}

void fragment() {
	vec4 canvas_tint = COLOR;
	float distances[8];
	float field = 1.0e20;
	for (int i = 0; i < 8; i++) {
		distances[i] = 1.0e20;
		if (i < cell_count) {
			distances[i] = length(local_point - centers[i]) - radii[i];
			field = min(field, distances[i]);
		}
	}
	for (int a = 0; a < 8; a++) {
		if (a >= cell_count) { break; }
		for (int b = a + 1; b < 8; b++) {
			if (b >= cell_count) { break; }
			float gap = max(0.0, distance(centers[a], centers[b]) - radii[a] - radii[b]);
			if (gap <= connection_range) {
				float k = join_strength * (2.0 * gap + 4.0 * neck_radius) + surface_softness;
				field = min(field, soft_union(distances[a], distances[b], k));
			}
		}
	}
	// Derivatives keep edge coverage in screen pixels through Canvas transforms.
	float aa = max(fwidth(field) * 0.65, 0.0001);
	float fill_alpha = fill_color.a * (1.0 - smoothstep(-aa, aa, field));
	float line_alpha = 0.0;
	if (outline_width > 0.0) {
		line_alpha = outline_color.a * (1.0 - smoothstep(outline_width * 0.5 - aa, outline_width * 0.5 + aa, abs(field)));
	}
	float alpha = line_alpha + fill_alpha * (1.0 - line_alpha);
	vec3 premultiplied = outline_color.rgb * line_alpha + fill_color.rgb * fill_alpha * (1.0 - line_alpha);
	vec3 rgb = premultiplied / max(alpha, 0.00001);
	COLOR = vec4(rgb, alpha * opacity) * canvas_tint;
}
