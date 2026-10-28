@tool
@abstract
class_name PixelMuzzleFlash2D
extends VisualEffect2D
## 方向闪光的重播、结束与外部时钟；派生表现消费方向、颜色和尺寸绘制。
signal finished
@export var core_color := Color("fff5dc")
@export var edge_color := Color("d99b56")
@export_range(2.0, 16.0, 0.5) var length_px := 7.0
@export_range(1.0, 10.0, 0.5) var width_px := 4.0
@export_range(0.02, 0.3, 0.01) var lifetime := 0.07
@export var auto_free := false
var active := false
var _age := 0.0
var _origin := Vector2.ZERO
var _direction := Vector2.RIGHT
var _generation := 0

func _ready() -> void:
	set_notify_transform(true)
	set_process(active)

func play(world_position: Vector2, direction: Vector2) -> void:
	reset()
	if not world_position.is_finite() or not direction.is_finite():
		return
	_origin = world_position
	_direction = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	active = true
	set_process(true)
	queue_redraw()

func reset() -> void:
	_generation += 1
	active = false
	_age = 0.0
	set_process(false)
	queue_redraw()

func advance(delta: float) -> void:
	if not active or not is_finite(delta) or delta <= 0.0:
		return
	_age += delta
	if _age >= clampf(lifetime, 0.02, 0.3):
		active = false
		set_process(false)
		var generation := _generation
		finished.emit()
		if not is_instance_valid(self):
			return
		if auto_free and generation == _generation and not active and is_inside_tree():
			queue_free()
	queue_redraw()

func _process(delta: float) -> void:
	advance(delta)

func get_active_count() -> int:
	return int(active)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		queue_redraw()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and not is_visible_in_tree():
		reset()
	elif what == NOTIFICATION_EXIT_TREE:
		reset()

func start_effect(world_position: Vector2, direction: Vector2, _seed: int = 0) -> void:
	auto_free = false
	play(world_position, direction)
	set_process(false)

func advance_effect(delta: float) -> void:
	advance(delta)
	set_process(false)

func effect_duration() -> float:
	return clampf(lifetime, 0.02, 0.3)

func effect_finished() -> bool:
	return not active
