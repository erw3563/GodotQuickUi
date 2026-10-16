@tool
class_name BlockReveal
extends Control
## Deterministic rectangular background reveal with separately authored content.
## Drive progress with QuickTweenFloat; the node draws cached block geometry.

enum Direction { RIGHT_TO_LEFT, LEFT_TO_RIGHT, TOP_TO_BOTTOM, BOTTOM_TO_TOP }

@export_range(0.0, 1.0, 0.001) var progress: float = 1.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()
@export var block_size := Vector2(32.0, 32.0):
	set(value):
		block_size = Vector2(maxf(value.x, 4.0), maxf(value.y, 4.0))
		_rebuild()
@export var direction: Direction = Direction.RIGHT_TO_LEFT:
	set(value):
		direction = value
		_rebuild()
## Random timing contribution, stable across frames and replays.
@export_range(0.0, 1.0, 0.01) var stagger: float = 0.35:
	set(value):
		stagger = clampf(value, 0.0, 1.0)
		_rebuild()
@export var random_seed: int = 42017:
	set(value):
		random_seed = value
		_rebuild()
## Maximum number of horizontally merged cells per rectangle.
@export_range(1, 8, 1) var max_block_span: int = 3:
	set(value):
		max_block_span = clampi(value, 1, 8)
		_rebuild()
## Permanent stepped silhouette on the left; 0 gives a full rectangle.
@export_range(0, 8, 1) var edge_steps: int = 2:
	set(value):
		edge_steps = clampi(value, 0, 8)
		_rebuild()
## Local opacity ramp; 0 gives crisp binary blocks.
@export_range(0.0, 0.3, 0.001) var softness: float = 0.045:
	set(value):
		softness = clampf(value, 0.0, 0.3)
		queue_redraw()
@export var fill_color := Color(0.96, 0.95, 0.97):
	set(value):
		fill_color = value
		queue_redraw()
@export var accent_color := Color(1.0, 0.26, 0.57):
	set(value):
		accent_color = value
		queue_redraw()
@export var secondary_accent_color := Color(0.45, 0.47, 0.52):
	set(value):
		secondary_accent_color = value
		queue_redraw()
@export var accents_enabled: bool = true:
	set(value):
		accents_enabled = value
		queue_redraw()
@export_range(0.01, 0.3, 0.01) var accent_window: float = 0.12:
	set(value):
		accent_window = clampf(value, 0.01, 0.3)
		queue_redraw()

var _blocks: Array[Dictionary] = []

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_rebuild)

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	_blocks.clear()
	if size.x <= 0.0 or size.y <= 0.0:
		queue_redraw()
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	# Bound work even if callers author very large controls.
	var cell := Vector2(maxf(block_size.x, size.x / 128.0), maxf(block_size.y, size.y / 128.0))
	var columns := int(ceil(size.x / cell.x))
	var rows := int(ceil(size.y / cell.y))
	for row in rows:
		var inset := rng.randi_range(0, mini(edge_steps, maxi(columns - 1, 0)))
		var column := inset
		while column < columns:
			var span := mini(rng.randi_range(1, max_block_span), columns - column)
			var origin := Vector2(column * cell.x, row * cell.y)
			var extent := Vector2(minf(span * cell.x, size.x - origin.x), minf(cell.y, size.y - origin.y))
			var center := (origin + extent * 0.5) / size
			var travel := 1.0 - center.x
			match direction:
				Direction.LEFT_TO_RIGHT: travel = center.x
				Direction.TOP_TO_BOTTOM: travel = center.y
				Direction.BOTTOM_TO_TOP: travel = 1.0 - center.y
			var threshold := 0.06 + 0.82 * lerpf(travel, rng.randf(), stagger)
			_blocks.append({"rect": Rect2(origin, extent), "threshold": threshold,
				"accent": rng.randf() < 0.38, "secondary": rng.randf() < 0.3,
				"line": rng.randf() < 0.45})
			column += span
	queue_redraw()

## Read-only geometry snapshot for tooling/tests; returned data is independent.
func get_blocks() -> Array[Dictionary]:
	return _blocks.duplicate(true)

func block_coverage(threshold: float) -> float:
	if progress <= 0.0: return 0.0
	if progress >= 1.0: return 1.0
	if softness <= 0.0: return 1.0 if progress >= threshold else 0.0
	return clampf((progress - threshold) / softness, 0.0, 1.0)

func _draw() -> void:
	if progress <= 0.0: return
	# Accent fragments use deterministic progress before their stable block.
	if accents_enabled and progress < 1.0:
		for block in _blocks:
			if not block.accent: continue
			var distance: float = absf(progress - float(block.threshold))
			var intensity := maxf(0.0, 1.0 - distance / accent_window)
			if intensity <= 0.0: continue
			var fragment: Rect2 = block.rect
			fragment.position.x -= block_size.x * 0.35
			if block.line:
				fragment.size.y = 3.0
				fragment.position.y += block_size.y * 0.6
			var color := secondary_accent_color if block.secondary else accent_color
			color.a *= intensity
			draw_rect(fragment, color)
	for block in _blocks:
		var coverage := block_coverage(block.threshold)
		if coverage <= 0.0: continue
		var color := fill_color
		color.a *= coverage
		draw_rect(block.rect, color)
