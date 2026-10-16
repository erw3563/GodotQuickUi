@tool
class_name PathDefinition
extends Resource

## 路径集合资源：每个 Shape 持有中心曲线、笔画宽度与宽度曲线。
## 集合编辑通过整体重赋值或集合操作方法提交。
signal geometry_changed
signal widths_changed

@export var shapes: Array[PathShape] = []:
	set(value):
		var normalized: Array[PathShape] = []
		var curves: Array[Curve2D] = []
		for shape in value:
			normalized.append(shape)
			curves.append(shape.curve if shape != null else null)
		_pending_geometry = _pending_geometry or curves != _curve_snapshot
		_curve_snapshot = curves
		_disconnect_shapes()
		shapes = normalized
		_bind_shapes()
		_pending_widths = true
		_flush_changes()

var _bound_shapes: Array[PathShape] = []
var _curve_snapshot: Array[Curve2D] = []
var _batch_depth := 0
var _pending_geometry := false
var _pending_widths := false

func begin_update() -> void:
	_batch_depth += 1

func end_update() -> void:
	_batch_depth = maxi(_batch_depth - 1, 0)
	_flush_changes()

func _notify_geometry() -> void:
	_curve_snapshot = get_curves()
	_pending_geometry = true
	_flush_changes()

func _notify_widths() -> void:
	_pending_widths = true
	_flush_changes()

func _flush_changes() -> void:
	if _batch_depth > 0:
		return
	var geometry := _pending_geometry
	var widths := _pending_widths
	_pending_geometry = false
	_pending_widths = false
	if geometry:
		geometry_changed.emit()
	if widths:
		widths_changed.emit()
	if geometry or widths:
		emit_changed()

func _disconnect_shapes() -> void:
	for shape in _bound_shapes:
		if shape.geometry_changed.is_connected(_notify_geometry):
			shape.geometry_changed.disconnect(_notify_geometry)
		if shape.widths_changed.is_connected(_notify_widths):
			shape.widths_changed.disconnect(_notify_widths)
	_bound_shapes.clear()

func _bind_shapes() -> void:
	for shape in shapes:
		if shape != null and not _bound_shapes.has(shape):
			_bound_shapes.append(shape)
			shape.geometry_changed.connect(_notify_geometry)
			shape.widths_changed.connect(_notify_widths)

## 接收编辑器提供的无类型数组，完整校验后以 Array[PathShape] 提交集合。
func set_shapes(values: Array) -> void:
	var normalized: Array[PathShape] = []
	for entry in values:
		if entry != null and not entry is PathShape:
			push_error("PathDefinition.set_shapes requires PathShape or null entries; resource unchanged.")
			return
		normalized.append(entry)
	shapes = normalized

## 返回曲线数组的独立快照，曲线资源保持原有身份。
func get_curves() -> Array[Curve2D]:
	var result: Array[Curve2D] = []
	for shape in shapes:
		result.append(shape.curve if shape != null else null)
	return result

## 按曲线身份重新排列 Shape，并保留对应宽度；新增曲线采用 1 像素恒定宽度。
func set_curves(curves: Array) -> void:
	for curve in curves:
		if curve != null and not curve is Curve2D:
			push_error("PathDefinition.set_curves requires Curve2D or null entries; resource unchanged.")
			return
	var remaining := shapes.duplicate()
	var next: Array[PathShape] = []
	for curve in curves:
		var found: PathShape
		for entry in remaining:
			if entry != null and entry.curve == curve:
				found = entry
				remaining.erase(entry)
				break
		if found == null:
			found = PathShape.new()
			found.curve = curve
		next.append(found)
	begin_update()
	shapes = next
	end_update()

func add_path(curve: Curve2D, width: float = 1.0, profile: Curve = null) -> PathShape:
	var entry := PathShape.new()
	entry.curve = curve
	entry.width = width
	entry.width_profile = profile
	var next := shapes.duplicate()
	next.append(entry)
	begin_update()
	shapes = next
	end_update()
	return entry

func remove_path(index: int) -> void:
	if index < 0 or index >= shapes.size():
		return
	var next := shapes.duplicate()
	next.remove_at(index)
	begin_update()
	shapes = next
	end_update()

func move_path(from: int, to: int) -> void:
	if from < 0 or to < 0 or from >= shapes.size() or to >= shapes.size() or from == to:
		return
	var next := shapes.duplicate()
	var entry: PathShape = next.pop_at(from)
	next.insert(to, entry)
	begin_update()
	shapes = next
	end_update()

func sample_width(index: int, progress: float) -> float:
	return shapes[index].sample_width(progress) if index >= 0 and index < shapes.size() and shapes[index] != null else 0.0

func set_path_width(index: int, width: float, profile: Curve = null) -> void:
	if index < 0 or index >= shapes.size() or shapes[index] == null:
		return
	begin_update()
	shapes[index].width = width
	shapes[index].width_profile = profile
	end_update()

func set_uniform_width(width: float, profile: Curve = null) -> void:
	begin_update()
	for shape in shapes:
		if shape == null:
			continue
		shape.width = width
		# 每条路径持有可独立编辑的宽度曲线。
		shape.width_profile = profile.duplicate() as Curve if profile != null else null
	end_update()

## 将源路径宽度复制到当前几何，并为每条路径复制宽度曲线。
func copy_widths_from(source: PathDefinition, source_indices: PackedInt32Array = []) -> void:
	begin_update()
	for i in shapes.size():
		var source_index := source_indices[i] if i < source_indices.size() else i
		var entry := source.shapes[source_index] if source != null and source_index >= 0 and source_index < source.shapes.size() else null
		set_path_width(i, entry.width if entry != null else 1.0, entry.width_profile.duplicate() as Curve if entry != null and entry.width_profile != null else null)
	end_update()
