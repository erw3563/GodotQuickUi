@tool
class_name VisualEffectCue
extends Resource
## 一次性特效的共享配置；位置与朝向由应用现场冻结。
enum Origin { TARGET, SOURCE, CARRIER }
enum FacingMode { SOURCE_TO_TARGET, CARRIER_DIRECTION, FIXED }
@export var scenes: Array[PackedScene] = []
@export var origin: Origin = Origin.TARGET
@export var orientation: FacingMode = FacingMode.SOURCE_TO_TARGET
@export var offset := Vector2.ZERO
@export var fixed_direction := Vector2.RIGHT

func validate_configuration() -> String:
	if origin not in Origin.values() or orientation not in FacingMode.values(): return "invalid_visual_effect_role"
	if scenes.is_empty() or scenes.has(null): return "missing_visual_effect_scene"
	if not offset.is_finite() or not fixed_direction.is_finite() or fixed_direction.is_zero_approx(): return "invalid_visual_effect_placement"
	for scene in scenes:
		if not scene.can_instantiate(): return "invalid_visual_effect_scene"
		var instance := scene.instantiate()
		var visual := instance as VisualEffect2D
		var valid := visual != null and is_finite(visual.effect_duration()) and visual.effect_duration() > 0.0
		instance.free()
		if not valid: return "visual_effect_requires_finite_prefab"
	return ""

func duration() -> float:
	var longest := 0.0
	for scene in scenes:
		if scene == null: continue
		var instance := scene.instantiate()
		if instance is VisualEffect2D: longest = maxf(longest, instance.effect_duration())
		instance.free()
	return longest

## positions 使用 Origin 角色键；basis 只变换偏移与固定朝向。
func placement(positions: Dictionary, carrier_direction: Vector2, basis: Transform2D) -> Dictionary:
	if not positions.has(origin): return {"reason": "missing_visual_effect_origin"}
	var point: Vector2 = positions[origin]
	var heading := Vector2.ZERO
	match orientation:
		FacingMode.SOURCE_TO_TARGET:
			if not positions.has(Origin.SOURCE) or not positions.has(Origin.TARGET): return {"reason": "missing_visual_effect_direction"}
			heading = positions[Origin.TARGET] - positions[Origin.SOURCE]
		FacingMode.CARRIER_DIRECTION:
			heading = carrier_direction
		FacingMode.FIXED:
			heading = basis.basis_xform(fixed_direction)
	if not point.is_finite() or not heading.is_finite() or not basis.is_finite() or absf(basis.determinant()) < 0.000001: return {"reason": "invalid_visual_effect_transform"}
	if heading.is_zero_approx(): heading = basis.basis_xform(fixed_direction)
	return {"reason": "", "position": point + basis.basis_xform(offset), "direction": heading.normalized()}
