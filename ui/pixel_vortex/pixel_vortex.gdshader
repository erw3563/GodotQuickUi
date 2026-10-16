shader_type canvas_item;
render_mode unshaded;

uniform float openness : hint_range(0.0, 1.0) = 1.0;
uniform float swirl_speed : hint_range(0.0, 4.0) = 0.85;
uniform float pixel_count : hint_range(24.0, 128.0) = 64.0;
uniform vec4 core_color : source_color = vec4(0.035, 0.027, 0.055, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.16, 0.125, 0.22, 1.0);
uniform vec4 spiral_color : source_color = vec4(0.39, 0.30, 0.51, 1.0);
uniform vec4 rim_color : source_color = vec4(0.66, 0.55, 0.71, 1.0);

void fragment() {
 vec2 p = (floor(UV * pixel_count) + 0.5) / pixel_count * 2.0 - 1.0;
 float r = length(p);
 float a = atan(p.y, p.x);
 float t = TIME * swirl_speed;
 float open = clamp(openness, 0.0, 1.0);
 // The solid circular cover encloses the square target even while the swirl is closed.
 float cover = 1.0 - step(0.76, r);
 float radius = 0.11 + 0.75 * open;
 float edge = radius + sin(a * 5.0 + t * 0.9) * 0.018 * open;
 float disk = 1.0 - step(edge, r);
 float depth = clamp(r / max(radius, 0.001), 0.0, 1.0);
 float winding = a * 3.0 + log(max(r, 0.025)) * 8.5 + t * 3.0;
 float ribbon = sin(winding + sin(a * 2.0 - t) * 0.35);
 float stripe = step(0.22, ribbon) * step(0.20, depth);
 float highlight = step(0.84, ribbon) * step(0.48, depth);
 vec3 ink = mix(core_color.rgb, shadow_color.rgb, step(0.27, depth) * 0.8);
 ink = mix(ink, spiral_color.rgb, stripe * (0.40 + depth * 0.4));
 ink = mix(ink, rim_color.rgb, highlight * (0.30 + depth * 0.25));
 ink = mix(core_color.rgb, ink, smoothstep(0.10, 0.30, depth));
 float lip = step(edge - 0.04, r) * disk;
 float lip_light = step(0.2, sin(a * 3.0 + t * 0.8));
 ink = mix(ink, mix(shadow_color.rgb, spiral_color.rgb, lip_light), lip);
 vec3 color = mix(core_color.rgb, ink, disk * smoothstep(0.0, 0.18, open));
 // A quiet stepped stone edge makes the closed state a covered socket.
 float cover_edge = cover * step(0.72, r);
 color = mix(color, shadow_color.rgb * 0.8, cover_edge * (1.0 - disk));
 float mote_phase = fract(r * 2.5 + t * 0.38);
 float motes = step(0.987, sin(a * 13.0 + r * 17.0 + t)) * step(0.73, r) * (1.0 - step(0.96, r)) * step(0.72, mote_phase) * open;
 color = mix(color, rim_color.rgb, motes);
 COLOR = vec4(color, max(max(cover, disk), motes));
}
