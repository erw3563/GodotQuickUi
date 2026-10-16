@tool
class_name CircleBridge
extends Control
## Two isolated images, one matched circular landmark, and a true circular reveal.
## Inputs are image textures or separately authored SubViewport textures.
## The scene author retains ownership of both input scenes.
signal progress_changed(value: float)
signal completed(value: float)
const EFFECT = preload("res://addons/gdbase/ui/circle_bridge/circle_bridge.gdshader")

@export_group("Isolated Inputs")
@export var source_a: Texture2D:
 set(value):
  source_a = value
  _sync()
@export var source_b: Texture2D:
 set(value):
  source_b = value
  _sync()
## SubViewport transparent render targets already contain premultiplied RGB.
@export var source_a_premultiplied := false:
 set(value):
  source_a_premultiplied = value
  _sync()
@export var source_b_premultiplied := false:
 set(value):
  source_b_premultiplied = value
  _sync()

@export_group("Matched Circular Landmark")
## Landmark centers in normalized source/output space; radii are local pixels.
@export var from_center := Vector2(0.5,0.5):
 set(value):
  if value.is_finite():
   from_center = value.clamp(Vector2(-8,-8),Vector2(8,8))
   _sync()
@export var to_center := Vector2(0.5,0.5):
 set(value):
  if value.is_finite():
   to_center = value.clamp(Vector2(-8,-8),Vector2(8,8))
   _sync()
@export_range(0.001,16384,0.1,"or_greater") var from_radius := 100.0:
 set(value):
  if is_finite(value):
   from_radius = clampf(value,0.001,1000000.0)
   _sync()
@export_range(0.001,16384,0.1,"or_greater") var to_radius := 100.0:
 set(value):
  if is_finite(value):
   to_radius = clampf(value,0.001,1000000.0)
   _sync()
## Zero disables source alignment but keeps the circular reveal.
@export_range(0,1,0.01) var match_strength := 1.0:
 set(value):
  if is_finite(value):
   match_strength = clampf(value,0,1)
   _sync()

## Local-pixel annulus reconnecting the matched landmark to unchanged input.
@export_range(1,2048,1,"or_greater") var match_falloff := 128.0:
 set(value):
  if is_finite(value):
   match_falloff = clampf(value,1,1000000)
   _sync()

@export_group("Circular Reveal")
@export_range(0,1,0.001) var progress := 0.0:
 set(value):
  if is_finite(value):
   progress = clampf(value,0,1)
   _sync()
   progress_changed.emit(progress)
@export_range(0,512,0.1,"or_greater") var feather := 1.0:
 set(value):
  if is_finite(value):
   feather = clampf(value,0,1000000)
   _sync()
@export var invert := false:
 set(value):
  invert = value
  _sync()
@export_range(0.01,120,0.01) var duration := 2.4:
 set(value):
  if is_finite(value): duration = clampf(value,0.01,120)
var playing := false
var direction := 1.0
var _owned_material: ShaderMaterial
var _transport_revision := 0

func _enter_tree() -> void:
 _sync()

func _ready() -> void:
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 if not resized.is_connected(_sync): resized.connect(_sync)
 if not visibility_changed.is_connected(_visibility): visibility_changed.connect(_visibility)
 _sync()

func _exit_tree() -> void:
 stop()

func _visibility() -> void:
 if not is_visible_in_tree(): stop()

func _process(delta: float) -> void:
 if not Engine.is_editor_hint(): advance(delta)

func advance(delta: float) -> void:
 if not playing or not is_inside_tree() or not is_visible_in_tree() or not is_finite(delta) or delta <= 0:
  return
 var revision := _transport_revision
 var next_value := clampf(progress+direction*delta/duration,0,1)
 progress = next_value
 # A synchronous progress listener may seek, hide, reverse or cancel.
 if revision != _transport_revision or not playing or not is_inside_tree() or progress != next_value:
  return
 if progress <= 0.0 or progress >= 1.0:
  playing = false
  completed.emit(progress)

func stop() -> void:
 _transport_revision += 1
 playing = false

func seek(value: float) -> void:
 if not is_finite(value): return
 stop()
 progress = value

func play_to(value: float) -> void:
 if not is_finite(value): return
 _transport_revision += 1
 var target := clampf(value,0,1)
 if not is_equal_approx(target,0.0) and not is_equal_approx(target,1.0):
  seek(target)
  return
 direction = 1.0 if target > progress else -1.0
 playing = is_inside_tree() and is_visible_in_tree() and not is_equal_approx(target,progress)

func replay() -> void:
 stop()
 var revision := _transport_revision
 progress = 0.0
 if revision == _transport_revision and progress == 0.0:
  play_to(1.0)

func reverse() -> void:
 _transport_revision += 1
 if progress <= 0: direction = 1
 elif progress >= 1: direction = -1
 else: direction = -direction
 playing = is_inside_tree() and is_visible_in_tree()

func toggle_pause() -> void:
 _transport_revision += 1
 if playing: stop()
 else:
  if progress <= 0: direction = 1
  if progress >= 1: direction = -1
  playing = is_inside_tree() and is_visible_in_tree()

func landmark() -> Vector3:
 var center := from_center.lerp(to_center,progress)*size
 return Vector3(center.x,center.y,lerpf(from_radius,to_radius,progress))

func source_uv(point: Vector2, source_is_b: bool) -> Vector2:
 if size.x <= 0 or size.y <= 0: return Vector2.ZERO
 if progress == (1.0 if source_is_b else 0.0): return point/size
 var anchor := landmark()
 var center := to_center if source_is_b else from_center
 var radius := to_radius if source_is_b else from_radius
 return point.lerp(_matched_point(point,Vector2(anchor.x,anchor.y),anchor.z,center*size,radius),match_strength)/size

func _matched_point(point:Vector2, center:Vector2, target_radius:float, source_center:Vector2, source_radius:float)->Vector2:
 var offset:=point-center
 var radius:=offset.length()
 if radius<0.00001: return source_center
 var ray_direction:=offset/radius
 var outer:=maxf(target_radius,source_radius+source_center.distance_to(center))+match_falloff
 if center.x>=0 and center.y>=0 and center.x<=size.x and center.y<=size.y:
  var ray_x:=absf(((size.x-center.x) if ray_direction.x>0 else -center.x)/(ray_direction.x+0.0000001))
  var ray_y:=absf(((size.y-center.y) if ray_direction.y>0 else -center.y)/(ray_direction.y+0.0000001))
  var edge:=minf(ray_x,ray_y)
  if edge>target_radius+0.001: outer=minf(outer,edge)
 if radius>=outer: return point
 if radius<=target_radius: return source_center+offset*source_radius/target_radius
 var t:float=(radius-target_radius)/maxf(outer-target_radius,0.00001)
 return source_center.lerp(center,t)+ray_direction*lerpf(source_radius,outer,t)

func reveal_weight(point: Vector2) -> float:
 if progress <= 0: return 0
 if progress >= 1: return 1
 var a := landmark()
 var center := Vector2(a.x,a.y)
 var cover := maxf(maxf(center.length(),(Vector2(size.x,0)-center).length()), maxf((Vector2(0,size.y)-center).length(),(size-center).length()))+feather
 var radius := lerpf(-feather,cover,1.0-progress if invert else progress)
 var width := maxf(feather,0.0001)
 var inside := 1.0-smoothstep(-width,width,point.distance_to(center)-radius)
 return 1.0-inside if invert else inside

func _sync() -> void:
 if not is_inside_tree(): return
 if _owned_material == null:
  _owned_material = ShaderMaterial.new()
  _owned_material.shader = EFFECT
  material = _owned_material
 var values := {"source_a": source_a,"source_b": source_b,"has_a": source_a!=null,"has_b": source_b!=null,
  "a_premultiplied":source_a_premultiplied,"b_premultiplied":source_b_premultiplied,
  "extent":size.max(Vector2.ONE),"anchor_a":from_center,"anchor_b":to_center,
  "radius_a":from_radius,"radius_b":to_radius,"match_strength":match_strength,
  "progress":progress,"feather":feather,"invert":invert,"match_falloff":match_falloff}
 for key in values: _owned_material.set_shader_parameter(key,values[key])
 queue_redraw()

func _draw() -> void:
 if size.x > 0 and size.y > 0:
  draw_rect(Rect2(Vector2.ZERO,size),Color.WHITE)
