@tool
class_name TextRevealClip
extends Control
## Generic authored clip window. Progress slides Content up from below its edge.
## Preserves authored glyphs and typography; accepts QuickTweenFloat progress.
@export_range(0.0, 1.0, 0.001) var progress: float = 1.0:
 set(value):
  progress = clampf(value, 0.0, 1.0)
  _apply()
func _ready() -> void:
 clip_contents = true
 resized.connect(_apply)
 _apply()
func _apply() -> void:
 var content := get_node_or_null("Content") as Control
 if content:
  content.position.y = size.y * (1.0 - progress)
