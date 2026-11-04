@tool
class_name NativeAnimationEffect2D
extends VisualEffect2D
## 特效实例用原生片段控制局部表现，所属会话提供时钟与运动记录。
@export var animation_set: NativeAnimationSet
@export var variant: StringName = &""
var _age := 0.0
var _phase := "main"
var _direction := Vector2.DOWN
var _renderers: Array[NativeAnimationRenderer] = []

func _ready() -> void:
	if Engine.is_editor_hint() and animation_set != null: prepare(animation_set)

func start_effect(world_position: Vector2, direction: Vector2, seed_value: int = 0) -> void:
	global_position = world_position
	_direction = (get_parent() as Node2D).global_transform.basis_xform_inv(direction)
	_age = 0.0
	_renderers.clear()
	for node in get_node("FeedbackRoot/ContentRoot").find_children("*", "", true, false):
		if node is NativeAnimationRenderer:
			_renderers.append(node)
			node.configure_effect(world_position, direction, seed_value)
	if animation_set == null:
		finished = true
		return
	prepare(animation_set)
	_phase = "enter" if _binding("enter") != null else ("hold" if _binding("hold") != null else "main")
	_play_phase()

func _binding(phase: String) -> NativeAnimationBinding:
	return animation_set.resolve(&"effect", variant, "", _direction, phase) if animation_set != null else null

func _play_phase() -> void:
	var binding := _binding(_phase)
	if binding == null:
		finished = true
		return
	play_clip(binding.animation, binding.reverse)

func follow_effect(world_position: Vector2, velocity: Vector2, delta: float) -> void:
	global_position = world_position
	for renderer in _renderers:
		renderer.capture_motion(world_position, velocity, _age + maxf(0.0, delta), delta)

func advance_effect(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	_age += delta
	var remaining := delta
	while remaining > 0.0 and not finished:
		var clip := get_player().get_animation(animation_name)
		var amount := remaining if is_looping() else minf(remaining, elapsed if reversed else clip.length - elapsed)
		advance_time(amount)
		remaining -= amount
		if not finished: break
		if _phase == "enter":
			if _binding("hold") != null: _phase = "hold"
			elif _binding("main") != null: _phase = "main"
			elif _binding("exit") != null: _phase = "exit"
			else: break
		elif _phase == "main" and _binding("exit") != null: _phase = "exit"
		else: break
		_play_phase()
	for renderer in _renderers: renderer.sample_clock(_age)

func stop_effect() -> void:
	for renderer in _renderers: renderer.stop_emitting()
	if _phase == "hold" or (_phase == "enter" and _binding("hold") != null):
		_phase = "exit"
		_play_phase()

func effect_duration() -> float:
	if animation_set == null: return 0.0
	if _binding("hold") != null: return -1.0
	var durations := {}
	for binding in animation_set.bindings:
		if binding.behavior != &"effect" or binding.variant != variant: continue
		var clip := animation_set.animation(binding.animation)
		if clip != null: durations[binding.phase] = maxf(float(durations.get(binding.phase, 0.0)), clip.length)
	return float(durations.get("enter", 0.0)) + float(durations.get("main", 0.0)) + float(durations.get("exit", 0.0))

func effect_finished() -> bool:
	return finished
