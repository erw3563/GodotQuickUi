@tool
class_name StarMapRegion
extends Node2D
## All children move together with the arithmetic centroid of current members.
## Assign any authored background texture to Texture; membership is region_id.
@export var region_id := "verdant"
@export var title := "VERDANT REACH"
@export var subtitle := "01  /  LIVING WORLDS"
@export var tint := Color("8ce3cd")
var target_centroid := Vector2.ZERO
var view_zoom := 1.0
func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_set_transform(Vector2(-174, -157), 0, Vector2.ONE / maxf(view_zoom, 0.35))
	draw_string(font, Vector2.ZERO, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(tint, 0.7))
	draw_string(font, Vector2(0, 19), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(tint, 0.43))
	draw_line(Vector2(0, 29), Vector2(54, 29), Color(tint, 0.28), 1, true)
