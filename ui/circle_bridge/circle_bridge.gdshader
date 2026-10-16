shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
uniform sampler2D source_a : filter_linear, repeat_disable;
uniform sampler2D source_b : filter_linear, repeat_disable;
uniform bool has_a = false;
uniform bool has_b = false;
uniform bool a_premultiplied = false;
uniform bool b_premultiplied = false;
uniform vec2 extent = vec2(1.0);
uniform vec2 anchor_a = vec2(0.5);
uniform vec2 anchor_b = vec2(0.5);
uniform float radius_a = 100.0;
uniform float radius_b = 100.0;
uniform float match_strength = 1.0;
uniform float match_falloff = 128.0;
uniform float progress = 0.0;
uniform float feather = 1.0;
uniform bool invert = false;
varying vec2 local_position;
void vertex() { local_position = VERTEX; }
vec4 sample_input(sampler2D tex, vec2 uv, bool present, bool premultiplied) {
 if (!present || any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) { return vec4(0.0); }
 vec4 c = texture(tex, uv);
 if (!premultiplied) { c.rgb *= c.a; }
 return c;
}
vec2 matched_point(vec2 point, vec2 center, float target_radius, vec2 source_center, float source_radius) {
 vec2 offset = point - center;
 float radius = length(offset);
 if (radius < 0.00001) { return source_center; }
 vec2 direction = offset / radius;
 float outer = max(target_radius, source_radius + length(source_center-center)) + match_falloff;
 // Keep the annulus inside the output boundary when the target landmark fits.
 if (all(greaterThanEqual(center,vec2(0.0))) && all(lessThanEqual(center,extent))) {
  vec2 remaining = mix(-center,extent-center,greaterThan(direction,vec2(0.0)));
  vec2 ray = remaining / (direction + vec2(0.0000001));
  float edge = min(abs(ray.x),abs(ray.y));
  if (edge > target_radius + 0.001) { outer = min(outer,edge); }
 }
 if (radius >= outer) { return point; }
 if (radius <= target_radius) { return source_center + offset*source_radius/target_radius; }
 float t = (radius-target_radius)/max(outer-target_radius,0.00001);
 return mix(source_center,center,t) + direction*mix(source_radius,outer,t);
}
void fragment() {
 vec2 c_a = anchor_a * extent;
 vec2 c_b = anchor_b * extent;
 vec2 center = mix(c_a, c_b, progress);
 float anchor_radius = mix(radius_a, radius_b, progress);
 vec2 uv_a = mix(local_position, matched_point(local_position,center,anchor_radius,c_a,radius_a), match_strength) / extent;
 vec2 uv_b = mix(local_position, matched_point(local_position,center,anchor_radius,c_b,radius_b), match_strength) / extent;
 // A circle uses local pixels and preserves its aspect on non-square output.
 float coverage = max(max(length(center), length(vec2(extent.x,0.0)-center)), max(length(vec2(0.0,extent.y)-center), length(extent-center))) + feather;
 float radial_progress = invert ? 1.0 - progress : progress;
 float radius = mix(-feather, coverage, radial_progress);
 float distance_to_edge = length(local_position-center)-radius;
 float inside = 1.0-smoothstep(-max(feather,0.0001), max(feather,0.0001), distance_to_edge);
 float mask = invert ? 1.0-inside : inside;
 // Exact endpoints, even for oversized feather, alpha, missing inputs, and off-canvas anchors.
 if (progress <= 0.0) { mask = 0.0; uv_a = local_position / extent; }
 if (progress >= 1.0) { mask = 1.0; uv_b = local_position / extent; }
 vec4 a = sample_input(source_a, uv_a, has_a, a_premultiplied);
 vec4 b = sample_input(source_b, uv_b, has_b, b_premultiplied);
 vec4 result = mix(a,b,mask);
 vec4 tint = COLOR;
 COLOR = vec4(result.rgb*tint.rgb*tint.a,result.a*tint.a);
}
