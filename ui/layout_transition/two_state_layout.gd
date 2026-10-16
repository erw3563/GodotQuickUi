@tool
class_name TwoStateLayout
extends Control
## Interpolates authored direct-child Control rectangles and input availability.
signal completed(expanded: bool)
signal progress_changed(value: float)
@export var reference_size := Vector2(1120, 580):
 set(value):
  reference_size = value.max(Vector2.ONE)
  _apply()
@export var tracks: Array[LayoutStateTrack] = []:
 set(value):
  tracks = value
  if is_node_ready(): refresh()
@export_range(0.0, 1.0) var progress: float:
 get: return _value
 set(value): seek(value)
@export_range(0.0, 5.0) var duration := 0.85
var _value := 0.0
var _destination := 0.0
var _tween: Tween
var _input: Dictionary = {}
var _warned: Dictionary = {}
func _ready() -> void:
 resized.connect(_apply)
 refresh()
func refresh() -> void:
 ## Call after editing resource fields/paths or replacing scene children.
 _restore_input()
 _warned.clear()
 _apply()
func seek(value: float) -> void:
 cancel()
 _set_value(value)
func cancel() -> void:
 if _tween and _tween.is_valid(): _tween.kill()
 _tween = null
func transition_to(expanded: bool, seconds: float = -1.0) -> void:
 cancel()
 _destination = 1.0 if expanded else 0.0
 var remaining := absf(_destination - _value)
 var travel := duration if seconds < 0.0 else maxf(0.0, seconds)
 if travel <= 0.0 or remaining <= 0.000001:
  _set_value(_destination)
  completed.emit(expanded)
  return
 # A linear master clock plus smoothstep per track gives reversible authored poses.
 _tween = create_tween()
 _tween.tween_method(_set_value, _value, _destination, travel * remaining)
 _tween.tween_callback(func(): completed.emit(expanded))
func reverse() -> void:
 transition_to(_destination < 0.5)
func _set_value(value: float) -> void:
 _value = clampf(value, 0.0, 1.0)
 _apply()
 progress_changed.emit(_value)
func _apply() -> void:
 if not is_node_ready(): return
 var ratio := size / reference_size
 for track in tracks:
  if track == null: continue
  var node := get_node_or_null(track.target) as Control
  if node == null or node == self or node.get_parent() != self or node.get_parent() is Container:
   _warn_once(str(track.target), "TwoStateLayout: target must be an existing direct-child Control: " + str(track.target))
   continue
  if node.anchor_left != 0 or node.anchor_right != 0 or node.anchor_top != 0 or node.anchor_bottom != 0:
   _warn_once(str(track.target), "TwoStateLayout: use zero anchors on target wrapper: " + str(track.target))
   continue
  var t := 0.0
  if track.end <= track.start:
   t = 1.0 if _value >= track.end else 0.0
  else:
   t = clampf((_value - track.start) / (track.end - track.start), 0.0, 1.0)
  t = t * t * (3.0 - 2.0 * t)
  node.position = track.compact_rect.position.lerp(track.expanded_rect.position, t) * ratio
  node.size = track.compact_rect.size.lerp(track.expanded_rect.size, t) * ratio
  var alpha := clampf(lerpf(track.compact_alpha, track.expanded_alpha, t), 0.0, 1.0)
  node.modulate.a = alpha
  node.visible = alpha > 0.0001
  if not Engine.is_editor_hint(): _gate_input(node, alpha >= 0.9999)
func _gate_input(node: Node, enabled: bool) -> void:
 if node is Control:
  var id := node.get_instance_id()
  if not _input.has(id):
   _input[id] = [weakref(node), node.mouse_filter, node.focus_mode]
  var saved: Array = _input[id]
  node.mouse_filter = saved[1] if enabled else Control.MOUSE_FILTER_IGNORE
  node.focus_mode = saved[2] if enabled else Control.FOCUS_NONE
  if not enabled and node.has_focus(): node.release_focus()
 for child in node.get_children(): _gate_input(child, enabled)
func _restore_input() -> void:
 for saved in _input.values():
  var node = saved[0].get_ref()
  if is_instance_valid(node):
   node.mouse_filter = saved[1]
   node.focus_mode = saved[2]
 _input.clear()
func _warn_once(key: String, message: String) -> void:
 if _warned.has(key): return
 _warned[key] = true
 push_warning(message)
func _exit_tree() -> void:
 cancel()
 _restore_input()
