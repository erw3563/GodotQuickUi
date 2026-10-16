@tool
extends Control
## 内部字符卷轴，负责绘制和裁剪当前数值字形。
var old_glyph := ""
var new_glyph := ""
var face: Font
var point_size := 48
var ink := Color.WHITE
var outline_size := 0
var outline_color := Color.BLACK
var progress := 1.0
var direction := 1.0
var mode := 0
var wipe_fraction := 0.0
var _old_clip: Control
var _new_clip: Control
var _old_label: Label
var _new_label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func refresh() -> void:
	if mode == 2 and old_glyph != new_glyph and progress < 1.0:
		_ensure_wipe()
		var width := size.x * clampf(wipe_fraction, 0.0, 1.0)
		var left := direction > 0.0
		_new_clip.position = Vector2(0 if left else size.x - width, 0)
		_new_clip.size = Vector2(width, size.y)
		_old_clip.position = Vector2(width if left else 0, 0)
		_old_clip.size = Vector2(size.x - width, size.y)
		for pair in [[_old_clip, _old_label, old_glyph], [_new_clip, _new_label, new_glyph]]:
			var holder: Control = pair[0]
			var label: Label = pair[1]
			holder.visible = holder.size.x > 0.0
			label.text = pair[2]
			label.add_theme_font_override("font", face)
			label.add_theme_font_size_override("font_size", point_size)
			label.add_theme_color_override("font_color", ink)
			label.add_theme_constant_override("outline_size", outline_size)
			label.add_theme_color_override("font_outline_color", outline_color)
			# 当前字体度量决定 Label 的最小尺寸与居中位置。
			label.size = size
			label.position = -holder.position
	else:
		if is_instance_valid(_old_clip):
			_old_clip.hide()
			_new_clip.hide()
	queue_redraw()

func _ensure_wipe() -> void:
	if is_instance_valid(_old_clip):
		return
	_old_clip = Control.new()
	_new_clip = Control.new()
	_old_label = Label.new()
	_new_label = Label.new()
	for pair in [[_old_clip, _old_label], [_new_clip, _new_label]]:
		var holder: Control = pair[0]
		var label: Label = pair[1]
		holder.clip_contents = true
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.clip_text = true
		label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
		holder.add_child(label)
		add_child(holder)

func _draw() -> void:
	if face == null:
		return
	var baseline := (size.y - face.get_height(point_size)) * 0.5 + face.get_ascent(point_size)
	if old_glyph == new_glyph or progress >= 1.0 or mode == 1:
		_glyph(new_glyph, baseline)
	elif mode == 0:
		_glyph(old_glyph, baseline - direction * size.y * progress)
		_glyph(new_glyph, baseline + direction * size.y * (1.0 - progress))

func _glyph(value: String, baseline: float) -> void:
	if not value.is_empty():
		var width := face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size).x
		var origin := Vector2((size.x - width) * 0.5, baseline)
		if outline_size > 0:
			draw_string_outline(face, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size, outline_size, outline_color)
		draw_string(face, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size, ink)
