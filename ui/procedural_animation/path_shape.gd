@tool
class_name PathShape
extends Resource

## 单条路径的中心曲线、笔画宽度和宽度曲线。
signal geometry_changed
signal widths_changed

@export var curve: Curve2D:
	set(value):
		if curve == value:
			return
		if curve != null and curve.changed.is_connected(_geometry_changed):
			curve.changed.disconnect(_geometry_changed)
		curve = value
		if curve != null:
			curve.changed.connect(_geometry_changed)
		_geometry_changed()

@export_range(0.0, 4096.0, 0.1, "or_greater") var width := 1.0:
	set(value):
		var next := maxf(value, 0.0) if is_finite(value) else 1.0
		if width == next:
			return
		width = next
		_widths_changed()

## 横轴为路径归一化进度，纵轴为笔画宽度倍率。
@export var width_profile: Curve:
	set(value):
		if width_profile == value:
			return
		if width_profile != null and width_profile.changed.is_connected(_widths_changed):
			width_profile.changed.disconnect(_widths_changed)
		width_profile = value
		if width_profile != null:
			width_profile.changed.connect(_widths_changed)
		_widths_changed()

func sample_width(progress: float) -> float:
	var multiplier := width_profile.sample(clampf(progress, 0.0, 1.0)) if width_profile != null else 1.0
	return width * maxf(multiplier, 0.0) if is_finite(multiplier) else 0.0

func _geometry_changed() -> void:
	geometry_changed.emit()
	emit_changed()

func _widths_changed() -> void:
	widths_changed.emit()
	emit_changed()
