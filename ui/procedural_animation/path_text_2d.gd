@tool
class_name PathText2D
extends Node2D
## A shaped, single-line text run sampled on one PathDefinition centerline.
## The shared source supplies geometry; typography owns font size.
## TextServer shapes typography edits; offset edits place cached clusters.

enum Alignment { START, CENTER, END }
enum TextOrientation { FOLLOW_TANGENT, UPRIGHT }
const MAX_TEXT_LENGTH := 4096
const MAX_GLYPHS := 8192
const MIN_PATH_LENGTH := 0.001

@export var definition: PathDefinition:
	set(value):
		_disconnect_definition()
		definition = value
		_bind_definition()
		_invalidate_path()
@export_range(0, 255, 1, "or_greater") var subpath_index := 0:
	set(value):
		subpath_index = maxi(value, 0)
		_invalidate_path()
@export_multiline var text := "DESIGN":
	set(value):
		if text == value: return
		text = value
		_invalidate_shape()
@export var font: Font:
	set(value):
		_disconnect_font()
		font = value
		_bind_font()
		_invalidate_shape()
@export_range(1, 512, 1) var font_size := 48:
	set(value):
		font_size = clampi(value, 1, 512)
		_invalidate_shape()
@export var color := Color.WHITE:
	set(value):
		color = value
		queue_redraw()
## Extra space between shaped clusters preserves base-and-mark grouping.
@export_range(0.0, 256.0, 0.1) var tracking := 0.0:
	set(value):
		tracking = clampf(value, 0.0, 256.0) if is_finite(value) else 0.0
		_invalidate_shape()
## Anchor of the shaped run at path_offset.
@export var alignment: Alignment = Alignment.START:
	set(value):
		alignment = value
		_invalidate_layout()
## Local arc distance from the travel start. Negative/large offsets are supported.
@export var path_offset := 0.0:
	set(value):
		path_offset = value if is_finite(value) else 0.0
		_invalidate_layout()
## Positive is the travel tangent's left normal (above a left-to-right straight line).
@export var baseline_offset := 0.0:
	set(value):
		baseline_offset = value if is_finite(value) else 0.0
		_invalidate_layout()
## Reverses travel and tangent while preserving TextServer visual order.
@export var reverse_path := false:
	set(value):
		reverse_path = value
		_invalidate_layout()
## UPRIGHT keeps glyphs horizontal.
@export var orientation: TextOrientation = TextOrientation.FOLLOW_TANGENT:
	set(value):
		orientation = value
		_invalidate_layout()
@export var text_direction: TextServer.Direction = TextServer.DIRECTION_AUTO:
	set(value):
		text_direction = value
		_invalidate_shape()
@export var language := "":
	set(value):
		language = value
		_invalidate_shape()

var _line: TextLine
var _bound_definition: PathDefinition
var _bound_font: Font
var _curve: Curve2D
var _path_length := 0.0
var _closed := false
var _text_length := 0.0
var _clusters: Array[Dictionary] = []
var _glyphs: Array[Dictionary] = []
var _shape_dirty := true
var _path_dirty := true
var _layout_dirty := true
var _refresh_queued := false
var _shape_revision := 0
var _layout_revision := 0
var _status := ""

func _enter_tree() -> void:
	_bind_definition()
	_bind_font()
	_invalidate_path()
	_invalidate_shape()

func _exit_tree() -> void:
	_disconnect_definition()
	_disconnect_font()

func _disconnect_definition() -> void:
	if _bound_definition != null and _bound_definition.geometry_changed.is_connected(_invalidate_path):
		_bound_definition.geometry_changed.disconnect(_invalidate_path)
	_bound_definition = null

func _bind_definition() -> void:
	_disconnect_definition()
	if not is_inside_tree() or definition == null: return
	_bound_definition = definition
	_bound_definition.geometry_changed.connect(_invalidate_path)

func _disconnect_font() -> void:
	if _bound_font != null and _bound_font.changed.is_connected(_invalidate_shape):
		_bound_font.changed.disconnect(_invalidate_shape)
	_bound_font = null

func _bind_font() -> void:
	_disconnect_font()
	if not is_inside_tree(): return
	_bound_font = font if font != null else ThemeDB.fallback_font
	if _bound_font != null: _bound_font.changed.connect(_invalidate_shape)

func _invalidate_shape() -> void:
	_shape_dirty = true
	_invalidate_layout()
func _invalidate_path() -> void:
	_path_dirty = true
	_invalidate_layout()
func _invalidate_layout() -> void:
	_layout_dirty = true
	if _refresh_queued: return
	_refresh_queued = true
	refresh.call_deferred()

## Sync pending edits. Deferred refresh and public queries synchronize caches.
func refresh() -> void:
	_refresh_queued = false
	if _path_dirty:
		_path_dirty = false
		_curve = null
		_path_length = 0.0
		_closed = false
		if definition != null and subpath_index < definition.shapes.size():
			var shape := definition.shapes[subpath_index]
			if shape != null and shape.curve != null and shape.curve.point_count >= 2:
				var length := shape.curve.get_baked_length()
				if is_finite(length) and length > MIN_PATH_LENGTH:
					_curve = shape.curve
					_path_length = length
					_closed = _curve.point_count >= 3 and _curve.get_point_position(0).distance_to(_curve.get_point_position(_curve.point_count - 1)) < 0.001
	if _shape_dirty:
		_shape_dirty = false
		_shape_text()
	if _layout_dirty:
		_layout_dirty = false
		_place_clusters()
		queue_redraw()

func _shape_text() -> void:
	_shape_revision += 1
	_clusters.clear()
	_glyphs.clear()
	_text_length = 0.0
	_status = ""
	_line = TextLine.new()
	if text.length() > MAX_TEXT_LENGTH:
		_status = "Text exceeds 4096 codepoints; run omitted rather than truncating a cluster."
		return
	var resolved_font := font if font != null else ThemeDB.fallback_font
	if resolved_font == null:
		_status = "No font or engine fallback font is available."
		return
	_line.direction = text_direction
	# Normalize line separators into spaces for the single shaped line.
	var single_line := text.replace("\r\n", " ").replace("\n", " ").replace("\r", " ").replace("\t", " ")
	_line.add_string(single_line, resolved_font, font_size, language)
	_line.get_line_width() # Force TextLine shaping before accessing its buffer.
	var ts := TextServerManager.get_primary_interface()
	var shaped := ts.shaped_text_get_glyphs(_line.get_rid())
	if shaped.size() > MAX_GLYPHS:
		_status = "Shaped run exceeds 8192 glyphs; run omitted."
		return
	var i := 0
	while i < shaped.size():
		var first: Dictionary = shaped[i]
		var count := maxi(1, int(first.get("count", 1)))
		var finish := mini(i + count, shaped.size())
		var cluster_index := _clusters.size()
		var pen := 0.0
		var indices: Array[int] = []
		for j in range(i, finish):
			var source: Dictionary = shaped[j]
			for _repeat_index in maxi(0, int(source.get("repeat", 1))):
				if _glyphs.size() >= MAX_GLYPHS:
					_clusters.clear()
					_glyphs.clear()
					_text_length = 0.0
					_status = "Repeated shaped run exceeds 8192 glyphs; run omitted."
					return
				var glyph := source.duplicate(true)
				glyph["cluster_index"] = cluster_index
				glyph["pen"] = pen
				indices.append(_glyphs.size())
				_glyphs.append(glyph)
				pen += float(source.get("advance", 0.0))
		var cluster := {"start": _text_length, "advance": pen, "glyphs": indices, "transform": Transform2D.IDENTITY, "visible": false}
		_clusters.append(cluster)
		for glyph_index in indices: _glyphs[glyph_index]["cluster_advance"] = pen
		_text_length += pen
		i = finish
		if i < shaped.size(): _text_length += tracking

func _place_clusters() -> void:
	_layout_revision += 1
	var anchor_shift := 0.0
	if alignment == Alignment.CENTER: anchor_shift = -_text_length * 0.5
	elif alignment == Alignment.END: anchor_shift = -_text_length
	for cluster in _clusters:
		var advance: float = cluster["advance"]
		var start: float = path_offset + anchor_shift + float(cluster["start"])
		var distance := start + advance * 0.5
		var visible_cluster := _curve != null
		var sampled_distance := 0.0
		var frame := Transform2D.IDENTITY
		var angle := 0.0
		if _curve != null:
			if not _closed:
				visible_cluster = start >= -0.0001 and start + advance <= _path_length + 0.0001
			var travel_distance := fposmod(distance, _path_length) if _closed else clampf(distance, 0.0, _path_length)
			sampled_distance = _path_length - travel_distance if reverse_path else travel_distance
			frame = _curve.sample_baked_with_rotation(sampled_distance, false)
			var tangent := frame.x.normalized()
			if reverse_path: tangent = -tangent
			angle = tangent.angle() if orientation == TextOrientation.FOLLOW_TANGENT else 0.0
			frame = Transform2D(angle, frame.origin + tangent.orthogonal() * baseline_offset)
		cluster["transform"] = frame
		cluster["visible"] = visible_cluster
		for glyph_index in cluster["glyphs"]:
			var glyph := _glyphs[glyph_index]
			var local := Vector2(float(glyph["pen"]) - advance * 0.5, 0.0) + Vector2(glyph["offset"])
			glyph["distance"] = distance
			glyph["sampled_distance"] = sampled_distance
			glyph["position"] = frame * local
			glyph["rotation"] = angle
			glyph["visible"] = visible_cluster

func _draw() -> void:
	refresh()
	var ts := TextServerManager.get_primary_interface()
	for cluster in _clusters:
		if not cluster["visible"]: continue
		var frame: Transform2D = cluster["transform"]
		# Font rasterization snaps/subpixel-selects in draw-local coordinates before
		# the CanvasItem transform. Rebase translation to an integer in glyph axes
		# to preserve integral baselines at half-advance cluster centers.
		var integral_origin := frame.basis_xform_inv(frame.origin).round()
		var draw_frame := frame
		draw_frame.origin = frame.basis_xform(integral_origin)
		var remainder := frame.basis_xform_inv(frame.origin - draw_frame.origin)
		draw_set_transform_matrix(draw_frame)
		for glyph_index in cluster["glyphs"]:
			var glyph := _glyphs[glyph_index]
			var at := Vector2(float(glyph["pen"]) - float(cluster["advance"]) * 0.5, 0.0) + Vector2(glyph["offset"]) + remainder
			# Snap near-integral baselines within the floating-point epsilon.
			# Preserve intentional fractional positions outside this epsilon.
			if absf(at.x - roundf(at.x)) < 0.0001: at.x = roundf(at.x)
			if absf(at.y - roundf(at.y)) < 0.0001: at.y = roundf(at.y)
			var rid: RID = glyph["font_rid"]
			if rid.is_valid():
				ts.font_draw_glyph(rid, get_canvas_item(), int(glyph["font_size"]), at, int(glyph["index"]), color)
			else:
				ts.draw_hex_code_box(get_canvas_item(), int(glyph["font_size"]), at, int(glyph["index"]), color)
	draw_set_transform_matrix(Transform2D.IDENTITY)

func get_path_length() -> float:
	refresh()
	return _path_length
func get_text_length() -> float:
	refresh()
	return _text_length
func get_cluster_count() -> int:
	refresh()
	return _clusters.size()
func get_glyph_snapshot() -> Array[Dictionary]:
	refresh()
	return _glyphs.duplicate(true)
func get_shape_revision() -> int:
	refresh()
	return _shape_revision
func get_layout_revision() -> int:
	refresh()
	return _layout_revision
func get_status() -> String:
	refresh()
	return _status
