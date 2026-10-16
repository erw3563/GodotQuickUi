@tool
class_name ImageSliceComposition
extends Control
signal progress_changed(value: float)
signal completed(value: float)
@export var texture: Texture2D:
 set(value):
  texture = value
  refresh()
@export_range(0,1) var progress := 1.0:
 set(value):
  progress = clampf(value,0,1)
  refresh()
  progress_changed.emit(progress)
@export var duration := 1.5
var _tween: Tween
var _target := 1.0
func _ready() -> void: refresh()
func refresh() -> void:
 for child in get_children():
  if child is ImageSliceWindow:
   child.texture = texture
   child.progress = progress
func seek(value: float) -> void:
 stop()
 progress = value
func stop() -> void:
 if _tween and _tween.is_valid(): _tween.kill()
 _tween = null
func play_to(value: float, seconds := -1.0) -> void:
 stop()
 _target = clampf(value,0,1)
 var time := duration if seconds < 0 else seconds
 if time <= 0 or is_equal_approx(progress,_target):
  progress = _target
  completed.emit(progress)
  return
 _tween = create_tween()
 _tween.tween_property(self,"progress",_target,time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
 _tween.tween_callback(func(): completed.emit(progress))
func replay() -> void:
 seek(0)
 play_to(1)
func reverse() -> void: play_to(0.0 if _target >= 0.5 else 1.0)
