shader_type canvas_item;
render_mode unshaded;
uniform vec2 control_size = vec2(600.0, 400.0);
uniform vec2 center_ratio = vec2(0.5);
uniform int sector_count = 2;
uniform float aperture = 0.70;
uniform float angle = 0.0;
uniform float inner_radius = 0.0;
uniform float outer_radius = 780.0;
uniform vec4 sector_color : source_color = vec4(0.02, 0.70, 0.73, 1.0);
uniform vec4 alternate_color : source_color = vec4(0.02, 0.70, 0.73, 1.0);
uniform bool alternate_colors = false;
void fragment() {
    vec2 p = (UV - center_ratio) * control_size;
    float r = length(p);
    float count = float(max(sector_count, 1));
    float spacing = TAU / count;
    float theta = atan(p.y, p.x) - angle;
    float local = mod(theta + spacing * 0.5, spacing) - spacing * 0.5;
    float aa = max(fwidth(r) * 0.6, 0.45);
    float radial = (inner_radius <= 0.0 ? 1.0 : smoothstep(inner_radius - aa, inner_radius + aa, r)) * (1.0 - smoothstep(outer_radius - aa, outer_radius + aa, r));
    float angular = aperture >= spacing ? 1.0 : 1.0 - smoothstep(-aa, aa, (abs(local) - aperture * 0.5) * r);
    float id = mod(floor((theta + spacing * 0.5) / spacing), count);
    vec4 tint = (alternate_colors && mod(id, 2.0) > 0.5) ? alternate_color : sector_color;
    float enabled = (sector_count > 0 && aperture > 0.0 && outer_radius > inner_radius) ? 1.0 : 0.0;
    COLOR = COLOR * tint * vec4(1.0, 1.0, 1.0, radial * angular * enabled);
}
