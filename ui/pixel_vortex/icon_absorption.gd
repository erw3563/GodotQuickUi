extends Control
## 把已捕获的图标纹理副本沿旋转收缩轨迹送往指定画布位置。
## 调用者持有业务提交与完成后的导航；本场景只管理自己的视觉副本。
signal finished
@export_range(0.1, 2.0) var duration: float = 0.52
@export_range(-4.0, 4.0) var turns: float = 1.5
var _tween: Tween
var _generation := 0
@onready var _icon: TextureRect = $Icon

func play(texture: Texture2D, source_transform: Transform2D, source_size: Vector2,
		target_canvas_position: Vector2, source_rotation: float = 0.0) -> void:
	cancel()
	var generation := _generation
	var canvas_to_local := get_global_transform_with_canvas().affine_inverse()
	var local_transform := canvas_to_local * source_transform
	var source_center := local_transform * (source_size * 0.5)
	var target_center := canvas_to_local * target_canvas_position
	_icon.texture = texture
	_icon.size = source_size
	_icon.pivot_offset = source_size * 0.5
	_icon.position = source_center - _icon.pivot_offset
	_icon.scale = local_transform.get_scale()
	_icon.rotation = local_transform.get_rotation() + source_rotation
	_icon.modulate = Color.WHITE
	_icon.show()
	_tween = create_tween().set_parallel(true)
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(_icon, "position", target_center - _icon.pivot_offset, duration)
	_tween.tween_property(_icon, "scale", _icon.scale * 0.025, duration)
	_tween.tween_property(_icon, "rotation", _icon.rotation + TAU * turns, duration)
	_tween.tween_property(_icon, "modulate:a", 0.0, duration * 0.24).set_delay(duration * 0.76)
	_tween.finished.connect(_finish.bind(generation), CONNECT_ONE_SHOT)

func cancel() -> void:
	_generation += 1
	if is_instance_valid(_tween):
		_tween.kill()
	_tween = null
	if is_instance_valid(_icon):
		_icon.hide()
		_icon.texture = null

func _finish(generation: int) -> void:
	if generation != _generation or not is_inside_tree():
		return
	_icon.hide()
	_icon.texture = null
	finished.emit()

func _exit_tree() -> void:
	cancel()
