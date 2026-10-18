@tool
class_name StarMapStar
extends Node2D
## Level identity and interaction state stay independent from per-node appearance.

## 节点进度状态：由宿主（如游戏适配层）写入，决定状态描边、角标与标签色。
## NORMAL 为不区分状态的默认表现。
enum Status { NORMAL, AVAILABLE, COMPLETED, LOCKED }

@export var title := "Unnamed level"
@export var region_id := "verdant"
@export var category := "encounter"
@export var style: LevelNodeStyle:
	set(value):
		if style != null and style.changed.is_connected(refresh_visual):
			style.changed.disconnect(refresh_visual)
		style = value.duplicate(true) if value != null else _default_style()
		style.changed.connect(refresh_visual)
		if is_inside_tree():
			refresh_visual()
var selected := false
var current := false
var hovered := false
var status: Status = Status.NORMAL
var view_zoom := 1.0
## 由所属星图视图下发；为空时使用默认样式。
var palette: StarMapPalette
## 主题字体解析上下文（所属星图视图）。
var font_context: Control
var visual_instance: LevelNodeVisual
var _clip: Control
var _slot: Node2D
var _overlay: Node2D
var _emphasis := 1.0

func _init() -> void:
	style = null

func _default_style() -> LevelNodeStyle:
	var result := LevelNodeStyle.new()
	result.size = Vector2(18, 18)
	return result

func _ready() -> void:
	refresh_visual()

func get_palette() -> StarMapPalette:
	return palette if palette != null else StarMapPalette.get_default()

func refresh_visual() -> void:
	if not is_inside_tree():
		return
	_slot = get_node_or_null("VisualSlot") as Node2D
	if not is_instance_valid(_slot):
		_slot = Node2D.new()
		_slot.name = "VisualSlot"
		add_child(_slot)
		_slot.owner = owner if owner != null else self
	if not is_instance_valid(_clip):
		_clip = _slot.get_node_or_null("AppearanceClip") as Control
	if is_instance_valid(_clip):
		if _clip.get_parent() != null:
			_clip.get_parent().remove_child(_clip)
		_clip.queue_free()
	_clip = Control.new()
	_clip.name = "AppearanceClip"
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot.add_child(_clip)
	_clip.owner = owner if owner != null else self
	visual_instance = null
	if style.visual_scene != null:
		var candidate: Node
		if style.visual_scene.can_instantiate():
			candidate = style.visual_scene.instantiate()
		if candidate is LevelNodeVisual:
			visual_instance = candidate
		else:
			if is_instance_valid(candidate):
				candidate.free()
			push_warning("Level visual scene requires an instantiable LevelNodeVisual root. Using the style texture or preset.")
	if visual_instance == null:
		visual_instance = preload("res://addons/gdbase/ui/star_map/level_node_glyph.gd").new()
	visual_instance.name = "LevelVisual"
	_clip.add_child(visual_instance)
	visual_instance.owner = owner if owner != null else self
	_disable_visual_input(visual_instance)
	if not is_instance_valid(_overlay):
		# 角标画在外观之上；内部节点不随场景保存。
		_overlay = Node2D.new()
		_overlay.name = "StatusOverlay"
		add_child(_overlay, false, Node.INTERNAL_MODE_BACK)
		_overlay.draw.connect(_draw_overlay)
	sync_presentation()

func _disable_visual_input(node: Node) -> void:
	# The map owns pointer and keyboard input throughout the appearance tree.
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	node.set_process_shortcut_input(false)
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.focus_mode = Control.FOCUS_NONE
	if node is CollisionObject2D: node.input_pickable = false
	for child in node.get_children(): _disable_visual_input(child)

func appearance_size() -> Vector2:
	return style.bounded_size()

func _zoom() -> float:
	return maxf(view_zoom, 0.35) if is_finite(view_zoom) else 1.0

## 当前外观框（含悬停 / 选中放大）。
func _box() -> Vector2:
	return appearance_size() / maxf(_zoom(), 0.8) * _emphasis

func _update_emphasis() -> void:
	var p := get_palette()
	var target := p.selected_scale if selected else (p.hover_scale if hovered else 1.0)
	if p.emphasis_speed <= 0.0 or not is_inside_tree():
		_emphasis = target
		return
	var delta := minf(get_process_delta_time(), 0.1)
	_emphasis = lerpf(_emphasis, target, 1.0 - exp(-p.emphasis_speed * delta))
	if absf(_emphasis - target) < 0.002:
		_emphasis = target

func _status_modulate(p: StarMapPalette) -> Color:
	match status:
		Status.AVAILABLE: return p.available_modulate
		Status.COMPLETED: return p.completed_modulate
		Status.LOCKED: return p.locked_modulate
	return Color.WHITE

func sync_presentation() -> void:
	_update_emphasis()
	var p := get_palette()
	var z := _zoom()
	var box := _box()
	if is_instance_valid(_slot):
		_slot.modulate = _status_modulate(p)
	if is_instance_valid(_clip):
		_clip.position = -box * .5
		_clip.size = box
	if is_instance_valid(visual_instance):
		visual_instance.position = box * .5
		visual_instance.scale = box
		visual_instance.set_presentation({"selected":selected,"current":current,"hovered":hovered,"zoom":z,"size":appearance_size(),"tint":style.color,"accent":style.accent,"decoration":style.decoration,"preset":style.preset,"texture":style.texture,"dark":p.glyph_dark_color,"status":status})
	queue_redraw()
	if is_instance_valid(_overlay):
		_overlay.queue_redraw()

func _label_color(p: StarMapPalette) -> Color:
	if selected or hovered:
		return p.label_active_color
	var by_status := Color(0, 0, 0, 0)
	match status:
		Status.AVAILABLE: by_status = p.available_label_color
		Status.COMPLETED: by_status = p.completed_label_color
		Status.LOCKED: by_status = p.locked_label_color
	return by_status if by_status.a > 0.0 else p.label_color

func _draw() -> void:
	var p := get_palette()
	var z := _zoom()
	var box := _box()
	var radius := box.length() * 0.5
	if (selected or hovered) and p.halo_color.a > 0.0:
		# 由外向内叠几层低透明圆，形成柔光。
		var layers := 4
		for i in layers:
			var t := float(i) / layers
			draw_circle(Vector2.ZERO, radius * lerpf(p.halo_radius, 0.9, t), Color(p.halo_color, p.halo_color.a * (0.35 if selected else 0.22)))
	var ring := Color(0, 0, 0, 0)
	if status == Status.AVAILABLE:
		ring = p.available_ring_color
	if ring.a > 0.0:
		draw_arc(Vector2.ZERO, radius + 3 / z, 0, TAU, 48, ring, p.state_ring_width / z, true)
	if selected and p.selected_ring_color.a > 0.0:
		draw_arc(Vector2.ZERO, radius + 6 / z, 0, TAU, 48, p.selected_ring_color, p.selected_ring_width / z, true)
	# Quiet underline + bookmark keep interaction visible for any custom silhouette.
	if p.underline and (selected or hovered):
		var y := box.y * .5 + 5 / z
		draw_line(Vector2(-box.x*.6,y),Vector2(box.x*.6,y),Color(p.label_active_color,1 if selected else .5),(2.0 if selected else 1.0)/z,true)
	if current:
		var y := -box.y*.5 - 7/z
		draw_colored_polygon(PackedVector2Array([Vector2(-3/z,y-5/z),Vector2(3/z,y-5/z),Vector2(3/z,y+2/z),Vector2(0,y),Vector2(-3/z,y+2/z)]),p.current_color)
	if z >= .73 or selected or hovered or current:
		var label_y := maxf(box.y, appearance_size().y / maxf(z, .8)) * .5 + 10/z
		draw_set_transform(Vector2(0, label_y),0,Vector2.ONE/z)
		var font := p.resolve_font(font_context)
		var text_size := font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,p.label_font_size)
		draw_string(font,Vector2(-text_size.x/2,12),title,HORIZONTAL_ALIGNMENT_LEFT,-1,p.label_font_size,_label_color(p))
		if current: draw_string(font,Vector2(-15,27),p.current_text,HORIZONTAL_ALIGNMENT_LEFT,-1,p.current_font_size,p.current_color)

## 状态角标：画在外观之上（已完成为勾，锁定为锁形）。
func _draw_overlay() -> void:
	var p := get_palette()
	var z := _zoom()
	var box := _box()
	var corner := Vector2(box.x * .5, -box.y * .5) + Vector2(1, -1) / z
	var r := 5.5 / z
	if status == Status.COMPLETED and p.completed_badge_color.a > 0.0:
		_overlay.draw_circle(corner, r, p.completed_badge_color)
		_overlay.draw_polyline(PackedVector2Array([corner + Vector2(-2.6, 0.2) / z, corner + Vector2(-0.6, 2.2) / z, corner + Vector2(2.8, -2.0) / z]), p.completed_badge_ink, 1.4 / z, true)
	elif status == Status.LOCKED and p.locked_badge_color.a > 0.0:
		var body := Rect2(corner + Vector2(-3.5, -1.0) / z, Vector2(7, 5.5) / z)
		_overlay.draw_arc(corner + Vector2(0, -1.2) / z, 2.4 / z, PI, TAU, 12, p.locked_badge_color, 1.2 / z, true)
		_overlay.draw_rect(body, p.locked_badge_color)
