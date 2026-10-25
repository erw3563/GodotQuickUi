@tool
class_name ProjectileVisualEffect2D
extends Node2D
## 特效预制的统一手动播放接口；素材、粒子与动画由预制自身持有。
## 播放拥有者负责时钟、实例释放和飞行阶段的运动采样。

func start_effect(world_position: Vector2, _direction: Vector2, _seed: int = 0) -> void:
	global_position = world_position

func follow_effect(world_position: Vector2, _velocity: Vector2, _delta: float) -> void:
	global_position = world_position

func advance_effect(_delta: float) -> void:
	pass

## 结束持续发射；有限尾迹与一次性表现继续推进到自然结束。
func stop_effect() -> void:
	pass

func effect_finished() -> bool:
	return true
