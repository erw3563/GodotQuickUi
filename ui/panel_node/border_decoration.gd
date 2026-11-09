@tool
class_name BorderDecoration
extends TextureRect
## 场景声明的独立装饰；身份、制作名称、图片和排布随场景保存。
@export var appearance_id: StringName = &"decoration"
@export var display_name := "装饰"

func get_appearance() -> Dictionary:
	return {"color": modulate, "texture": texture, "width": size.x, "height": size.y, "x": position.x, "y": position.y, "decoration": true, "editable_fields": PackedStringArray(["color", "texture", "width", "height", "x", "y"])}

func set_appearance(values: Dictionary) -> void:
	if values.has("color"): modulate = values.color
	if values.has("texture"): texture = values.texture
	if values.has("width"): size.x = values.width
	if values.has("height"): size.y = values.height
	if values.has("x"): position.x = values.x
	if values.has("y"): position.y = values.y

func contains_canvas_point(point: Vector2) -> bool:
	return is_visible_in_tree() and Rect2(Vector2.ZERO, size).has_point(get_global_transform().affine_inverse() * point)
