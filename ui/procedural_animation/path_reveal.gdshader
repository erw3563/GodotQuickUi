shader_type canvas_item;
render_mode unshaded;
uniform float reveal_progress : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint : source_color = vec4(0.05, 0.85, 1.0, 1.0);
uniform float feather = 0.002;
uniform float pattern_speed = 0.0;
uniform float pattern_strength = 0.12;
void fragment() {
    // UV.x stores the normalized longitudinal arc length of the ribbon.
    float s = UV.x;
    if (reveal_progress <= 0.0 || s > reveal_progress) { discard; }
    float mask = 1.0;
    if (reveal_progress < 1.0 && feather > 0.0) {
        mask = smoothstep(0.0, feather, reveal_progress - s);
    }
    float stripe = step(0.5, fract(s * 19.0 + UV.y * 0.5 - TIME * pattern_speed));
    COLOR *= vec4(tint.rgb * (1.0 - stripe * pattern_strength), tint.a * mask);
}
