shader_type canvas_item;
render_mode unshaded;
// Original geometric lettering expressed as analytic intervals.
// Each horizontal scanline is a union of intervals. Extending the intervals
// gives exact continuous horizontal dilation, at constant cost regardless of length.
uniform vec2 canvas_size = vec2(450.0,600.0);
uniform float seconds = 1.6;
uniform vec4 front_color : source_color = vec4(0.93,0.93,0.92,1.0);
uniform vec4 middle_color : source_color = vec4(0.60,0.20,0.98,1.0);
uniform vec4 back_color : source_color = vec4(0.08,1.0,0.35,1.0);
uniform float motion_scale = 1.0;
float band(float x,float a,float b,float extension,float aa) {
 return smoothstep(a-aa,a+aa,x)*(1.0-smoothstep(b+extension-aa,b+extension+aa,x));
}
float edge(float y,float w,float h,float r) {
 float q=max(abs(y-h*0.5)-(h*0.5-r),0.0);
 return w*0.5-r+sqrt(max(r*r-q*q,0.0));
}
float letter(vec2 p,int kind,float extension,float aa) {
 float w=76.0,h=220.0,stroke=24.0;
 if(p.y < -aa || p.y > h+aa) return 0.0;
 float vertical=smoothstep(-aa,aa,p.y)*(1.0-smoothstep(h-aa,h+aa,p.y));
 float x=p.x-w*0.5;
 if(kind==4) { // L
  return max(band(x,-38.0,-14.0,extension,aa),band(x,-38.0,38.0,extension,aa)*smoothstep(194.0-aa,194.0+aa,p.y))*vertical;
 }
 if(kind==7) { // K: continuous sloping arms and spine
  float arm= -8.0+abs(p.y-110.0)*0.37;
  return max(band(x,-38.0,-14.0,extension,aa),band(x,arm-13.0,arm+13.0,extension,aa))*vertical;
 }
 float outer=edge(p.y,w,h,kind==3?30.0:34.0);
 float a=-outer,b=outer;
 if(kind==3) a=-38.0; // D straight spine
 float result=0.0;
 bool inside_hole=p.y>stroke && p.y<h-stroke;
 if(kind==5 && p.y<stroke) inside_hole=true; // U open top
 if(inside_hole) {
  float inner=14.0;
  if(kind!=5 || p.y>stroke) inner=edge(p.y-stroke,28.0,h-2.0*stroke,12.0);
  result=band(x,a,-inner,extension,aa);
  bool right_visible=true;
  if(kind==6 && p.y>48.0 && p.y<172.0) right_visible=false; // C
  if(kind==0 && p.y>48.0 && p.y<108.0) right_visible=false; // G
  if(right_visible) result=max(result,band(x,inner,b,extension,aa));
  if(kind==0 && p.y>=104.0 && p.y<=128.0) result=max(result,band(x,-1.0,b,extension,aa));
 } else {
  result=band(x,a,b,extension,aa);
 }
 return result*vertical;
}
float field(vec2 p,float t,int layer,float aa) {
 float delay=float(layer)*0.065;
 float q=max(t-delay,0.0);
 float settle=smoothstep(0.42,1.30,q);
 float extension=mix(260.0,0.0,settle);
 // A second authored stretch at 2.7 seconds, then a separate forward exit.
 float pulse=smoothstep(2.60,2.83,q)*(1.0-smoothstep(2.83,3.30,q));
 extension+=pulse*150.0;
 float gap=16.0;
 float front_extent=mix(260.0,0.0,smoothstep(0.42,1.30,t));
 front_extent+=smoothstep(2.60,2.83,t)*(1.0-smoothstep(2.83,3.30,t))*150.0;
 extension=max(extension,front_extent); // delayed release cannot overtake the front
 float pitch=76.0+gap+front_extent;
 float travel=mix(-8.0*pitch-100.0,-135.0,smoothstep(0.15,0.95,t));
 travel-=max(q-1.3,0.0)*15.0;
 travel+=smoothstep(3.65,4.45,q)*1550.0;
 p.x-=travel+float(layer)*mix(25.0,1.5,smoothstep(0.42,1.30,t));
 p.x+=mod(floor(p.y/234.0),2.0)*48.0;
 int row=int(mod(floor(p.y/234.0),2.0));
 p.y=mod(p.y,234.0);
 // Fixed finite field: 8 glyphs per row, deliberately oversized poster crop.
 float coverage=0.0;
 for(int i=0;i<8;i++) {
  int index=i%4;
  int kind=index;
  if(row==0) kind=index==0?0:(index==3?3:1); // GOOD
  else kind=4+index; // LUCK
  coverage=max(coverage,letter(vec2(p.x-float(i)*pitch,p.y),kind,extension,aa));
 }
 return coverage*smoothstep(0.0,0.05,q);
}
void fragment() {
 vec2 p=UV*canvas_size;
 float angle=0.44*smoothstep(0.12,0.90,seconds)*motion_scale;
 vec2 center=canvas_size*0.5;
 p-=center;
 p=mat2(vec2(cos(angle),-sin(angle)),vec2(sin(angle),cos(angle)))*p;
 p+=center+vec2(0.0,132.0);
 float aa=max(fwidth(p.x),fwidth(p.y))*0.6;
 vec4 result=vec4(0.0);
 for(int layer=2;layer>=0;layer--) {
  float a=field(p,seconds,layer,aa);
  vec4 tint=layer==0?front_color:(layer==1?middle_color:back_color);
  result=mix(result,vec4(tint.rgb,1.0),a*tint.a);
 }
 COLOR=result;
}
