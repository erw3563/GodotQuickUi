@tool
## MapPath 沿路径贴图网格：把贴图按「U 轴沿路径、V 轴跨路径」映射到路径网格上拉伸显示。
## 路径配置由 PathDefinition 资源持有（第 0 条路径为贴图顶部，需要至少两条有效路径）；
## 资源或路径变化时自动重建网格。
class_name MapPathMesh2D
extends Node2D

## 路径配置资源。
@export var definition: PathDefinition = null:
	set(value):
		_disconnect_curve_signals()
		definition = value
		_rebind_curve_signals()
		_request_rebuild()

## 沿路径的采样列数（每条路径的细分份数 + 1）。
@export_range(2, 512, 1) var subdivision: int = 32:
	set(value):
		subdivision = maxi(value, 2)
		_request_rebuild()

@export var texture: Texture2D = null:
	set(value):
		texture = value
		queue_redraw()

## 平铺模式：U 轴按弧长 / tile_length 重复采样贴图；关闭时整张贴图沿路径拉伸一次。
@export var uv_tile: bool = false:
	set(value):
		uv_tile = value
		_sync_texture_repeat()
		_request_rebuild()

## 平铺模式下贴图单次重复覆盖的路径长度（像素）。
@export_range(1.0, 4096.0, 0.1, "suffix:px") var tile_length: float = 64.0:
	set(value):
		tile_length = value
		_request_rebuild()

var _mesh: ArrayMesh = null
var _definition_connected := false
var _rebuild_queued := false

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_ENTER_TREE:
			_rebind_curve_signals()
			_request_rebuild()
		NOTIFICATION_EXIT_TREE:
			_disconnect_curve_signals()

func _draw() -> void:
	if texture == null or _mesh == null or _mesh.get_surface_count() == 0:
		return
	draw_mesh(_mesh, texture)

## 当前构建结果；配置不足时为空网格（无表面）。
func get_build_mesh() -> ArrayMesh:
	return _mesh

func _request_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_rebuild_queued = false
	var curve_list: Array[Curve2D] = []
	if definition != null:
		curve_list = definition.get_curves()
	var rows := MapPathMeshBuilder.sample_path_rows(curve_list, subdivision)
	_mesh = MapPathMeshBuilder.build_mesh(rows, uv_tile, tile_length)
	queue_redraw()
	update_configuration_warnings()

func _on_definition_changed() -> void:
	_rebind_curve_signals()
	_request_rebuild()

func _rebind_curve_signals() -> void:
	_disconnect_curve_signals()
	if definition == null:
		return
	definition.geometry_changed.connect(_on_definition_changed)
	_definition_connected = true

func _disconnect_curve_signals() -> void:
	if _definition_connected and definition != null \
			and definition.geometry_changed.is_connected(_on_definition_changed):
		definition.geometry_changed.disconnect(_on_definition_changed)
	_definition_connected = false

func _sync_texture_repeat() -> void:
	texture_repeat = (
		CanvasItem.TEXTURE_REPEAT_ENABLED
		if uv_tile
		else CanvasItem.TEXTURE_REPEAT_DISABLED
	)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if definition == null:
		warnings.append("需要指定 PathDefinition 路径配置资源。")
		return warnings
	var valid := 0
	for path in definition.get_curves():
		if path != null and path.point_count >= 2:
			valid += 1
	if valid < 2:
		warnings.append(
			"PathDefinition 需要至少 2 条有效 Curve2D（各含至少 2 个点）才能构成跨路径网格。"
		)
	return warnings
