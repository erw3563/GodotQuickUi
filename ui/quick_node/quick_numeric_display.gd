@tool
class_name QuickNumericDisplay
extends Control
## 数值显示控件，读取精确业务数值并独立驱动字形表现。
## 活动过渡连续播放，后续变动合并为最新目的数值。

signal value_changed(value: Variant)
signal transition_finished(value: Variant)
enum Transition { ROLL, POP, WIPE }
const Cell := preload("res://addons/gdbase/ui/quick_node/numeric_display_cell.gd")

@export_group("观察器（可选）")
@export var target: Node:
	set(value):
		target = value
		_reset_binding()
@export var value_property := "":
	set(value):
		value_property = value
		reset_baseline()
@export var observe_enabled := true:
	set(value):
		observe_enabled = value
		reset_baseline()
@export var include_builtin_properties := false:
	set(value):
		include_builtin_properties = value
		_source_changed()
@export var skip_hidden_target := true
@export var skip_disabled_target := true

@export_group("数值格式")
@export_range(0, 6, 1) var precision := 0:
	set(value):
		precision = clampi(value, 0, 6)
		_reformat()
@export var trim_trailing_zeros := true:
	set(value):
		trim_trailing_zeros = value
		_reformat()
@export var positive_prefix := false:
	set(value):
		positive_prefix = value
		_reformat()
@export var text_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT:
	set(value):
		text_alignment = value
		_refresh_visuals()

@export_group("字形样式")
@export var font: Font:
	set(value):
		if font != null and font.changed.is_connected(_style_changed):
			font.changed.disconnect(_style_changed)
		font = value
		if font != null and not font.changed.is_connected(_style_changed):
			font.changed.connect(_style_changed)
		_style_changed()
## 0 继承 Label 主题字号，字号设置作用于当前控件。
@export_range(0, 160, 1) var font_size := 48:
	set(value):
		font_size = clampi(value, 0, 160)
		_style_changed()
@export var font_color := Color.WHITE:
	set(value):
		font_color = value
		_refresh_visuals()
## 描边宽度同时计入字位间距与上下裁切留白。
@export_range(0, 24, 1) var outline_size := 0:
	set(value):
		outline_size = clampi(value, 0, 24)
		_style_changed()
@export var outline_color := Color.BLACK:
	set(value):
		outline_color = value
		_refresh_visuals()

@export_group("切换")
@export var transition: Transition = Transition.ROLL
@export_range(0.0, 2.0, 0.01) var animation_duration := 0.42
@export_range(0.0, 0.5, 0.01) var pop_strength := 0.18
## 0 is continuous; 8/12 gives a deliberately stepped wipe. Scoped to this display.
@export_range(0, 64, 1) var wipe_steps := 0
@export var tint_enabled := false
@export var gain_color := Color("71f0ad")
@export var loss_color := Color("ff6885")

@export_group("编辑器预览")
## 编辑器占位文本；运行期首次有效数值直接显示。
@export var preview_text := "120":
	set(value):
		preview_text = value.left(330)
		if Engine.is_editor_hint():
			_set_static(preview_text)

var _value: Variant = null
var _settled_value: Variant = null
var _active_value: Variant = null
var _baseline: Variant = null
var _watched: Node
var _property_valid := false
var _settled_text := ""
var _from_text := ""
var _to_text := ""
var _desired_text := ""
var _age := 0.0
var _duration := 0.0
var _animating := false
var _active_mode := 0
var _active_steps := 0
var _active_pop := 0.18
var _active_tint := false
var _active_color := Color.WHITE
var _direction := 1.0
var _glyphs: Control
var _cells: Array[Control] = []
var _entries: Array[Dictionary] = []
var _layout_width := 0.0
var _cell_width := 0.0
var _line_height := 0.0
var _refreshing := false
var _suspended := false
var _refreshing_source := false

func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE

func _enter_tree() -> void:
	# 重新进入场景树时同步绑定与字形状态。
	if is_node_ready():
		_tree_sync()

func _ready() -> void:
	_ensure_glyphs()
	_reset_binding()
	if Engine.is_editor_hint():
		_set_static(preview_text)
	elif _value == null:
		_set_static("0")
	else:
		finish()
	sample_now()

func _tree_sync() -> void:
	if not is_inside_tree():
		return
	_ensure_glyphs()
	_reset_binding()
	_style_changed()
	sample_now()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		_style_changed()
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_inside_tree() and not is_visible_in_tree():
			_suspend()
		elif is_inside_tree():
			_baseline = null
	elif what == NOTIFICATION_PAUSED or what == NOTIFICATION_DISABLED:
		_suspend()
	elif what == NOTIFICATION_UNPAUSED or what == NOTIFICATION_ENABLED:
		_baseline = null

func _exit_tree() -> void:
	_disconnect_target()
	_suspend()

func _suspend() -> void:
	finish()
	_baseline = null
	_suspended = true

func _reset_binding() -> void:
	reset_baseline()
	_disconnect_target()
	if is_instance_valid(target):
		_watched = target
		_watched.script_changed.connect(_source_changed)
		_watched.property_list_changed.connect(_source_changed)
		if _watched is CanvasItem:
			_watched.visibility_changed.connect(_source_visibility_changed)
	_source_changed()

func _disconnect_target() -> void:
	if is_instance_valid(_watched):
		for pair in [[_watched.script_changed, _source_changed], [_watched.property_list_changed, _source_changed]]:
			if pair[0].is_connected(pair[1]):
				pair[0].disconnect(pair[1])
		if _watched is CanvasItem and _watched.visibility_changed.is_connected(_source_visibility_changed):
			_watched.visibility_changed.disconnect(_source_visibility_changed)
	_watched = null

func _source_visibility_changed() -> void:
	if skip_hidden_target:
		_suspend()

func _source_changed() -> void:
	if _refreshing_source:
		return
	_refreshing_source = true
	reset_baseline()
	notify_property_list_changed()
	if is_inside_tree():
		update_configuration_warnings()
	_refreshing_source = false

func reset_baseline() -> void:
	finish()
	_baseline = null
	_property_valid = list_value_properties().has(StringName(value_property))

func list_value_properties() -> Array[StringName]:
	return NumericPropertyChoices.list_properties(target, include_builtin_properties)

func value_property_choices() -> PackedStringArray:
	return NumericPropertyChoices.choices(target, include_builtin_properties, value_property)

func _validate_property(property: Dictionary) -> void:
	if property.name == "value_property":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(value_property_choices())

func _get_configuration_warnings() -> PackedStringArray:
	if not observe_enabled:
		return []
	if target == null:
		return []
	if not is_instance_valid(target):
		return ["Target 已失效，请重新选择数值源。"]
	if not list_value_properties().has(StringName(value_property)):
		return ["Value Property 必须是可选 int / float；原生数值请开启 Include Builtin Properties。"]
	return []

func sample_now() -> void:
	if Engine.is_editor_hint() or not observe_enabled:
		return
	# 空绑定控件通过 set_value 接收显示数值。
	if target == null:
		return
	if not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion() or not _property_valid:
		_suspend()
		return
	if not is_visible_in_tree() or not can_process() or (skip_disabled_target and not target.can_process()) or (skip_hidden_target and target is CanvasItem and not target.is_visible_in_tree()):
		_suspend()
		return
	var current: Variant = target.get(value_property)
	if not _valid_number(current):
		_suspend()
		return
	var baseline_missing := _baseline == null
	_baseline = current
	_suspended = false
	set_value(current, not baseline_missing)

## 接受最新显示数值；非法输入返回 false。
## int 保持整数格式化，重复值延续当前演出。
func set_value(value: Variant, animate := true) -> bool:
	if not _valid_number(value):
		return false
	var initial := _value == null
	var changed: bool = initial or value != _value or typeof(value) != typeof(_value)
	_value = value
	_desired_text = format_value(value)
	if initial or not animate or not is_inside_tree() or not is_visible_in_tree() or not can_process():
		finish()
	elif not _animating and _settled_text != _desired_text:
		_begin()
	elif not _animating:
		_settled_value = value
	# 活动演出连续完成，边界处衔接最新目的数值。
	if changed:
		value_changed.emit(value)
	return true

func get_value() -> Variant:
	return _value

## Latest exact formatted value. The visible reel can still be in transit.
func get_display_text() -> String:
	return _desired_text

func is_animating() -> bool:
	return _animating

func format_value(value: Variant) -> String:
	if not _valid_number(value):
		return "—"
	var result: String
	if value is int:
		result = str(value)
		if not trim_trailing_zeros and precision > 0:
			result += "." + "0".repeat(precision)
	else:
		result = ("%." + str(precision) + "f") % value
		if trim_trailing_zeros and result.contains("."):
			while result.ends_with("0"):
				result = result.left(-1)
			if result.ends_with("."):
				result = result.left(-1)
		# Suppress the misleading negative sign when rounded magnitude is zero.
		if result.begins_with("-") and result.to_float() == 0.0:
			result = result.substr(1)
	if positive_prefix and not result.begins_with("-"):
		result = "+" + result
	return result

func _valid_number(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value))

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	sample_now()
	advance(delta)

## Deterministic manual clock; disable _process before calling manually.
func advance(delta: float) -> void:
	if not _animating or not is_finite(delta) or delta <= 0.0:
		return
	_age += delta
	if _age >= _duration:
		# 推进当前段及最新目的段。
		var remainder := _age - _duration
		_settled_value = _active_value
		_set_static(_to_text)
		if _settled_text != _desired_text:
			_begin()
			if _animating and remainder > 0.0:
				advance(remainder)
		else:
			_settled_value = _value
			transition_finished.emit(_value)
	else:
		_refresh_visuals()

## 完成显示演出并展示最新精确数值。
func finish() -> void:
	if _value != null:
		_settled_value = _value
		_set_static(_desired_text)
	else:
		_animating = false
		_refresh_visuals()

func _begin() -> void:
	if _settled_text == _desired_text:
		return
	_from_text = _settled_text
	_to_text = _desired_text
	_active_value = _value
	# Comparison rather than subtraction avoids int64 delta overflow.
	_direction = -1.0 if _settled_value != null and _value < _settled_value else 1.0
	_duration = clampf(animation_duration, 0.0, 2.0) if is_finite(animation_duration) else 0.0
	_active_mode = clampi(transition, 0, 2)
	_active_steps = clampi(wipe_steps, 0, 64)
	_active_pop = clampf(pop_strength, 0.0, 0.5) if is_finite(pop_strength) else 0.18
	_active_tint = tint_enabled
	_active_color = gain_color if _direction > 0 else loss_color
	_age = 0.0
	_animating = _duration > 0.0
	if not _animating:
		finish()
		transition_finished.emit(_value)
		return
	_build_entries()
	_refresh_visuals()

func _set_static(text: String) -> void:
	_animating = false
	_settled_text = text
	_from_text = text
	_to_text = text
	_age = 0.0
	_build_entries()
	_refresh_visuals()

func _reformat() -> void:
	if _value != null:
		_desired_text = format_value(_value)
		finish()

func _ensure_glyphs() -> void:
	if is_instance_valid(_glyphs):
		return
	_glyphs = get_node_or_null("Glyphs") as Control
	if _glyphs == null:
		_glyphs = Control.new()
		_glyphs.name = "Glyphs"
		add_child(_glyphs, false, Node.INTERNAL_MODE_BACK)
	_glyphs.mouse_filter = MOUSE_FILTER_IGNORE

## Numeric place keys keep units/decimals aligned through 9→10, 99→100 and shrinking.
func _places(text: String) -> Dictionary:
	var result := {}
	var decimal := text.find(".")
	if decimal < 0:
		decimal = text.length()
	for i in text.length():
		var glyph := text.substr(i, 1)
		var key := "sign" if glyph in ["+", "-"] else ("dot" if glyph == "." else str(decimal - i - 1 if i < decimal else decimal - i))
		result[key] = {"glyph": glyph, "index": i}
	return result

func _build_entries() -> void:
	_entries.clear()
	var before := _places(_from_text)
	var after := _places(_to_text)
	var keys := before.keys()
	for key in after:
		if not keys.has(key):
			keys.append(key)
	for key in keys:
		var a: Dictionary = before.get(key, {})
		var b: Dictionary = after.get(key, {})
		_entries.append({"key": key, "old": a.get("glyph", ""), "new": b.get("glyph", ""), "from": a.get("index", b.get("index", 0)), "to": b.get("index", a.get("index", 0)), "old_present": not a.is_empty(), "new_present": not b.is_empty()})

func _style_changed() -> void:
	if not is_inside_tree():
		return
	_refresh_visuals()
	update_minimum_size()

func _font() -> Font:
	return font if font != null else get_theme_font("font", "Label")

func _font_size() -> int:
	return maxi(1, font_size if font_size > 0 else get_theme_font_size("font_size", "Label"))

func _get_minimum_size() -> Vector2:
	var face := _font()
	if face == null:
		return Vector2.ZERO
	var point := _font_size()
	var width := face.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, point).x
	for glyph in "123456789+-.—":
		width = maxf(width, face.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, point).x)
	var padding := float(outline_size * 2)
	return Vector2((ceilf(width) + padding) * maxi(_from_text.length(), _to_text.length()), ceilf(face.get_height(point)) + 4.0 + padding)

func _start_x(length: int) -> float:
	if text_alignment == HORIZONTAL_ALIGNMENT_LEFT:
		return 0.0
	if text_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		return (size.x - length * _cell_width) * 0.5
	return size.x - length * _cell_width

func _refresh_visuals() -> void:
	if not is_inside_tree() or _refreshing:
		return
	_refreshing = true
	_ensure_glyphs()
	var face := _font()
	var point := _font_size()
	_cell_width = 0.0
	for glyph in "0123456789+-.—":
		_cell_width = maxf(_cell_width, face.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, point).x)
	var padding := float(outline_size * 2)
	_cell_width = ceilf(_cell_width) + padding
	_line_height = ceilf(face.get_height(point)) + 4.0 + padding
	while _cells.size() < _entries.size():
		var cell := Cell.new()
		_glyphs.add_child(cell, false, Node.INTERNAL_MODE_BACK)
		_cells.append(cell)
	# 字符节点容量随当前段的字位数量收缩。
	while _cells.size() > _entries.size():
		var cell: Control = _cells.pop_back()
		cell.free()
	var raw := clampf(_age / _duration, 0, 1) if _animating else 1.0
	var p := 1.0 - pow(1.0 - raw, 3.0)
	var color := font_color
	if _animating and _active_tint:
		color = _active_color.lerp(font_color, p)
		color.a = font_color.a
	var from_x := _start_x(_from_text.length())
	var to_x := _start_x(_to_text.length())
	var left := minf(from_x, to_x)
	var right := maxf(from_x + _from_text.length() * _cell_width, to_x + _to_text.length() * _cell_width)
	_layout_width = right - left
	var wipe := p
	if _active_steps > 0 and raw < 1.0:
		wipe = floorf(p * _active_steps) / _active_steps
	_glyphs.size = size
	_glyphs.position = Vector2.ZERO
	_glyphs.pivot_offset = Vector2((left + right) * 0.5, size.y * 0.5)
	_glyphs.scale = Vector2.ONE
	if _animating and _active_mode == Transition.POP:
		# 内部字形执行压缩、过冲及回正。
		var pulse := sin(raw * PI * 2.0) * pow(1.0 - raw, 2.0)
		_glyphs.scale = Vector2(1.0 + pulse * _active_pop, 1.0 - pulse * _active_pop * 0.7)
	for i in _entries.size():
		var entry := _entries[i]
		var cell = _cells[i]
		var x0: float = from_x + entry.from * _cell_width
		var x1: float = to_x + entry.to * _cell_width
		if not entry.old_present:
			x0 = x1
		if not entry.new_present:
			x1 = x0
		cell.position = Vector2(lerpf(x0, x1, p), (size.y - _line_height) * 0.5)
		cell.size = Vector2(_cell_width, _line_height)
		cell.old_glyph = entry.old
		cell.new_glyph = entry.new
		cell.face = face
		cell.point_size = point
		cell.ink = color
		cell.outline_size = outline_size
		cell.outline_color = outline_color
		cell.progress = p
		cell.direction = _direction
		cell.mode = _active_mode if _animating else Transition.ROLL
		var edge := left + _layout_width * wipe if _direction > 0 else right - _layout_width * wipe
		cell.wipe_fraction = clampf((edge - cell.position.x) / _cell_width if _direction > 0 else (cell.position.x + _cell_width - edge) / _cell_width, 0.0, 1.0)
		cell.refresh()
	_refreshing = false
	update_minimum_size()

## 返回用于测试和集成的只读数值、字位及演出状态快照。
func debug_state() -> Dictionary:
	var glyphs: Array[Dictionary] = []
	for i in _entries.size():
		var cell = _cells[i] if i < _cells.size() else null
		glyphs.append({"key": _entries[i].key, "old": _entries[i].old, "new": _entries[i].new, "position": cell.position if cell != null else Vector2.ZERO, "progress": cell.progress if cell != null else 1.0})
	return {"value": _value, "latest_text": _desired_text, "settled_text": _settled_text, "active_text": _to_text, "animating": _animating, "pending": _animating and _desired_text != _to_text, "age": _age, "duration": _duration, "direction": _direction, "cells": _cells.size(), "glyphs": glyphs, "internal_scale": _glyphs.scale if is_instance_valid(_glyphs) else Vector2.ONE, "baseline": _baseline}
