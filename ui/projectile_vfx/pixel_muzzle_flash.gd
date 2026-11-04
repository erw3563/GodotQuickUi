@tool
@abstract
class_name PixelMuzzleFlash2D
extends NativeAnimationRenderer
## 方向闪光的重播、结束与外部时钟；派生表现消费方向、颜色和尺寸绘制。
signal finished
@export var core_color := Color("fff5dc")
@export var edge_color := Color("d99b56")
@export_range(2.0, 16.0, 0.5) var length_px := 7.0
@export_range(1.0, 10.0, 0.5) var width_px := 4.0
@export_range(0.02, 0.3, 0.01) var lifetime := 0.07
var active: bool:
	get: return local_time < lifetime
var _age: float:
	get: return local_time
var _origin := Vector2.ZERO
var _direction := Vector2.RIGHT

func configure_effect(world_position: Vector2, direction: Vector2, _seed_value: int = 0) -> void:
	_origin = world_position
	_direction = direction.normalized() if direction.length_squared() > 0.0 else Vector2.RIGHT
	local_time = 0.0
	set_process(false)
	set_notify_transform(true)

func get_active_count() -> int:
	return int(active)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED: queue_redraw()
