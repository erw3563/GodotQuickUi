@tool
extends LevelNodeVisual
## Asset-free, intentionally simple silhouettes; all coordinates fit the unit box.
func _draw() -> void:
	if presentation.is_empty(): return
	var color: Color = presentation.tint
	var accent: Color = presentation.accent
	var dark: Color = presentation.get("dark", Color("292b25"))
	var texture: Texture2D = presentation.texture
	if texture != null:
		var dims := texture.get_size()
		var box: Vector2 = presentation.size
		if dims.x > 0 and dims.y > 0:
			var fit: Vector2 = dims * minf(box.x / dims.x, box.y / dims.y) / box
			draw_texture_rect(texture, Rect2(-fit * 0.5, fit), false, color)
		return
	match presentation.preset:
		LevelNodeStyle.Preset.BUD:
			draw_colored_polygon(PackedVector2Array([Vector2(0,.45),Vector2(-.12,.13),Vector2(-.45,-.1),Vector2(-.37,-.4),Vector2(-.05,-.29),Vector2(.1,-.47),Vector2(.42,-.25),Vector2(.35,.09)]), color)
			if presentation.decoration:
				draw_polyline(PackedVector2Array([Vector2(0,.37),Vector2(-.05,.0),Vector2(.22,-.25)]), accent,.065,true)
		LevelNodeStyle.Preset.SEAL:
			var points := PackedVector2Array()
			for i in 10:
				points.append(Vector2.from_angle(i * TAU / 10 - PI/2) * (.47 if i % 2 == 0 else .39))
			draw_colored_polygon(points,color)
			if presentation.decoration:
				draw_polyline(PackedVector2Array([Vector2(-.2,.02),Vector2(-.04,.18),Vector2(.22,-.17)]),dark,.09,true)
		LevelNodeStyle.Preset.DOORWAY:
			draw_colored_polygon(PackedVector2Array([Vector2(-.43,.45),Vector2(-.43,-.19),Vector2(-.22,-.44),Vector2(.22,-.44),Vector2(.43,-.19),Vector2(.43,.45)]),color)
			draw_colored_polygon(PackedVector2Array([Vector2(-.23,.45),Vector2(-.23,-.13),Vector2(0,-.29),Vector2(.23,-.13),Vector2(.23,.45)]),dark)
			if presentation.decoration: draw_line(Vector2(-.34,.36),Vector2(.34,.36),accent,.065,true)
		LevelNodeStyle.Preset.STONE:
			draw_colored_polygon(PackedVector2Array([Vector2(-.42,.39),Vector2(-.34,-.32),Vector2(.03,-.48),Vector2(.36,-.3),Vector2(.42,.39)]),color)
			draw_rect(Rect2(-.49,.36,.98,.11),color.darkened(.15))
			if presentation.decoration:
				draw_line(Vector2(-.15,-.14),Vector2(.15,-.14),dark,.065,true)
				draw_line(Vector2(-.12,.04),Vector2(.12,.04),dark,.065,true)
