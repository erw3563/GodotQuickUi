class_name IsoPlane
extends Control
## Live Control scenes rendered onto real 3D quads. Fixed perspective camera.
## This component displays UI; it intentionally does not forward pointer input.
signal finished
signal progress_changed(value: float)

@export var content_scene: PackedScene
@export var content_size := Vector2i(1200, 675)
@export var start_angles := Vector3(-48.0, -16.0, -12.0)
@export_range(0.1, 20.0, 0.1) var duration := 0.60
@export_range(0.0, 3.0, 0.05) var lead_in := 0.55
@export_enum("Reference snap", "Smooth", "Cubic out", "Linear") var easing := 0
@export_range(0.0, 1.5, 0.05) var layer_separation := 0.65
@export var autoplay := true

var progress := 0.0
var playing := false
var elapsed := 0.0
var world_view: SubViewport
var camera: Camera3D
var pivot: Node3D
var surface: TextureRect
var layers: Array[MeshInstance3D] = []
var content_views: Array[SubViewport] = []
var _start_q: Quaternion

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_view = SubViewport.new()
	world_view.own_world_3d = true
	world_view.transparent_bg = true
	world_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_view.msaa_3d = Viewport.MSAA_4X
	add_child(world_view)
	pivot = Node3D.new()
	world_view.add_child(pivot)
	camera = Camera3D.new()
	camera.position.z = 10.7
	camera.fov = 40.0
	camera.near = 0.1
	world_view.add_child(camera)
	camera.current = true
	surface = TextureRect.new()
	surface.texture = world_view.get_texture()
	surface.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	surface.stretch_mode = TextureRect.STRETCH_SCALE
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(surface)
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_resize)
	_resize()
	if content_scene:
		set_content(content_scene.instantiate())
	_set_progress(0.0)
	if autoplay:
		replay()

func _resize() -> void:
	content_size = Vector2i(maxi(content_size.x, 2), maxi(content_size.y, 2))
	if not is_instance_valid(world_view):
		return
	world_view.size = Vector2i(maxi(int(size.x), 2), maxi(int(size.y), 2))
	# Vertical FOV is fixed. Pull back on narrow windows rather than stretching UI.
	var screen_aspect := maxf(size.x / maxf(size.y, 1.0), 0.1)
	var quad_width := 8.9
	var quad_height := quad_width * float(content_size.y) / maxf(content_size.x, 1)
	var visible_height := maxf(quad_height, quad_width / screen_aspect)
	camera.position.z = visible_height / (2.0 * tan(deg_to_rad(camera.fov * 0.5))) * 1.55

func set_content(content: Control) -> void:
	clear_content()
	add_layer(content, 0.0)

func clear_content() -> void:
	for layer in layers:
		layer.queue_free()
	for view in content_views:
		view.queue_free()
	layers.clear()
	content_views.clear()

func add_layer(content: Control, depth: float = 0.0) -> void:
	content_size = Vector2i(maxi(content_size.x, 2), maxi(content_size.y, 2))
	assert(is_instance_valid(world_view), "Call after the component enters the scene tree.")
	var view := SubViewport.new()
	view.size = content_size
	view.transparent_bg = true
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	view.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var quad := QuadMesh.new()
	quad.size = Vector2(8.9, 8.9 * float(content_size.y) / content_size.x)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.albedo_texture = view.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.no_depth_test = false
	material.render_priority = layers.size()
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	mesh.material_override = material
	mesh.set_meta("depth", depth)
	pivot.add_child(mesh)
	layers.append(mesh)
	content_views.append(view)
	_resize()
	_apply_pose()

func replay() -> void:
	elapsed = -lead_in
	playing = true
	_set_progress(0.0)

func stop() -> void:
	playing = false

func seek(value: float) -> void:
	playing = false
	elapsed = clampf(value, 0.0, 1.0) * duration
	_set_progress(value)

func _set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	_apply_pose()
	progress_changed.emit(progress)

func _process(delta: float) -> void:
	if playing and progress >= 1.0:
		playing = false
		return
	if playing:
		elapsed += delta
		_set_progress(elapsed / maxf(duration, 0.01))
		if progress >= 1.0:
			playing = false
			finished.emit()

func _apply_pose() -> void:
	if not is_instance_valid(pivot):
		return
	var t := progress
	match easing:
		0:
			# Fast attack, small overshoot, then a short settle. No long slow tail.
			var u := t - 1.0
			t = 1.0 + 1.5 * u * u * u + 0.5 * u * u
		1: t = t * t * (3.0 - 2.0 * t)
		2: t = 1.0 - pow(1.0 - t, 3.0)
	_start_q = Quaternion.from_euler(start_angles * PI / 180.0)
	pivot.quaternion = _start_q.slerp(Quaternion.IDENTITY, t)
	for i in layers.size():
		# Tiny final offsets avoid coplanar z-fighting; visually one flat UI.
		# Layer docking finishes before the camera-facing rotation settles.
		# With 0.60 s duration: 0.04–0.36 s, staggered by at most 0.07 s.
		var stagger := 0.115 * float(i) / maxf(layers.size() - 1, 1)
		var dock := clampf((progress - 0.065 - stagger) / 0.535, 0.0, 1.0)
		dock = dock * dock * (3.0 - 2.0 * dock)
		layers[i].position.z = float(layers[i].get_meta("depth")) * layer_separation * (1.0 - dock) + i * 0.002
