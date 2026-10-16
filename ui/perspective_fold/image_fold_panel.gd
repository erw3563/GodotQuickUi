@tool
class_name ImageFoldPanel
extends Control
## A planar perspective-projected quad. 0 = folded angle, 1 = flat.
## Input bounds stay rectangular; parent clip_contents clips projected overflow.
enum Hinge { LEFT, RIGHT, TOP, BOTTOM }
@export var front_texture: Texture2D:
 set(v): front_texture=v; queue_redraw()
@export var back_texture: Texture2D:
 set(v): back_texture=v; queue_redraw()
@export var front_tint := Color.WHITE:
 set(v): front_tint=v; queue_redraw()
@export var back_tint := Color("afc44c"):
 set(v): back_tint=v; queue_redraw()
@export var hinge: Hinge = Hinge.LEFT:
 set(v): hinge=v; queue_redraw()
@export_range(0,1) var fold_progress := 1.0:
 set(v): fold_progress=clampf(v,0,1); queue_redraw()
@export_range(-170,170) var folded_angle := 145.0:
 set(v): folded_angle=clampf(v,-170,170); queue_redraw()
@export_range(0.6,8) var perspective := 2.5:
 set(v): perspective=maxf(v,0.6); queue_redraw()
@export var cull_backface := false:
 set(v): cull_backface=v; queue_redraw()
@export var mirror_back_uv := true:
 set(v): mirror_back_uv=v; queue_redraw()
@export var source_region := Rect2(0,0,1,1):
 set(v): source_region=v; queue_redraw()
const UV_SHADER = preload("res://addons/gdbase/ui/perspective_fold/perspective_uv.gdshader")
var _own_material: ShaderMaterial
func _ready() -> void:
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 resized.connect(queue_redraw)
 _own_material=ShaderMaterial.new()
 _own_material.shader=UV_SHADER
 material=_own_material
 queue_redraw()
func hinge_point() -> Vector2:
 match hinge:
  Hinge.RIGHT: return Vector2(size.x,size.y*.5)
  Hinge.TOP: return Vector2(size.x*.5,0)
  Hinge.BOTTOM: return Vector2(size.x*.5,size.y)
 return Vector2(0,size.y*.5)
func geometry() -> Dictionary:
 var theta=deg_to_rad(folded_angle*(1.0-fold_progress))
 var cs=cos(theta)
 var sn=sin(theta)
 var pivot=hinge_point()
 var distance=maxf(size.x,size.y)*perspective
 var result={"points":PackedVector2Array(),"q":PackedFloat32Array(),"back":cs<0.0,"visible":true}
 if size.x<=0 or size.y<=0 or absf(cs)<0.00001 or (cull_backface and cs<0):
  result.visible=false
  return result
 for p in [Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)]:
  var local: Vector2=p-pivot
  var z: float
  if hinge==Hinge.LEFT or hinge==Hinge.RIGHT:
   z=local.x*sn; local.x*=cs
  else:
   z=local.y*sn; local.y*=cs
  var denominator=distance+z
  if denominator<=distance*.05:
   result.visible=false
   return result
  var q=distance/denominator
  result.points.append(pivot+local*q)
  result.q.append(q)
 return result
func _draw() -> void:
 if not _own_material: return
 var g=geometry()
 if not g.visible: return
 var tex=back_texture if g.back else front_texture
 _own_material.set_shader_parameter("textured",tex!=null)
 _own_material.set_shader_parameter("panel_tint",back_tint if g.back else front_tint)
 var uv=PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)])
 if g.back and mirror_back_uv:
  for i in range(4): uv[i].x=1.0-uv[i].x
 for i in range(4): uv[i]=source_region.position+uv[i]*source_region.size
 var weights: PackedFloat32Array = g.q
 _own_material.set_shader_parameter("perspective_weights", Vector4(weights[0], weights[1], weights[2], weights[3]))
 draw_polygon(g.points,PackedColorArray([Color.WHITE]),uv,tex)
