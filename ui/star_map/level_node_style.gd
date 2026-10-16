@tool
class_name LevelNodeStyle
extends Resource
## Reusable authoring preset; StarMapStar takes a private deep copy on assignment.
enum Preset { BUD, SEAL, DOORWAY, STONE }
@export var preset: Preset = Preset.BUD:
	set(value):
		preset = value
		emit_changed()
@export var color := Color("b4c596"):
	set(value):
		color = value
		emit_changed()
@export var accent := Color("f4e1b8"):
	set(value):
		accent = value
		emit_changed()
@export var decoration := true:
	set(value):
		decoration = value
		emit_changed()
@export var size := Vector2(20, 24):
	set(value):
		size = value
		emit_changed()
@export var texture: Texture2D:
	set(value):
		texture = value
		emit_changed()
@export var visual_scene: PackedScene:
	set(value):
		visual_scene = value
		emit_changed()

func bounded_size() -> Vector2:
	return Vector2(clampf(size.x, 8, 40) if is_finite(size.x) else 20.0, clampf(size.y, 8, 40) if is_finite(size.y) else 24.0)
