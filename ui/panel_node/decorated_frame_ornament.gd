@tool
class_name DecoratedFrameOrnament
extends Resource
## 固定原生尺寸的边框装饰。锚点采用边框矩形内的相对坐标。
@export var appearance_id: StringName = &"decoration"
@export var display_name := "边框装饰"
@export var texture: Texture2D
@export var anchor := Vector2(0.5, 0.0)
@export var offset := Vector2.ZERO

## 绘制与预览命中共用原生纹理尺寸和相对外框的锚点偏移。
func get_rect(frame_rect: Rect2) -> Rect2:
	var origin := (frame_rect.position + frame_rect.size * anchor).floor() + offset
	return Rect2(origin, texture.get_size() if texture != null else Vector2.ZERO)

func get_appearance() -> Dictionary:
	var dimensions := texture.get_size() if texture != null else Vector2.ZERO
	return {"color": Color.WHITE, "texture": texture, "width": dimensions.x, "height": dimensions.y, "x": offset.x, "y": offset.y, "decoration": true, "editable_fields": PackedStringArray(["texture", "x", "y"]), "disabled_reasons": {"color": "装饰使用纹理原始颜色，不支持独立着色。", "width": "装饰按纹理原始尺寸绘制，宽度由纹理决定。", "height": "装饰按纹理原始尺寸绘制，高度由纹理决定。"}}

func set_appearance(values: Dictionary) -> void:
	if values.has("texture"): texture = values.texture
	if values.has("x"): offset.x = values.x
	if values.has("y"): offset.y = values.y
