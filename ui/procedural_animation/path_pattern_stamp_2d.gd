@tool
## 路径横向条带图案静态贴图：沿 PathDefinition 各条曲线，在法线方向 ±half_width 的走廊内按固定种子播撒 Texture2D，
## 每个烘焙点生成一张 Sprite2D（按权重抽图案，并随机缩放与朝向）。
## 几何由 PathPatternScatterBuilder 计算；本节点持有参数、监听路径变更并管理生成的 Sprite2D 子节点。
## 契约：名下直接子节点均为生成产物，参数变化即移除重建——不要把业务节点挂在本节点下。
## 生成子节点不设置 owner，不会序列化进 .tscn；加载/实例化时按进入树重新生成。
class_name PathPatternStamp2D
extends Node2D

## 随机种子下限：6 位种子的最小取值。
const SEED_MIN := 100000
## 随机种子上限：6 位种子的最大取值。
const SEED_MAX := 999999

@export_group("散布")
## 路径配置资源；每条有效曲线各自在走廊内独立播撒。
@export var definition: PathDefinition = null:
	set(value):
		_disconnect_curve_signals()
		definition = value
		_rebind_curve_signals()
		_request_rebuild()

## 横向半宽：沿路径法线方向的走廊半宽（像素）。
@export_range(0.0, 4096.0, 1.0, "or_greater", "suffix:px") var half_width: float = 32.0:
	set(value):
		half_width = maxf(value, 0.0)
		_request_rebuild()

## 沿路径弧长采样列数。
@export_range(1, 512, 1) var columns: int = 24:
	set(value):
		columns = maxi(value, 1)
		_request_rebuild()

## 每个弧长基点在横向条带内再采的点数。
@export_range(1, 64, 1) var samples_per_column: int = 1:
	set(value):
		samples_per_column = maxi(value, 1)
		_request_rebuild()

## 预设图案贴图列表；空项跳过。
@export var patterns: Array[Texture2D] = []:
	set(value):
		patterns = value
		_request_rebuild()

## 与 patterns 对齐的权重；缺省或非正则按 1；每个烘焙点按权重独立抽图案。
@export var pattern_weights: Array[float] = []:
	set(value):
		pattern_weights = value
		_request_rebuild()

## 固定随机种子：同种子同参数生成结果完全一致（命名避开全局函数 seed()）。
@export_range(100000, 999999, 1) var random_seed: int = SEED_MIN:
	set(value):
		random_seed = clampi(value, SEED_MIN, SEED_MAX)
		_request_rebuild()

## 随机生成 6 位种子。
@export_tool_button("随机种子") var randomize_seed_button: Callable = randomize_seed

@export_group("外观")
## 贴图缩放下限。
@export_range(0.01, 64.0, 0.01, "or_greater") var scale_min: float = 1.0:
	set(value):
		scale_min = maxf(value, 0.01)
		_request_rebuild()

## 贴图缩放上限。
@export_range(0.01, 64.0, 0.01, "or_greater") var scale_max: float = 1.0:
	set(value):
		scale_max = maxf(value, 0.01)
		_request_rebuild()

## 贴图朝向下限（度）。
@export_range(-720.0, 720.0, 0.1, "or_less", "or_greater", "suffix:°") var angle_degrees_min: float = 0.0:
	set(value):
		angle_degrees_min = value
		_request_rebuild()

## 贴图朝向上限（度）。
@export_range(-720.0, 720.0, 0.1, "or_less", "or_greater", "suffix:°") var angle_degrees_max: float = 0.0:
	set(value):
		angle_degrees_max = value
		_request_rebuild()

var _sprite_nodes: Array[Sprite2D] = []
var _definition_connected := false
var _rebuild_queued := false
var _stamp_count: int = 0

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_ENTER_TREE:
			_rebind_curve_signals()
			_request_rebuild()
		NOTIFICATION_EXIT_TREE:
			_disconnect_curve_signals()

## 当前生成的 Sprite2D 快照副本。
func get_sprites() -> Array[Sprite2D]:
	return _sprite_nodes.duplicate()

## 最近一次生成的贴图数量。
func get_stamp_count() -> int:
	return _stamp_count

## 随机生成 6 位种子并重建；Inspector 按钮与运行时共用。
func randomize_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	random_seed = rng.randi_range(SEED_MIN, SEED_MAX)

func _request_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_rebuild_queued = false
	_clear_sprite_nodes()
	_stamp_count = 0

	var curve_list: Array[Curve2D] = []
	if definition != null:
		curve_list = definition.get_curves()
	var baked := PathPatternScatterBuilder.bake_emission(
		curve_list,
		columns,
		samples_per_column,
		half_width,
		random_seed
	)
	var positions: PackedVector2Array = baked["positions"]
	var valid_patterns := _collect_valid_patterns()
	if positions.is_empty() or valid_patterns.is_empty():
		update_configuration_warnings()
		return

	var instances := PathPatternScatterBuilder.bake_stamp_instances(
		positions.size(),
		_collect_weights(valid_patterns.size()),
		scale_min,
		scale_max,
		angle_degrees_min,
		angle_degrees_max,
		random_seed
	)
	var pattern_indices: PackedInt32Array = instances["pattern_indices"]
	var scales: PackedFloat32Array = instances["scales"]
	var angles_radians: PackedFloat32Array = instances["angles_radians"]

	for point_index in positions.size():
		var pattern_index := pattern_indices[point_index]
		if pattern_index < 0 or pattern_index >= valid_patterns.size():
			continue
		var sprite := _create_stamp_sprite(
			valid_patterns[pattern_index],
			positions[point_index],
			scales[point_index],
			angles_radians[point_index]
		)
		add_child(sprite)
		_sprite_nodes.append(sprite)
	_stamp_count = _sprite_nodes.size()
	update_configuration_warnings()

func _collect_valid_patterns() -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	for pattern in patterns:
		if pattern != null:
			result.append(pattern)
	return result

func _collect_weights(pattern_count: int) -> Array[float]:
	var weights: Array[float] = []
	var valid_index := 0
	for pattern_index in patterns.size():
		if patterns[pattern_index] == null:
			continue
		var weight := 1.0
		if pattern_index < pattern_weights.size() and pattern_weights[pattern_index] > 0.0:
			weight = pattern_weights[pattern_index]
		weights.append(weight)
		valid_index += 1
		if valid_index >= pattern_count:
			break
	while weights.size() < pattern_count:
		weights.append(1.0)
	return weights

func _create_stamp_sprite(
	texture: Texture2D,
	stamp_position: Vector2,
	stamp_scale: float,
	stamp_rotation: float
) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = stamp_position
	sprite.rotation = stamp_rotation
	sprite.scale = Vector2(stamp_scale, stamp_scale)
	return sprite

func _clear_sprite_nodes() -> void:
	for sprite in _sprite_nodes:
		if sprite == null:
			continue
		remove_child(sprite)
		sprite.queue_free()
	_sprite_nodes.clear()

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

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if definition == null:
		warnings.append("需要指定 PathDefinition 路径配置资源。")
		return warnings
	var valid_curves := 0
	for path in definition.get_curves():
		if path != null and path.point_count >= 2:
			valid_curves += 1
	if valid_curves < 1:
		warnings.append("PathDefinition 需要至少 1 条有效 Curve2D（各含至少 2 个点）。")
	var has_pattern := false
	for pattern in patterns:
		if pattern != null:
			has_pattern = true
			break
	if not has_pattern:
		warnings.append("需要至少一张有效的图案 Texture2D。")
	var weight_sum := 0.0
	var valid_pattern_count := 0
	for pattern_index in patterns.size():
		if patterns[pattern_index] == null:
			continue
		valid_pattern_count += 1
		if pattern_index < pattern_weights.size():
			weight_sum += maxf(pattern_weights[pattern_index], 0.0)
		else:
			weight_sum += 1.0
	if valid_pattern_count > 0 and pattern_weights.size() > 0 and weight_sum <= 0.0:
		warnings.append("图案权重之和需要大于 0。")
	return warnings
