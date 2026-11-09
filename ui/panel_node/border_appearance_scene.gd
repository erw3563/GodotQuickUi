@tool
class_name BorderAppearanceScene
extends DecoratedNinePatchPanel
## 边框场景的外观接口。制作引用由场景显式声明，运行时与编辑器消费相同对象。
@export var border_surfaces: Array[Control] = []
@export var decorations: Array[BorderDecoration] = []
@export var appearance_provider: BorderAppearanceScene
@export var decoration_parent: Control
@export var decoration_template: PackedScene
@export var thickness_editable := false
@export var next_decoration_id := 1

func get_decorations() -> Array[BorderDecoration]:
	return appearance_provider.get_decorations() if appearance_provider != null else decorations.duplicate()

func get_decoration(id: StringName) -> BorderDecoration:
	for decoration in get_decorations():
		if decoration.appearance_id == id: return decoration
	return null

func can_add_decoration() -> bool:
	return appearance_provider.can_add_decoration() if appearance_provider != null else decoration_parent != null and decoration_template != null

## 场景决定装饰模板与挂载点，调用方提供本次保存的场景所有者。
func add_decoration(scene_owner: Node) -> BorderDecoration:
	if appearance_provider != null: return appearance_provider.add_decoration(scene_owner)
	if not can_add_decoration(): return null
	var decoration := decoration_template.instantiate() as BorderDecoration
	decoration.appearance_id = StringName("decoration_%s" % next_decoration_id)
	decoration.name = String(decoration.appearance_id)
	decoration.display_name = "装饰 %s" % next_decoration_id
	next_decoration_id += 1
	decoration_parent.add_child(decoration)
	decoration.owner = scene_owner
	decorations.append(decoration)
	return decoration

func get_border_style() -> Dictionary:
	var values := {"color": Color.WHITE, "texture": null, "thickness": 0.0, "decoration": false}
	var fields := PackedStringArray()
	if appearance_provider != null:
		values = appearance_provider.get_border_style()
		fields = values.editable_fields.duplicate()
	elif not border_surfaces.is_empty():
		fields.append_array(PackedStringArray(["color", "texture"]))
		var surface := border_surfaces[0]
		var supports_thickness := thickness_editable
		values.color = surface.self_modulate
		if surface is NinePatchRect or surface is TextureRect:
			values.texture = surface.texture
			values.thickness = surface.patch_margin_left if surface is NinePatchRect else 0.0
			supports_thickness = thickness_editable and surface is NinePatchRect
		elif surface is Panel or surface is PanelContainer:
			var style := surface.get_theme_stylebox("panel")
			supports_thickness = thickness_editable and style is StyleBoxFlat
			if style is StyleBoxTexture: values.texture = style.texture
			if style is StyleBoxFlat: values.thickness = style.border_width_left
		if values.texture is AtlasTexture: values.texture = values.texture.atlas
		if supports_thickness: fields.append("thickness")
	if frame != null:
		fields.append_array(PackedStringArray(["left", "top", "right", "bottom"]))
	var outer: Control = frame if frame != null else self
	values.merge({"left": -outer.offset_left if frame != null else 0.0, "top": -outer.offset_top if frame != null else 0.0, "right": outer.offset_right if frame != null else 0.0, "bottom": outer.offset_bottom if frame != null else 0.0, "editable_fields": fields}, true)
	return values

func set_border_style(values: Dictionary) -> void:
	if appearance_provider != null:
		var presentation := values.duplicate()
		for key in ["left", "top", "right", "bottom"]: presentation.erase(key)
		appearance_provider.set_border_style(presentation)
	else:
		for surface in border_surfaces:
			if values.has("color"): surface.self_modulate = values.color
			if values.has("texture"):
				if surface is NinePatchRect or surface is TextureRect:
					var texture: Texture2D = values.texture
					if surface.texture is AtlasTexture:
						var atlas := AtlasTexture.new()
						atlas.atlas = texture
						atlas.region = surface.texture.region
						texture = atlas
					surface.texture = texture
				elif surface is Panel or surface is PanelContainer:
					var style := StyleBoxTexture.new()
					style.texture = values.texture
					surface.add_theme_stylebox_override("panel", style)
			if values.has("thickness") and thickness_editable:
				if surface is NinePatchRect:
					for side in 4: surface.set_patch_margin(side, int(values.thickness))
				elif surface is Panel or surface is PanelContainer:
					var style := surface.get_theme_stylebox("panel").duplicate(false) as StyleBox
					if style is StyleBoxFlat: style.set_border_width_all(int(values.thickness))
					surface.add_theme_stylebox_override("panel", style)
	if frame != null:
		if values.has("left"): frame.offset_left = -values.left
		if values.has("top"): frame.offset_top = -values.top
		if values.has("right"): frame.offset_right = values.right
		if values.has("bottom"): frame.offset_bottom = values.bottom
	update_minimum_size()

func get_decoration_at(canvas_point: Vector2) -> BorderDecoration:
	var ordered := get_decorations()
	ordered.reverse()
	for decoration in ordered:
		if decoration.contains_canvas_point(canvas_point): return decoration
	return null

func get_appearance_rect(id: StringName = &"") -> Rect2:
	var decoration := get_decoration(id) if not id.is_empty() else null
	if decoration != null:
		return get_global_transform().affine_inverse() * decoration.get_global_transform() * Rect2(Vector2.ZERO, decoration.size)
	return get_frame_rect()

func get_frame_rect() -> Rect2:
	var bounds := super.get_frame_rect()
	for decoration in get_decorations():
		bounds = bounds.merge(get_global_transform().affine_inverse() * decoration.get_global_transform() * Rect2(Vector2.ZERO, decoration.size))
	return bounds

## 内容区与外框之间的四边留白，坐标属于本场景。
func get_spacing_rect(side: int) -> Rect2:
	var outer := frame.get_rect() if frame != null else Rect2(Vector2.ZERO, size)
	var content := Rect2(Vector2.ZERO, size)
	match side:
		SIDE_LEFT: return Rect2(Vector2(outer.position.x, 0), Vector2(maxf(-outer.position.x, 0), size.y))
		SIDE_TOP: return Rect2(Vector2(0, outer.position.y), Vector2(size.x, maxf(-outer.position.y, 0)))
		SIDE_RIGHT: return Rect2(Vector2(content.end.x, 0), Vector2(maxf(outer.end.x - size.x, 0), size.y))
		SIDE_BOTTOM: return Rect2(Vector2(0, content.end.y), Vector2(size.x, maxf(outer.end.y - size.y, 0)))
	return Rect2()

## 装饰优先，其次是外框边缘和内侧留白。edge_width 为场景局部坐标中的命中宽度。
func get_border_hit(canvas_point: Vector2, edge_width: float) -> Dictionary:
	var decoration := get_decoration_at(canvas_point)
	if decoration != null: return {"kind": "decoration", "decoration_id": decoration.appearance_id}
	var point := get_global_transform().affine_inverse() * canvas_point
	var outer := frame.get_rect() if frame != null else Rect2(Vector2.ZERO, size)
	if not outer.has_point(point) or Rect2(Vector2.ZERO, size).has_point(point): return {}
	if outer.grow(-edge_width).has_point(point):
		for side in 4:
			if get_spacing_rect(side).has_point(point): return {"kind": "spacing", "side": side, "decoration_id": &""}
	return {"kind": "style", "decoration_id": &""}
