@tool
class_name LayeredWave
extends Control
## A travelling, undulating curtain between two isolated input textures.
## Native SubViewport textures must opt into premultiplied input handling.
## This node owns its material and transport; callers own both sources.
signal progress_changed(value: float)
signal completed(value: float)
const EFFECT = preload("res://addons/gdbase/ui/layered_wave/layered_wave.gdshader")
const MAX_BANDS := 8
var _widths := PackedFloat32Array([8,18,720,18,8])
var _colors := PackedColorArray([Color("f2f0df"),Color("eceb93"),Color("b6eb39"),Color("eceb93"),Color("f2f0df")])
@export_group("Isolated Inputs")
@export var source_a: Texture2D:
 set(value):
  source_a=value
  _sync()
@export var source_b: Texture2D:
 set(value):
  source_b=value
  _sync()
@export var source_a_premultiplied := false:
 set(value):
  source_a_premultiplied=value
  _sync()
@export var source_b_premultiplied := false:
 set(value):
  source_b_premultiplied=value
  _sync()
@export_group("Wave Geometry")
## Direction in local output pixels. Zero and nonfinite vectors are ignored.
@export var sweep_direction := Vector2.UP:
 set(value):
  if value.is_finite() and value.length_squared()>0.000001:
   sweep_direction=value.normalized()
   _sync()
@export_range(0,1024,0.5,"or_greater") var amplitude := 34.0:
 set(value):
  if is_finite(value):
   amplitude=clampf(value,0,65536)
   _sync()
## Number of full oscillations across the perpendicular output extent.
@export_range(0,16,0.01,"or_greater") var frequency := 1.35:
 set(value):
  if is_finite(value):
   frequency=clampf(value,0,64)
   _sync()
@export_range(-6.283,6.283,0.01,"or_less","or_greater") var phase := 0.35:
 set(value):
  if is_finite(value):
   phase=fposmod(value,TAU)
   _sync()
## Optional total phase travel over the sweep. It is progress-based and reversible.
@export_range(-12.566,12.566,0.01) var phase_travel := 1.4:
 set(value):
  if is_finite(value):
   phase_travel=clampf(value,-64*TAU,64*TAU)
   _sync()
@export_range(0,128,0.1,"or_greater") var softness := 1.0:
 set(value):
  if is_finite(value):
   softness=clampf(value,0,4096)
   _sync()
@export_group("Intermediate Bands")
## Leading to trailing widths, in local pixels; at most eight width/color pairs.
## Getter returns a copy: assign the edited array back to apply changes.
@export var band_widths := PackedFloat32Array([8,18,720,18,8]):
 set(value):
  var clean := PackedFloat32Array()
  for index in range(mini(value.size(),MAX_BANDS)):
   clean.append(clampf(value[index],0,65536) if is_finite(value[index]) else 0.0)
  _widths=clean
  _sync()
 get: return _widths.duplicate()
@export var band_colors := PackedColorArray([Color("f2f0df"),Color("eceb93"),Color("b6eb39"),Color("eceb93"),Color("f2f0df")]):
 set(value):
  var clean := PackedColorArray()
  for index in range(mini(value.size(),MAX_BANDS)):
   var c:Color=value[index]
   if not is_finite(c.r) or not is_finite(c.g) or not is_finite(c.b) or not is_finite(c.a): c=Color.TRANSPARENT
   clean.append(c.clamp())
  _colors=clean
  _sync()
 get: return _colors.duplicate()
@export_range(0,1,0.001) var opacity := 1.0:
 set(value):
  if is_finite(value):
   opacity=clampf(value,0,1)
   _sync()
@export_group("Transport")
@export_range(0,1,0.001) var progress := 0.0:
 set(value):
  if is_finite(value):
   progress=clampf(value,0,1)
   _sync()
   progress_changed.emit(progress)
@export_range(0.01,120,0.01) var duration := 3.0:
 set(value):
  if is_finite(value): duration=clampf(value,0.01,120)
var playing := false
var playback_direction := 1.0
var _revision := 0
var _owned_material: ShaderMaterial
var _previous_material: Material
func _enter_tree() -> void:
 _previous_material=material
 if _owned_material==null:
  _owned_material=ShaderMaterial.new()
  _owned_material.shader=EFFECT
 material=_owned_material
 if not resized.is_connected(_sync): resized.connect(_sync)
 if not visibility_changed.is_connected(_visibility): visibility_changed.connect(_visibility)
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 set_process(false)
 _sync()
func _ready() -> void:
 set_process(playing and not Engine.is_editor_hint())
func _exit_tree() -> void:
 stop()
 if material==_owned_material: material=_previous_material
func _visibility() -> void:
 if not is_visible_in_tree(): stop()
func _process(delta:float) -> void:
 if not Engine.is_editor_hint(): advance(delta)
func _set_playing(value:bool) -> void:
 playing=value
 set_process(value and not Engine.is_editor_hint())
func stop() -> void:
 _revision+=1
 _set_playing(false)
func seek(value:float) -> void:
 if not is_finite(value): return
 stop()
 progress=value
func play_to(endpoint:float) -> void:
 if not is_finite(endpoint): return
 _revision+=1
 var target:=clampf(endpoint,0,1)
 if target!=0 and target!=1:
  seek(target)
  return
 playback_direction=1 if target>progress else -1
 _set_playing(is_inside_tree() and is_visible_in_tree() and target!=progress)
func replay() -> void:
 stop()
 var revision:=_revision
 progress=0
 if _revision==revision and progress==0: play_to(1)
func reverse() -> void:
 _revision+=1
 if progress<=0: playback_direction=1
 elif progress>=1: playback_direction=-1
 else: playback_direction=-playback_direction
 _set_playing(is_inside_tree() and is_visible_in_tree())
func toggle_pause() -> void:
 _revision+=1
 if playing: stop()
 else:
  if progress<=0: playback_direction=1
  elif progress>=1: playback_direction=-1
  _set_playing(is_inside_tree() and is_visible_in_tree())
func advance(delta:float) -> void:
 if not playing or not is_inside_tree() or not is_visible_in_tree() or not is_finite(delta) or delta<=0: return
 var revision:=_revision
 var next:=clampf(progress+playback_direction*delta/duration,0,1)
 progress=next
 if revision!=_revision or not playing or not is_inside_tree() or progress!=next: return
 if progress==0 or progress==1:
  _set_playing(false)
  completed.emit(progress)
func band_count() -> int: return mini(_widths.size(),_colors.size())
func total_band_width() -> float:
 var total:=0.0
 for i in range(band_count()): total+=_widths[i]
 return total
## (minimum, maximum) projection of the output rectangle onto an axis.
func projection_bounds(axis:Vector2) -> Vector2:
 var a:=axis.x*maxf(size.x,0)
 var b:=axis.y*maxf(size.y,0)
 return Vector2(minf(0,a)+minf(0,b),maxf(0,a)+maxf(0,b))
func wave_offset(point:Vector2) -> float:
 var tangent:=Vector2(-sweep_direction.y,sweep_direction.x)
 var bounds:=projection_bounds(tangent)
 var t:float=(point.dot(tangent)-bounds.x)/maxf(bounds.y-bounds.x,1)
 return amplitude*sin(t*TAU*frequency+phase+phase_travel*progress)
func front_position() -> float:
 var bounds:=projection_bounds(sweep_direction)
 var margin:=amplitude+softness+1.0
 return lerpf(bounds.x-margin,bounds.y+total_band_width()+margin,progress)
## Convex compositing weights [A, band0..bandN, B], useful for CPU hit/QA logic.
func weights_at(point:Vector2) -> PackedFloat32Array:
 var weights:=PackedFloat32Array()
 weights.resize(band_count()+2)
 if progress<=0:
  weights[0]=1
  return weights
 if progress>=1:
  weights[weights.size()-1]=1
  return weights
 var distance:=front_position()+wave_offset(point)-point.dot(sweep_direction)
 var edge:=maxf(softness,0.0001)
 var previous:=smoothstep(-edge,edge,distance)
 weights[0]=1-previous
 var offset:=0.0
 for i in range(band_count()):
  offset+=_widths[i]
  var next:=smoothstep(-edge,edge,distance-offset)
  weights[i+1]=maxf(0,previous-next)
  previous=next
 weights[weights.size()-1]=previous
 return weights
func _sync() -> void:
 if not is_inside_tree() or _owned_material==null: return
 var widths:=PackedFloat32Array()
 var colors:=PackedColorArray()
 for i in range(MAX_BANDS):
  widths.append(_widths[i] if i<band_count() else 0.0)
  colors.append(_colors[i] if i<band_count() else Color.TRANSPARENT)
 var values:Dictionary={"source_a":source_a,"source_b":source_b,"has_a":source_a!=null,"has_b":source_b!=null,
  "a_premultiplied":source_a_premultiplied,"b_premultiplied":source_b_premultiplied,
  "extent":size.max(Vector2.ONE),"sweep_direction":sweep_direction,"amplitude":amplitude,"frequency":frequency,
  "phase":phase,"phase_travel":phase_travel,"softness":softness,"progress":progress,"opacity":opacity,
  "band_count":band_count(),"band_widths":widths,"band_colors":colors,"total_width":total_band_width()}
 for key in values: _owned_material.set_shader_parameter(key,values[key])
 queue_redraw()
func _draw() -> void:
 if size.x>0 and size.y>0: draw_rect(Rect2(Vector2.ZERO,size),Color.WHITE)
