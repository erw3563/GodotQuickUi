@tool
class_name LoopingStrip
extends Control
## A transport for an authored set of native Control children.
## Supply enough authored repeats to cover the view plus two pitches. Items remain
## native, selectable nodes, and owned positions can be restored explicitly.
signal phase_changed(value: float)
signal wrapped(cycles: int)
signal coverage_changed(enough: bool)

@export var items_path: NodePath = ^"Items"
@export_range(1.0,4096.0,1.0) var item_width := 152.0:
 set(value):
  if is_finite(value):
   item_width = clampf(value,1.0,4096.0)
   _layout()
@export_range(0.0,1024.0,1.0) var gap := 48.0:
 set(value):
  if is_finite(value):
   gap = clampf(value,0.0,1024.0)
   _layout()
@export_range(0.0,2000.0,1.0) var speed := 64.0:
 set(value):
  if is_finite(value): speed = clampf(value,0.0,2000.0)
@export_enum("Left:-1","Right:1") var direction := -1:
 set(value): direction = -1 if value < 0 else 1
@export_range(-45.0,45.0,0.1) var tilt_degrees := -10.0:
 set(value):
  if is_finite(value):
   tilt_degrees = clampf(value,-45.0,45.0)
   rotation = deg_to_rad(tilt_degrees)
@export var initial_phase := 0.0
@export var autoplay := true

var phase := 0.0
var playing := false
var _items: Array[Control] = []
var _original: Array[Dictionary] = []
var _initialized := false
var _revision := 0
var _restored := false
var _coverage := true

func _ready() -> void:
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 if not resized.is_connected(_layout): resized.connect(_layout)
 if not visibility_changed.is_connected(_visibility_changed): visibility_changed.connect(_visibility_changed)
 if not _initialized:
  refresh_items()
  phase = fposmod(initial_phase,cycle_length()) if is_finite(initial_phase) else 0.0
  _initialized = true
  _layout()
  if autoplay and not Engine.is_editor_hint(): play()

func _enter_tree() -> void:
 rotation = deg_to_rad(tilt_degrees)
 if _initialized:
  _restored = false
  _layout()

func _exit_tree() -> void:
 stop()

func _visibility_changed() -> void:
 if not is_visible_in_tree(): stop()

func refresh_items() -> void:
 ## Explicitly rebuild the authored-child binding after an editor/runtime edit.
 ## Release the old binding first, so removed/rebound nodes retain their base pose.
 stop()
 restore_items()
 _items.clear()
 _original.clear()
 var container := get_node_or_null(items_path)
 if container:
  for child in container.get_children():
   if child is Control:
    _items.append(child)
    _original.append({"position":child.position})
 _restored = false
 _layout()

func restore_items() -> void:
 ## Releases owned positions while preserving rotation, scale, pivot and content.
 stop()
 for index in _items.size():
  var item := _items[index]
  if is_instance_valid(item) and item.get_parent() == get_node_or_null(items_path):
   item.position = _original[index].position
 _restored = true

func pitch() -> float:
 return item_width + gap

func cycle_length() -> float:
 return maxf(pitch()*_items.size(),1.0)

func binding_is_valid() -> bool:
 var container := get_node_or_null(items_path)
 if not is_instance_valid(container) or _items.is_empty(): return false
 for item in _items:
  if not is_instance_valid(item) or item.get_parent() != container: return false
 return true

func has_coverage() -> bool:
 return binding_is_valid() and _items.size() >= 2 and cycle_length() >= maxf(size.x,0.0)+2.0*pitch()

func item_count() -> int:
 return _items.size()

func wrapped_position(index: int, at_phase: float) -> float:
 if not is_finite(at_phase): return 0.0
 return fposmod(float(index)*pitch()+at_phase,cycle_length())-pitch()

func _layout() -> void:
 if _items.is_empty() or _restored: return
 if not binding_is_valid():
  stop()
  if _coverage:
   _coverage = false
   coverage_changed.emit(false)
  return
 phase = fposmod(phase,cycle_length())
 for index in _items.size():
  var item := _items[index]
  if is_instance_valid(item):
   item.position = Vector2(wrapped_position(index,phase),_original[index].position.y)
 var enough := has_coverage()
 if enough != _coverage:
  _coverage = enough
  coverage_changed.emit(enough)

func _process(delta: float) -> void:
 if not Engine.is_editor_hint(): advance(delta)

func advance(delta: float) -> void:
 if not playing or not is_inside_tree() or not is_visible_in_tree() or not is_finite(delta) or delta <= 0.0 or speed <= 0.0 or _items.is_empty(): return
 if not binding_is_valid():
  stop()
  return
 var revision := _revision
 var length := cycle_length()
 var travel := float(direction)*speed*minf(delta,1000000.0)
 var next := phase+travel
 var cycles := int(floor(next/length))
 phase = fposmod(next,length)
 _layout()
 phase_changed.emit(phase)
 # Any synchronous stop/seek/reverse/restoration owns the latest intent.
 if revision != _revision or not playing: return
 if cycles != 0: wrapped.emit(cycles)

func play() -> void:
 _revision += 1
 _restored = false
 _layout()
 playing = is_inside_tree() and is_visible_in_tree() and binding_is_valid()
 set_process(playing and not Engine.is_editor_hint())

func stop() -> void:
 _revision += 1
 playing = false
 set_process(false)

func toggle_pause() -> void:
 if playing: stop()
 else: play()

func reverse() -> void:
 ## Reverses velocity while preserving phase and pause state.
 _revision += 1
 direction = -direction

func seek_pixels(value: float) -> void:
 if not is_finite(value): return
 stop()
 _restored = false
 phase = fposmod(value,cycle_length())
 _layout()
 phase_changed.emit(phase)

func seek_normalized(value: float) -> void:
 if is_finite(value): seek_pixels(clampf(value,0.0,1.0)*cycle_length())

func replay() -> void:
 stop()
 var revision := _revision
 _restored = false
 phase = fposmod(initial_phase,cycle_length()) if is_finite(initial_phase) else 0.0
 _layout()
 phase_changed.emit(phase)
 if revision == _revision: play()
