@tool
class_name VisualEffectPlayback
extends RefCounted
## 战斗与预览共用的预制实例播放集合；宿主持有节点，调用方提供统一时钟和运动快照。
var _host: Node2D
var _active: Array[VisualEffect2D] = []
var _following: Array[VisualEffect2D] = []
var _serial := 0
var _generation := 0

func _init(host: Node2D) -> void:
	_host = host

func play_prefab(scene: PackedScene, world_position: Vector2, direction: Vector2, following := false) -> void:
	if scene == null or not scene.can_instantiate(): return
	var generation := _generation
	var instance := scene.instantiate()
	var effect := instance as VisualEffect2D
	if effect == null:
		instance.free()
		push_warning("特效预制根节点须继承 VisualEffect2D: " + scene.resource_path)
		return
	_host.add_child(effect)
	effect.process_mode = Node.PROCESS_MODE_DISABLED
	_serial += 1
	_active.append(effect)
	if following: _following.append(effect)
	effect.start_effect(world_position, direction, _serial)
	if generation != _generation or not is_instance_valid(effect): return
	if not following: effect.stop_effect()

func follow(world_position: Vector2, velocity: Vector2, delta: float) -> void:
	var generation := _generation
	for effect in _following.duplicate():
		if is_instance_valid(effect): effect.follow_effect(world_position, velocity, delta)
		if generation != _generation: return

func stop_following() -> void:
	var generation := _generation
	for effect in _following.duplicate():
		if is_instance_valid(effect): effect.stop_effect()
		if generation != _generation: return
	_following.clear()

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	var generation := _generation
	for effect in _active.duplicate():
		if not is_instance_valid(effect):
			_active.erase(effect)
			_following.erase(effect)
			continue
		effect.advance_effect(delta)
		if generation != _generation: return
		if not is_instance_valid(effect):
			_active.erase(effect)
			_following.erase(effect)
			continue
		if effect.effect_finished():
			_active.erase(effect)
			_following.erase(effect)
			effect.queue_free()

func is_empty() -> bool:
	return _active.is_empty()

func active_count() -> int:
	return _active.size()

func clear() -> void:
	_generation += 1
	for effect in _active:
		if is_instance_valid(effect):
			if effect.get_parent() != null: effect.get_parent().remove_child(effect)
			effect.queue_free()
	_active.clear()
	_following.clear()
	_serial = 0