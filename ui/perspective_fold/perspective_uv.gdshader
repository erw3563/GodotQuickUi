shader_type canvas_item;
render_mode unshaded;
varying vec3 uvq;
varying vec4 canvas_tint;
uniform vec4 perspective_weights = vec4(1.0);
uniform vec4 panel_tint : source_color = vec4(1.0);
uniform bool textured = false;
void vertex() {
 float q = perspective_weights[VERTEX_ID];
 uvq = vec3(UV * q, q);
 canvas_tint = COLOR;
}
void fragment() {
 vec2 p = uvq.xy / max(uvq.z, 0.00001);
 COLOR = canvas_tint * panel_tint * (textured ? texture(TEXTURE, p) : vec4(1.0));
}
