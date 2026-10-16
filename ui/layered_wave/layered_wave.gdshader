shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
uniform sampler2D source_a : filter_linear, repeat_disable;
uniform sampler2D source_b : filter_linear, repeat_disable;
uniform bool has_a = false;
uniform bool has_b = false;
uniform bool a_premultiplied = false;
uniform bool b_premultiplied = false;
uniform vec2 extent = vec2(1.0);
uniform vec2 sweep_direction = vec2(0.0,-1.0);
uniform float amplitude = 34.0;
uniform float frequency = 1.35;
uniform float phase = 0.35;
uniform float phase_travel = 1.4;
uniform float softness = 1.0;
uniform float progress = 0.0;
uniform float opacity = 1.0;
uniform int band_count = 0;
uniform float band_widths[8];
uniform vec4 band_colors[8] : source_color;
uniform float total_width = 0.0;
varying vec2 local_position;
void vertex() { local_position = VERTEX; }
vec4 sample_input(sampler2D tex,vec2 uv,bool present,bool premultiplied) {
 if (!present) { return vec4(0.0); }
 vec4 c=texture(tex,uv);
 if (!premultiplied) { c.rgb*=c.a; }
 return c;
}
vec2 bounds(vec2 axis) {
 vec2 sides=axis*extent;
 return vec2(min(0.0,sides.x)+min(0.0,sides.y),max(0.0,sides.x)+max(0.0,sides.y));
}
void fragment() {
 vec2 uv=local_position/extent;
 vec4 a=sample_input(source_a,uv,has_a,a_premultiplied);
 vec4 b=sample_input(source_b,uv,has_b,b_premultiplied);
 vec4 result;
 // Explicit endpoints guarantee original images for any wave/band/alpha settings.
 if (progress<=0.0) { result=a; }
 else if (progress>=1.0) { result=b; }
 else {
  vec2 along=bounds(sweep_direction);
  vec2 tangent=vec2(-sweep_direction.y,sweep_direction.x);
  vec2 across=bounds(tangent);
  float t=(dot(local_position,tangent)-across.x)/max(across.y-across.x,1.0);
  float wave=amplitude*sin(t*6.28318530718*frequency+phase+phase_travel*progress);
  float margin=amplitude+softness+1.0;
  float front=mix(along.x-margin,along.y+total_width+margin,progress);
  float d=front+wave-dot(local_position,sweep_direction);
  float edge=max(softness,0.0001);
  float previous=smoothstep(-edge,edge,d);
  result=a*(1.0-previous);
  float offset=0.0;
  for (int i=0;i<8;i++) {
   if(i>=band_count) { break; }
   offset+=band_widths[i];
   float next=smoothstep(-edge,edge,d-offset);
   vec4 c=band_colors[i];
   c.rgb*=c.a;
   result+=c*max(0.0,previous-next);
   previous=next;
  }
  result+=b*previous;
 }
 vec4 tint=COLOR;
 COLOR=vec4(result.rgb*tint.rgb*tint.a,result.a*tint.a)*opacity;
}
