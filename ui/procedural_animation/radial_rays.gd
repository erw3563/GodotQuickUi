@tool
## 放射条带生成器：按参数在名下生成一圈 Polygon2D 条带，用于从中心向外发散的背景装饰。
## 几何计算全部在 RadialRaysBuilder（纯静态）；本节点持有参数、调度重建并管理生成子节点。
## 每根条带以中心角为轴：内端（起点）是长度 base_width 的横切线，两侧边按 ray_slope 展开，
## 起点为一条线段；ray_slope 为 0 时整根等宽，取正值向外张开、取负值向内收窄。
## 控件形态：放射中心为矩形中心（size/2；无布局时 size 为 0，中心即节点原点），
## 尺寸变化自动跟随；可按普通 Control 锚点布局（如满屏铺开时从屏幕中心放射）。
## 契约：名下直接子节点均为生成产物，参数变化即全部移除重建——不要把业务节点挂在本节点下，
## 也不要手工修改生成的 Polygon2D（会被下一次重建覆盖）。
## 生成的子节点不设置 owner：不会序列化进 .tscn，加载/实例化时按进入树重新生成；
## 固定种子保证编辑器所见与运行时一致。整盘动画（旋转/缩放/淡入）直接驱动本节点 transform 即可。
class_name RadialRays
extends Control

## 随机种子下限：6 位种子的最小取值。
const SEED_MIN := 100000
## 随机种子上限：6 位种子的最大取值。
const SEED_MAX := 999999

@export_group("基础几何")
## 条带数量；小于 1 时按 1 处理。
@export var ray_count: int = 16:
	set(value):
		ray_count = maxi(value, 1)
		_request_rebuild()

## 内半径：条带起点所在的基础半径；0 时起点横线落在原点。
@export_range(0.0, 4096.0, 1.0, "or_greater", "suffix:px") var inner_radius: float = 120.0:
	set(value):
		inner_radius = maxf(value, 0.0)
		_request_rebuild()

## 外半径：条带终点所在的基础半径。
@export_range(0.0, 8192.0, 1.0, "or_greater", "suffix:px") var outer_radius: float = 900.0:
	set(value):
		outer_radius = maxf(value, 0.0)
		_request_rebuild()

## 基础宽度：条带内端横切线的长度，起点为一条该长度的线段；0 时起点收成一个点。
@export_range(0.0, 2048.0, 1.0, "or_greater", "suffix:px") var base_width: float = 24.0:
	set(value):
		base_width = maxf(value, 0.0)
		_request_rebuild()

## 斜率：两侧边每单位轴向距离的横向展开量（无量纲）；0 时两侧边平行，整根条带等宽。
## 正值向外张开、负值向内收窄（内端最宽）；外端横切线的长度 = 基础宽度 + 2 × 轴向长度 × 斜率，下限为 0。
@export_range(-10.0, 10.0, 0.01, "or_less", "or_greater") var ray_slope: float = 0.12:
	set(value):
		ray_slope = value
		_request_rebuild()

## 全体中心角偏移（弧度）：每根条带的基准角同加本值，用于整盘方位调整，不改节点 rotation。
## 已有条带时原地刷新顶点；无条带时走完整重建。
@export_range(-TAU, TAU, 0.001, "or_less", "or_greater", "suffix:rad") var angle_offset: float = 0.0:
	set(value):
		angle_offset = value
		if not is_inside_tree():
			return
		_ensure_ray_storage()
		if _ray_nodes.is_empty():
			_request_rebuild()
		else:
			refresh_ray_polygons()

@export_group("随机")
## 内半径逐根随机幅度：每根条带起点在内半径上各自 ± 随机；0 时全体落在内半径。
@export_range(0.0, 2048.0, 1.0, "or_greater", "suffix:px") var inner_radius_randomness: float = 0:
	set(value):
		inner_radius_randomness = maxf(value, 0.0)
		_request_rebuild()

## 斜率随机幅度：每根条带斜率在 1±幅度 系数内随机，基础宽度不随之变化。
@export_range(0.0, 1.0, 0.01) var slope_randomness: float = 0:
	set(value):
		slope_randomness = clampf(value, 0.0, 1.0)
		_request_rebuild()

## 长度随机幅度：每根条带外半径在基础值 ± 幅度内随机（下限保护到该根起点，不内翻）。
@export_range(0.0, 4096.0, 1.0, "or_greater", "suffix:px") var length_randomness: float = 0:
	set(value):
		length_randomness = maxf(value, 0.0)
		_request_rebuild()

## 角度随机幅度（弧度）：每根条带中心角在基准 ± 幅度内抖动。
@export_range(0.0, TAU, 0.001, "or_greater", "suffix:rad") var angle_randomness: float = 0:
	set(value):
		angle_randomness = maxf(value, 0.0)
		_request_rebuild()

## 固定随机种子：同种子同参数生成结果完全一致，便于美术调参（命名避开全局函数 seed()）。
## 种子为 6 位整数，输入超出 100000–999999 时按上下限取值。
@export_range(100000, 999999, 1) var random_seed: int = SEED_MIN:
	set(value):
		random_seed = clampi(value, SEED_MIN, SEED_MAX)
		_request_rebuild()

## 随机生成 6 位种子。
@export_tool_button("随机种子") var randomize_seed_button: Callable = randomize_seed

@export_group("角度偏移")
## 角度偏移区域起始角（弧度）；与跨度共同划定半开环段。
@export_range(-TAU, TAU, 0.001, "or_less", "or_greater", "suffix:rad") var region_start_angle: float = 0.0:
	set(value):
		region_start_angle = value
		_request_rebuild()

## 角度偏移区域跨度（弧度）；0 时整组区域偏移不生效，上限为一整圈。
@export_range(0.0, TAU, 0.001, "suffix:rad") var region_span: float = 0.0:
	set(value):
		region_span = clampf(value, 0.0, TAU)
		_request_rebuild()

## 区域内条带的内半径固定偏移（像素，可负）；与逐根内半径随机相加。
@export var region_inner_radius_offset: float = 0.0:
	set(value):
		region_inner_radius_offset = value
		_request_rebuild()

## 区域内条带的斜率系数固定偏移：有效系数 = 1±随机 + 本偏移，再下限钳 0 后乘基础斜率。
@export var region_slope_scale_offset: float = 0.0:
	set(value):
		region_slope_scale_offset = value
		_request_rebuild()

## 区域内条带的外半径固定偏移（像素，可负）；与逐根长度随机相加。
@export var region_length_offset: float = 0.0:
	set(value):
		region_length_offset = value
		_request_rebuild()

## 区域内条带的中心角固定偏移（弧度，可负）；与逐根角度随机相加。
@export_range(-TAU, TAU, 0.001, "or_less", "or_greater", "suffix:rad") var region_angle_offset: float = 0.0:
	set(value):
		region_angle_offset = value
		_request_rebuild()

@export_group("外观")
## 条带颜色（含透明度）。
@export var color: Color = Color(0.1, 0.45, 1.0, 0.5):
	set(value):
		color = value
		_ensure_ray_storage()
		for ray in _ray_nodes:
			ray.color = color

var _ray_nodes: Array[Polygon2D] = []
var _rebuild_queued := false

## 装饰控件默认不拦截鼠标，避免盖住下层 UI 的点击。
func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_ensure_ray_storage()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_ENTER_TREE:
			_ensure_ray_storage()
			_request_rebuild()
		NOTIFICATION_RESIZED:
			_update_ray_positions()

## 尺寸变化时把条带移到新矩形中心（只移动不重建）。
func _update_ray_positions() -> void:
	_ensure_ray_storage()
	var center := size * 0.5
	for ray in _ray_nodes:
		ray.position = center

## 当前生成的全部条带节点（快照副本）。
func get_rays() -> Array[Polygon2D]:
	_ensure_ray_storage()
	return _ray_nodes.duplicate()

## 第 index 根条带的四边形顶点；越界返回空数组。
func get_ray_polygon(index: int) -> PackedVector2Array:
	_ensure_ray_storage()
	if index < 0 or index >= _ray_nodes.size():
		return PackedVector2Array()
	return _ray_nodes[index].polygon

## 随机生成 6 位种子并重建条带；Inspector 按钮与运行时调用共用本入口。
func randomize_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	random_seed = rng.randi_range(SEED_MIN, SEED_MAX)

## 修复脚本热重载后子类实例上数组/标志槽位错乱，保证条带存储可用。
func _ensure_ray_storage() -> void:
	if typeof(_ray_nodes) != TYPE_ARRAY:
		_ray_nodes = [] as Array[Polygon2D]
	if typeof(_rebuild_queued) != TYPE_BOOL:
		_rebuild_queued = false

## 按当前参数重算各条带顶点；数量变化或尚无条带时走完整重建。
func refresh_ray_polygons() -> void:
	_ensure_ray_storage()
	var polygons := _build_polygons()
	if polygons.is_empty():
		_rebuild()
		return
	if polygons.size() != _ray_nodes.size():
		_rebuild()
		return
	var center := size * 0.5
	for index in polygons.size():
		_ray_nodes[index].polygon = polygons[index]
		_ray_nodes[index].color = color
		_ray_nodes[index].position = center

func _request_rebuild() -> void:
	_ensure_ray_storage()
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_ensure_ray_storage()
	_rebuild_queued = false
	for ray in _ray_nodes:
		remove_child(ray)
		ray.queue_free()
	_ray_nodes.clear()

	for polygon in _build_polygons():
		var ray := Polygon2D.new()
		ray.polygon = polygon
		ray.color = color
		ray.position = size * 0.5
		add_child(ray)
		_ray_nodes.append(ray)
	update_configuration_warnings()

## 调用构建器生成当前参数下的全部条带多边形。
func _build_polygons() -> Array[PackedVector2Array]:
	return RadialRaysBuilder.build_ray_polygons(capture_build_parameters())

## 把当前导出参数装配为一次构建的输入值快照；节点重建与外部按同口径取当前几何。
func capture_build_parameters() -> RadialRaysParameters:
	var parameters := RadialRaysParameters.new()
	parameters.ray_count = ray_count
	parameters.inner_radius = inner_radius
	parameters.outer_radius = outer_radius
	parameters.base_width = base_width
	parameters.ray_slope = ray_slope
	parameters.angle_offset = angle_offset
	parameters.inner_radius_randomness = inner_radius_randomness
	parameters.slope_randomness = slope_randomness
	parameters.length_randomness = length_randomness
	parameters.angle_randomness = angle_randomness
	parameters.random_seed = random_seed
	parameters.region_start_angle = region_start_angle
	parameters.region_span = region_span
	parameters.region_inner_radius_offset = region_inner_radius_offset
	parameters.region_slope_scale_offset = region_slope_scale_offset
	parameters.region_length_offset = region_length_offset
	parameters.region_angle_offset = region_angle_offset
	return parameters

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if outer_radius <= inner_radius:
		warnings.append("外半径需要大于内半径，否则无法生成条带。")
	var half_start := base_width * 0.5
	var half_end := maxf(half_start + maxf(outer_radius - inner_radius, 0.0) * ray_slope, 0.0)
	var angle_step := TAU / float(ray_count)
	if half_end * 2.0 > angle_step * outer_radius:
		warnings.append("条带端部宽度达到外半径处的相邻条带间距，相邻条带将重叠。")
	if inner_radius > 0.0 and half_start * 2.0 > angle_step * inner_radius:
		warnings.append("条带起点宽度达到内半径处的相邻条带间距，相邻条带将重叠。")
	return warnings
