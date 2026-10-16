@tool
class_name QuickFloatNumber
extends Node2D
## 差额浮字播放器，按帧观察数值净变化或通过 emit_delta 接收逐笔事件。
## 数值来源优先使用 target，其次父节点；锚点、偏移与运动使用本件局部坐标。
## 活动浮字达到容量时复用最早活动项，演出结束时释放所属 Label。

signal number_emitted(delta: Variant, label: Label)

enum Motion { RISE, TOSS, DRIFT, SPRING, RISE_FALL }
enum SpawnStyle { POP, FADE, INSTANT }
enum DisappearStyle { FADE, SHRINK, SINK }

@export_group("观察器（可选）")
@export var target: Node:
	set(value):
		target = value
		_reset_binding()
@export var value_property: String = "":
	set(value):
		value_property = value
		_source_changed()
@export var observe_enabled := true:
	set(value):
		observe_enabled = value
		_source_changed()
## 开启时纳入原生节点的数值属性，例如 Range.value。
@export var include_builtin_properties := false:
	set(value):
		include_builtin_properties = value
		_source_changed()
@export var skip_hidden_target := true
@export var skip_disabled_target := true
@export_range(0.0, 1.0, 0.00001) var epsilon := 0.00001

@export_group("位置")
## 同一 Viewport 内可跨 CanvasLayer 指定独立显示锚点。
@export var anchor: CanvasItem
@export var offset := Vector2(0, -8)
## Label 的归一化定位点，同时作为缩放中心；默认顶边中心。
@export var label_anchor_ratio := Vector2(0.5, 0.0)
## 初始位置的水平随机幅度；运动侧向幅度由 spread 决定。
@export var jitter_x := 6.0

@export_group("样式")
@export_range(8, 160, 1) var font_size := 18
@export var font: Font
@export var gain_color := Color(0.4, 0.85, 0.45)
@export var loss_color := Color(1.0, 0.35, 0.25)
@export var outline_color := Color.BLACK
@export_range(0, 24, 1) var outline_size := 4
@export_range(0, 6, 1) var precision := 1
@export var positive_prefix := true

@export_group("运动 / 出现 / 消失")
@export var motion: Motion = Motion.RISE
@export var spawn_style: SpawnStyle = SpawnStyle.INSTANT
@export var disappear_style: DisappearStyle = DisappearStyle.FADE
@export var rise_height := 28.0
## RISE_FALL 从上升顶点沿局部正 Y 方向回落的距离。
@export var fall_height := 28.0
## 各时钟以秒计时，浮字在全部轨道完成后释放。
@export var rise_duration := 0.7
@export var fall_duration := 0.45
@export var fade_delay := 0.2
@export var fade_duration := 0.55
@export var spawn_duration := 0.18
@export_range(0.0, 1.0, 0.01, "or_greater") var spawn_initial_scale := 0.25
@export var rise_transition: Tween.TransitionType = Tween.TRANS_CUBIC
@export var fall_transition: Tween.TransitionType = Tween.TRANS_QUAD
@export var spread := 0.0
@export var random_seed: int = 42:
	set(value):
		random_seed = value
		_rng.seed = value
@export_range(1, 256, 1) var max_active := 64:
	set(value):
		max_active = clampi(value, 1, 256)
		_trim_active()

var _rng := RandomNumberGenerator.new()
var _baseline: Variant = null
var _watched: Node
var _active: Array[Dictionary] = []
var _property_valid := false
var _clearing := false
var _refreshing_property := false

func _enter_tree() -> void:
	_reset_binding()
	if is_node_ready() and not Engine.is_editor_hint():
		sample_now()

func _ready() -> void:
	_rng.seed = random_seed
	_reset_binding()
	if not Engine.is_editor_hint():
		sample_now()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_DISABLED:
		_baseline = null

func _exit_tree() -> void:
	_disconnect_target()
	clear()
	_baseline = null

## 有效的显式目标优先，其次使用父节点。
func resolve_target() -> Node:
	return target if is_instance_valid(target) else get_parent()

func _reset_binding() -> void:
	_disconnect_target()
	_baseline = null
	var source := resolve_target()
	if is_instance_valid(source):
		_watched = source
		_watched.script_changed.connect(_source_changed)
		_watched.property_list_changed.connect(_source_changed)
		if _watched is CanvasItem:
			_watched.visibility_changed.connect(_source_visibility_changed)
	_refresh_property()

func _sync_binding() -> void:
	var source := resolve_target()
	if not is_instance_valid(_watched) or _watched != source:
		_reset_binding()

func _disconnect_target() -> void:
	if is_instance_valid(_watched):
		if _watched.script_changed.is_connected(_source_changed):
			_watched.script_changed.disconnect(_source_changed)
		if _watched.property_list_changed.is_connected(_source_changed):
			_watched.property_list_changed.disconnect(_source_changed)
		if _watched is CanvasItem and _watched.visibility_changed.is_connected(_source_visibility_changed):
			_watched.visibility_changed.disconnect(_source_visibility_changed)
	_watched = null

func _source_visibility_changed() -> void:
	if skip_hidden_target:
		_baseline = null

func _source_changed() -> void:
	_baseline = null
	_refresh_property()

func _refresh_property() -> void:
	if _refreshing_property:
		return
	_refreshing_property = true
	_property_valid = list_value_properties().has(StringName(value_property))
	notify_property_list_changed()
	if is_inside_tree():
		update_configuration_warnings()
	_refreshing_property = false

func list_value_properties() -> Array[StringName]:
	return NumericPropertyChoices.list_properties(resolve_target(), include_builtin_properties)

func value_property_choices() -> PackedStringArray:
	return NumericPropertyChoices.choices(resolve_target(), include_builtin_properties, value_property)

func _validate_property(property: Dictionary) -> void:
	if property.name == "value_property":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(value_property_choices())

func _get_configuration_warnings() -> PackedStringArray:
	if not observe_enabled:
		return []
	if not is_instance_valid(resolve_target()):
		return ["选择 Target 或将本件挂在数值源下；事件驱动时可关闭观察器。"]
	if not list_value_properties().has(StringName(value_property)):
		return ["Value Property 请选择 int / float；原生参数可开启 Include Builtin Properties。"]
	return []

## 下一次有效读数建立新的静默基线。
func reset_baseline() -> void:
	_baseline = null
	_property_valid = list_value_properties().has(StringName(value_property))

## 采样业务变动后的净差额；接受的基线先于 number_emitted 更新。
func sample_now() -> void:
	if Engine.is_editor_hint():
		return
	_sync_binding()
	var source := resolve_target()
	if not observe_enabled or not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion():
		_baseline = null
		return
	if (skip_disabled_target and not source.can_process()) or (skip_hidden_target and source is CanvasItem and not source.is_visible_in_tree()):
		_baseline = null
		return
	if not _property_valid:
		_baseline = null
		return
	var current: Variant = source.get(value_property)
	if not _valid_number(current):
		_baseline = null
		return
	if _baseline == null:
		_baseline = current
		return
	# 整数减法保持 int64 精度，溢出时以当前读数重建基线。
	if current is int and _baseline is int:
		if (current >= 0 and _baseline < 0 and current > 9223372036854775807 + _baseline) or (current < 0 and _baseline > 0 and current < (-9223372036854775807 - 1) + _baseline):
			_baseline = current
			return
	var change: Variant = current - _baseline
	if not _valid_number(change):
		_baseline = current
		return
	if change == 0 or (change is float and absf(change) <= _nonnegative(epsilon, 0.00001)):
		return
	_baseline = current
	emit_delta(change)

func _valid_number(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value))

func _nonnegative(value: float, fallback: float) -> float:
	return maxf(value, 0.0) if is_finite(value) else fallback

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	sample_now()
	if is_instance_valid(self) and is_inside_tree():
		advance(delta)

## 手动时钟用于确定性回放；正常运行由 _process 推进。
func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_prune_active()
	for entry in _active.duplicate():
		if not _is_active_entry(entry):
			continue
		entry.age += delta
		if entry.age >= entry.duration:
			_active.erase(entry)
			_release_label(entry.label)
		else:
			_update_entry(entry)

## 接收差额，options 可覆写 color、font_size、position（本地锚点）。
## 零差额通过整数 zero_sign（-1 或 +1）显式声明事件方向，显示 -0 或 +0。
## 返回当前活动 Label；容量饱和可复用该节点，清理与到期会释放它。
## 信号回调同步清理或退出时返回 null。
func emit_delta(amount: Variant, options: Dictionary = {}) -> Label:
	if Engine.is_editor_hint() or _clearing or not is_inside_tree() or is_queued_for_deletion() or not _valid_number(amount):
		return null
	var zero_direction := 0
	if amount == 0:
		var requested_sign: Variant = options.get("zero_sign")
		if requested_sign is int and (requested_sign == -1 or requested_sign == 1):
			zero_direction = requested_sign
		else:
			return null
	var point := resolve_anchor_position()
	if options.has("position") and options.position is Vector2:
		point = options.position
	if not point.is_finite():
		return null
	_prune_active()
	var label: Label
	if _active.size() >= max_active:
		label = _active.pop_front().label
	else:
		label = Label.new()
		add_child(label)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.rotation = 0.0
	label.self_modulate = Color.WHITE
	label.text = ("+0" if zero_direction > 0 else "-0") if amount == 0 else format_delta(amount)
	label.add_theme_font_size_override("font_size", clampi(int(options.get("font_size", font_size)), 8, 160))
	label.add_theme_color_override("font_color", options.get("color", gain_color if amount > 0 or zero_direction > 0 else loss_color))
	label.add_theme_color_override("font_outline_color", outline_color)
	label.add_theme_constant_override("outline_size", clampi(outline_size, 0, 24))
	if font != null:
		label.add_theme_font_override("font", font)
	else:
		label.remove_theme_font_override("font")
	label.reset_size()
	var ratio := label_anchor_ratio.clamp(Vector2.ZERO, Vector2.ONE) if label_anchor_ratio.is_finite() else Vector2(0.5, 0.0)
	label.pivot_offset = label.size * ratio
	label.show()
	var rise_time := _nonnegative(rise_duration, 0.7)
	var fall_time := _nonnegative(fall_duration, 0.45) if motion == Motion.RISE_FALL else 0.0
	var motion_time := rise_time + fall_time
	var delay_time := _nonnegative(fade_delay, 0.2)
	var fade_time := _nonnegative(fade_duration, 0.55)
	var spawn_time := _nonnegative(spawn_duration, 0.18) if spawn_style != SpawnStyle.INSTANT else 0.0
	# RNG 每次先采样初始抖动，再采样轨迹侧移；reseed 可复现完整序列。
	var jitter := _rng.randf_range(-1.0, 1.0) * _nonnegative(jitter_x, 6.0)
	var side := _rng.randf_range(-1.0, 1.0) * _nonnegative(spread, 0.0)
	var entry := {"label": label, "age": 0.0,
		"duration": maxf(maxf(motion_time, delay_time + fade_time), spawn_time),
		"rise_duration": rise_time, "fall_duration": fall_time, "motion_duration": motion_time,
		"fade_delay": delay_time, "fade_duration": fade_time, "spawn_duration": spawn_time,
		"spawn_initial_scale": _nonnegative(spawn_initial_scale, 0.25),
		"origin": point + Vector2(jitter, 0) - label.size * ratio,
		"height": rise_height if is_finite(rise_height) else 28.0, "side": side,
		"fall_height": fall_height if is_finite(fall_height) else 28.0,
		"motion": motion, "spawn": spawn_style, "exit": disappear_style,
		"transition": clampi(rise_transition, Tween.TRANS_LINEAR, Tween.TRANS_SPRING),
		"fall_transition": clampi(fall_transition, Tween.TRANS_LINEAR, Tween.TRANS_SPRING)}
	_active.append(entry)
	_update_entry(entry)
	number_emitted.emit(amount, label)
	if not is_instance_valid(label) or not _is_active_entry(entry):
		return null
	if entry.duration == 0.0:
		_active.erase(entry)
		_release_label(label)
		return null
	return label

## 通过画布坐标换算 Control 顶边中心或 Node2D 原点，并应用局部偏移。
func resolve_anchor_position() -> Vector2:
	var resolved := resolve_target()
	var source: CanvasItem = anchor if is_instance_valid(anchor) else (resolved as CanvasItem)
	var local_offset := offset if offset.is_finite() else Vector2.ZERO
	if source == null or not source.is_inside_tree() or source.get_viewport() != get_viewport():
		return local_offset
	var origin := Vector2(source.size.x * 0.5, 0) if source is Control else Vector2.ZERO
	var transform := get_global_transform_with_canvas()
	if not transform.is_finite() or absf(transform.determinant()) < 0.000001:
		return local_offset
	var point := transform.affine_inverse() * (source.get_global_transform_with_canvas() * origin) + local_offset
	return point if point.is_finite() else local_offset

func _clock_progress(age: float, duration: float) -> float:
	return clampf(age / duration, 0.0, 1.0) if duration > 0.0 else 1.0

func _update_entry(entry: Dictionary) -> void:
	var t := _clock_progress(entry.age, entry.rise_duration)
	var move := Vector2.ZERO
	match entry.motion:
		Motion.RISE:
			var eased: float = Tween.interpolate_value(0.0, 1.0, t, 1.0, entry.transition, Tween.EASE_OUT)
			move = Vector2(entry.side * t * 0.2, -entry.height * eased)
		Motion.RISE_FALL:
			var ascent: float = Tween.interpolate_value(0.0, 1.0, t, 1.0, entry.transition, Tween.EASE_OUT)
			var fall := _clock_progress(entry.age - entry.rise_duration, entry.fall_duration) if entry.age >= entry.rise_duration else 0.0
			var descent: float = Tween.interpolate_value(0.0, 1.0, fall, 1.0, entry.fall_transition, Tween.EASE_IN)
			move = Vector2(entry.side * _clock_progress(entry.age, entry.motion_duration) * 0.2, -entry.height * ascent + entry.fall_height * descent)
		Motion.TOSS:
			move = Vector2(entry.side * t * 2.0, entry.height * (-4.0 * t + 5.0 * t * t))
		Motion.DRIFT:
			move = Vector2(sin(t * PI * 1.5) * entry.side, -entry.height * t)
		Motion.SPRING:
			move = Vector2(entry.side * t * 0.4, -entry.height * (1.0 - exp(-5.0 * t) * cos(t * PI * 3.0)))
	var alpha := 1.0
	var size_factor := 1.0
	var enter := _clock_progress(entry.age, entry.spawn_duration)
	match entry.spawn:
		SpawnStyle.POP:
			var q := enter - 1.0
			size_factor = entry.spawn_initial_scale + (1.0 - entry.spawn_initial_scale) * (1.0 + 2.70158 * q * q * q + 1.70158 * q * q)
		SpawnStyle.FADE:
			alpha *= enter
	var leave := _clock_progress(entry.age - entry.fade_delay, entry.fade_duration) if entry.age >= entry.fade_delay else 0.0
	alpha *= 1.0 - leave
	match entry.exit:
		DisappearStyle.SHRINK:
			size_factor *= 1.0 - leave * 0.85
		DisappearStyle.SINK:
			move.y += entry.height * 0.4 * leave * leave
	var label: Label = entry.label
	label.position = entry.origin + move
	label.scale = Vector2.ONE * size_factor
	label.modulate = Color(1, 1, 1, alpha)

func format_delta(amount: Variant) -> String:
	if not _valid_number(amount):
		return ""
	var result := str(amount) if amount is int else ("%.*f" % [clampi(precision, 0, 6), float(amount)])
	if amount is float and result.contains("."):
		while result.ends_with("0"):
			result = result.left(-1)
		if result.ends_with("."):
			result = result.left(-1)
	return ("+" if positive_prefix and amount > 0 else "") + result

func get_active_count() -> int:
	_prune_active()
	return _active.size()

func reseed(seed_value: int) -> void:
	_rng.seed = seed_value

func _is_active_entry(entry: Dictionary) -> bool:
	for current in _active:
		if is_same(current, entry):
			return true
	return false

func _prune_active() -> void:
	for index in range(_active.size() - 1, -1, -1):
		if not is_instance_valid(_active[index].label):
			_active.remove_at(index)

func _trim_active() -> void:
	_prune_active()
	while _active.size() > max_active:
		_release_label(_active.pop_front().label)

func _release_label(label: Label) -> void:
	if is_instance_valid(label):
		label.free()

## 同步释放本件创建的活动浮字；退出场景时自动执行。
func clear() -> void:
	if _clearing:
		return
	_clearing = true
	var entries := _active.duplicate()
	_active.clear()
	for entry in entries:
		_release_label(entry.label)
	_clearing = false
