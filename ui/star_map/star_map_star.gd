@tool
class_name StarMapStar
extends Node2D
## Level identity and interaction state stay independent from per-node appearance.
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
var view_zoom := 1.0
var visual_instance: LevelNodeVisual
var _clip: Control
var _slot: Node2D

func _init() -> void:
	style = null

func _default_style() -> LevelNodeStyle:
	var result := LevelNodeStyle.new()
	result.size = Vector2(18, 18)
	return result

func _ready() -> void:
	refresh_visual()

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

func sync_presentation() -> void:
	var z := maxf(view_zoom, 0.35) if is_finite(view_zoom) else 1.0
	var box := appearance_size() / maxf(z, 0.8)
	if is_instance_valid(_clip):
		_clip.position = -box * .5
		_clip.size = box
	if is_instance_valid(visual_instance):
		visual_instance.position = box * .5
		visual_instance.scale = box
		visual_instance.set_presentation({"selected":selected,"current":current,"hovered":hovered,"zoom":z,"size":appearance_size(),"tint":style.color,"accent":style.accent,"decoration":style.decoration,"preset":style.preset,"texture":style.texture})
	queue_redraw()

func _draw() -> void:
	var z := maxf(view_zoom, 0.35) if is_finite(view_zoom) else 1.0
	var box := appearance_size() / maxf(z, .8)
	var ink := Color("eee2c6")
	# Quiet underline + bookmark keep interaction visible for any custom silhouette.
	if selected or hovered:
		var y := box.y * .5 + 5 / z
		draw_line(Vector2(-box.x*.6,y),Vector2(box.x*.6,y),Color(ink,1 if selected else .5),(2.0 if selected else 1.0)/z,true)
	if current:
		var y := -box.y*.5 - 7/z
		draw_colored_polygon(PackedVector2Array([Vector2(-3/z,y-5/z),Vector2(3/z,y-5/z),Vector2(3/z,y+2/z),Vector2(0,y),Vector2(-3/z,y+2/z)]),Color("dcc185"))
	if z >= .73 or selected or hovered or current:
		draw_set_transform(Vector2(0, box.y*.5 + 10/z),0,Vector2.ONE/z)
		var font := ThemeDB.fallback_font
		var text_size := font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,13)
		draw_string(font,Vector2(-text_size.x/2,12),title,HORIZONTAL_ALIGNMENT_LEFT,-1,13,ink if selected or hovered else Color("b9b8a5"))
		if current: draw_string(font,Vector2(-15,27),"HERE",HORIZONTAL_ALIGNMENT_LEFT,-1,8,Color("dcc185"))
