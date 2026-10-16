shader_type canvas_item;
render_mode unshaded;
uniform vec2 control_size = vec2(1120.0, 430.0);
uniform bool source_is_premultiplied = false;
uniform bool source_available = false;
uniform float progress = 0.0;
uniform float band_direction = 3.14159265;
uniform float band_width = 260.0;
uniform float edge_softness = 30.0;
uniform float rib_frequency = 112.0;
uniform float rib_angle = 0.0;
uniform float refraction_amplitude = 16.0;
varying vec4 canvas_tint;
void vertex() { canvas_tint = COLOR; }
void fragment() {
    vec2 p = (UV - vec2(0.5)) * control_size;
    vec2 travel = vec2(cos(band_direction), sin(band_direction));
    float extent = dot(abs(travel), control_size) * 0.5;
    float half_width = band_width * 0.5;
    float center = mix(-extent - half_width, extent + half_width, progress);
    float distance_to_band = abs(dot(p, travel) - center);
    float softness = min(edge_softness, half_width);
    float influence = softness > 0.001 ? 1.0 - smoothstep(half_width - softness, half_width, distance_to_band) : 1.0 - step(half_width, distance_to_band);
    // At either endpoint the original texture is an exact identity, even at its edge.
    if (progress <= 0.0 || progress >= 1.0 || refraction_amplitude <= 0.0 || rib_frequency <= 0.0) influence = 0.0;
    vec2 normal = vec2(cos(rib_angle), sin(rib_angle));
    float wave = sin(dot(p, normal) * rib_frequency * 0.00628318530718);
    vec2 shift = normal * wave * refraction_amplitude * influence / max(control_size, vec2(1.0));
    vec2 sample_uv = UV + shift;
    // Preserve transparent coverage beyond the actual input image.
    vec4 displaced = texture(TEXTURE, clamp(sample_uv, vec2(0.0), vec2(1.0)));
    if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) displaced = vec4(0.0);
    if (source_is_premultiplied) {
        displaced.rgb = displaced.a > 0.000001 ? displaced.rgb / displaced.a : vec3(0.0);
    }
    COLOR = source_available ? displaced * canvas_tint : vec4(0.0);
}
