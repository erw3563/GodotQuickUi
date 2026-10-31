@tool
class_name AnimatedFramesEffect2D
extends VisualEffect2D
## 固定世界锚点上的有限帧动画；所属播放器提供唯一时钟并回收节点。
@export var frames: SpriteFrames
@export var direction_angles: Dictionary = {}
@onready var sprite: AnimatedSprite2D = $Frames
var _age := 0.0
var _duration := 0.0
var _finished := true
func start_effect(world_position: Vector2, direction: Vector2, _seed_value: int = 0) -> void:
	global_position = world_position
	sprite.sprite_frames = frames
	var local_direction: Vector2 = (get_parent() as Node2D).global_transform.basis_xform_inv(direction)
	var key: StringName = &"default"
	var score := -INF
	for candidate in direction_angles:
		var alignment := local_direction.normalized().dot(Vector2.RIGHT.rotated(direction_angles[candidate]))
		if alignment > score:
			score = alignment
			key = candidate
	_age = 0.0
	_finished = frames == null or not frames.has_animation(key)
	if _finished: return
	sprite.animation = key
	sprite.pause()
	_duration = 0.0
	for index in frames.get_frame_count(key): _duration += frames.get_frame_duration(key, index) / frames.get_animation_speed(key)
	_sample()
func advance_effect(delta: float) -> void:
	if _finished or not is_finite(delta) or delta <= 0.0: return
	_age += delta
	_sample()
func _sample() -> void:
	var key := sprite.animation
	var cursor := minf(_age, maxf(0.0, _duration - 0.000001)) * frames.get_animation_speed(key)
	var index := 0
	while index < frames.get_frame_count(key) - 1 and cursor >= frames.get_frame_duration(key, index):
		cursor -= frames.get_frame_duration(key, index)
		index += 1
	sprite.set_frame_and_progress(index, cursor / frames.get_frame_duration(key, index))
	_finished = _age >= _duration
func stop_effect() -> void:
	pass
func effect_duration() -> float:
	var longest := 0.0
	if frames == null: return longest
	for key in frames.get_animation_names():
		var speed := frames.get_animation_speed(key)
		if not is_finite(speed) or speed <= 0.0: return 0.0
		var duration := 0.0
		for index in frames.get_frame_count(key): duration += frames.get_frame_duration(key, index) / speed
		longest = maxf(longest, duration)
	return longest
func effect_finished() -> bool:
	return _finished
