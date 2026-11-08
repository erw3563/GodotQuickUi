@tool
class_name DecoratedNinePatchStyleBox
extends StyleBox
## 可用于容器样式槽的九宫格边框。底色、切片和原尺寸装饰按绘制顺序组合。
@export var background: StyleBox
@export var border: StyleBoxTexture
@export var ornaments: Array[DecoratedFrameOrnament] = []
@export var minimum_frame_size := Vector2.ZERO


func get_minimum_frame_size() -> Vector2:
	return minimum_frame_size.max(get_minimum_size())


func _draw(canvas_item: RID, rect: Rect2) -> void:
	if background != null:
		background.draw(canvas_item, rect)
	if border != null:
		border.draw(canvas_item, rect)
	for ornament in ornaments:
		if ornament == null or ornament.texture == null:
			continue
		var origin := (rect.position + rect.size * ornament.anchor).floor() + ornament.offset
		ornament.texture.draw(canvas_item, origin)
