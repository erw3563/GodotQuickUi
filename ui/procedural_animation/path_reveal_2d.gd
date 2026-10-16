@tool
class_name PathReveal2D
extends Node2D
## 形状和笔画宽度驱动完整带状网格重建，UV.x 表达归一化累计弧长。
## reveal_progress 更新节点私有的 ShaderMaterial，纹理条纹使用独立时钟。
const REVEAL_SHADER = preload("res://addons/gdbase/ui/procedural_animation/path_reveal.gdshader")

@export var definition: PathDefinition:
	set(value):
		_disconnect_sources()
		definition = value
		_bind_sources()
		_request_rebuild()
@export_range(2, 512, 1) var subdivision: int = 160:
	set(value):
		subdivision = clampi(value, 2, 512)
		_request_rebuild()
@export_range(0.0, 1.0, 0.001) var reveal_progress: float = 1.0:
	set(value):
		reveal_progress = clampf(value, 0.0, 1.0)
		_sync_shader()
@export var color: Color = Color(0.05, 0.85, 1.0):
	set(value):
		color = value
		_sync_shader()
@export_range(0.0, 0.05, 0.001) var feather: float = 0.002:
	set(value):
		feather = maxf(value, 0.0)
		_sync_shader()
## 装饰条纹速度独立控制材质内部的纹理运动。
@export var pattern_speed: float = 0.0:
	set(value):
		pattern_speed = value
		_sync_shader()
@export_range(0.0, 1.0, 0.01) var pattern_strength: float = 0.12:
	set(value):
		pattern_strength = value
		_sync_shader()

var _mesh: ArrayMesh
var _shader_material: ShaderMaterial
var _connected_definition: PathDefinition
var _curves: Array[Curve2D] = []
var _rebuild_queued := false
var build_revision := 0

func _enter_tree() -> void:
	_bind_sources()
	_sync_shader()
	_request_rebuild()

func _exit_tree() -> void:
	_disconnect_sources()

func _draw() -> void:
	if _mesh != null and _mesh.get_surface_count() > 0:
		draw_mesh(_mesh, null)

func get_build_mesh() -> ArrayMesh:
	return _mesh

func _sync_shader() -> void:
	if _shader_material == null:
		_shader_material = ShaderMaterial.new()
		_shader_material.shader = REVEAL_SHADER
		material = _shader_material
	_shader_material.set_shader_parameter("reveal_progress", reveal_progress)
	_shader_material.set_shader_parameter("tint", color)
	_shader_material.set_shader_parameter("feather", feather)
	_shader_material.set_shader_parameter("pattern_speed", pattern_speed)
	_shader_material.set_shader_parameter("pattern_strength", pattern_strength)

func _disconnect_sources() -> void:
	if _connected_definition != null and _connected_definition.changed.is_connected(_on_definition_changed):
		_connected_definition.changed.disconnect(_on_definition_changed)
	_connected_definition = null
	for curve in _curves:
		if curve.changed.is_connected(_request_rebuild):
			curve.changed.disconnect(_request_rebuild)
	_curves.clear()

func _bind_sources() -> void:
	_disconnect_sources()
	if definition == null:
		return
	_connected_definition = definition
	definition.changed.connect(_on_definition_changed)

func _on_definition_changed() -> void:
	_bind_sources()
	_request_rebuild()

func _request_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_rebuild_queued = false
	_mesh = ArrayMesh.new()
	build_revision += 1
	if definition != null:
		for index in definition.shapes.size():
			var curve := definition.shapes[index].curve if definition.shapes[index] != null else null
			if curve != null and curve.point_count >= 2 and curve.get_baked_length() > 0.001:
				_build_ribbon(curve, index)
	queue_redraw()

func _build_ribbon(curve: Curve2D, index: int) -> void:
	var points := PackedVector2Array()
	var distances := PackedFloat32Array([0.0])
	for i in subdivision + 1:
		points.append(curve.sample_baked(curve.get_baked_length() * float(i) / subdivision))
		if i > 0:
			distances.append(distances[-1] + points[i].distance_to(points[i - 1]))
	var total := distances[-1]
	if total <= 0.001:
		return
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in points.size():
		var tangent := points[mini(i + 1, points.size() - 1)] - points[maxi(0, i - 1)]
		if tangent.length_squared() < 0.000001:
			tangent = Vector2.RIGHT
		var normal := tangent.normalized().orthogonal()
		var s := distances[i] / total
		var shape_width := definition.sample_width(index, s)
		for side in 2:
			vertices.append(points[i] + normal * (float(side) - 0.5) * shape_width)
			uvs.append(Vector2(s, float(side)))
		if i < points.size() - 1:
			var j := i * 2
			indices.append_array(PackedInt32Array([j, j + 2, j + 1, j + 1, j + 2, j + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
