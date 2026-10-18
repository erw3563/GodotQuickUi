@tool
class_name StarMapRegion
extends Node2D
## All children move together with the arithmetic centroid of current members.
## Assign any authored background texture to Texture; membership is region_id.
@export var region_id := "verdant"
@export var title := "VERDANT REACH"
@export var subtitle := "01  /  LIVING WORLDS"
@export var tint := Color("8ce3cd")
## 由所属星图视图下发；为空时使用默认样式。
var palette: StarMapPalette
## 主题字体解析上下文（所属星图视图）。
var font_context: Control
var target_centroid := Vector2.ZERO
var view_zoom := 1.0
func _draw() -> void:
	var style := palette if palette != null else StarMapPalette.get_default()
	var font := style.resolve_font(font_context)
	var title_color := style.region_title_color if style.override_region_title_color else Color(tint, 0.7)
	draw_set_transform(Vector2(-174, -157), 0, Vector2.ONE / maxf(view_zoom, 0.35))
	draw_string(font, Vector2.ZERO, title, HORIZONTAL_ALIGNMENT_LEFT, -1, style.region_title_font_size, title_color)
	draw_string(font, Vector2(0, 19), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, style.region_subtitle_font_size, Color(title_color, title_color.a * 0.43 / 0.7))
	draw_line(Vector2(0, 29), Vector2(54, 29), Color(title_color, title_color.a * 0.28 / 0.7), 1, true)
