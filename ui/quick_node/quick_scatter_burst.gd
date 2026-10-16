class_name QuickScatterBurst
extends Node
## QuickUiAnimHost 的有限单次粒子步骤；场景显式引用 Scatter 的配置与生命周期。
## target 必须 one_shot=true；延时、取消、重播都通过 Scatter 生命周期入口。
signal play_finished
@export var target: PathPatternScatter2D
@export_range(0.0, 60.0, 0.01, "or_greater", "suffix:s") var delay := 0.0
var _active := false
var _connected_target: PathPatternScatter2D
func play() -> bool:
	interrupt()
	if not is_instance_valid(target) or not target.is_inside_tree() or not target.one_shot:
		return false
	_connected_target = target
	target.finished.connect(_on_finished)
	_active = true
	target.restart(delay)
	return true
func _on_finished() -> void:
	_disconnect()
	if not _active:
		return
	_active = false
	play_finished.emit()
func interrupt() -> void:
	_disconnect()
	if _active and is_instance_valid(_connected_target):
		_connected_target.stop()
	_active = false
	_connected_target = null
func _disconnect() -> void:
	if is_instance_valid(_connected_target) and _connected_target.finished.is_connected(_on_finished):
		_connected_target.finished.disconnect(_on_finished)
func get_playback_duration() -> float:
	return maxf(delay, 0.0) + target.get_burst_duration() + 1.0 / 30.0 if is_instance_valid(target) else 0.0
func _exit_tree() -> void:
	interrupt()
