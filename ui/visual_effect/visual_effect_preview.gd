@tool
class_name VisualEffectPreview
extends RefCounted
## 独占预制按固定步长确定性采样；定位回退重建本次实例。
const SAMPLE_STEP := 1.0 / 60.0
var cue: VisualEffectCue
var playback: VisualEffectPlayback
var _position := -1.0
var _placement: Dictionary
var _duration := 0.0

func configure(host: Node2D, configuration: VisualEffectCue, positions: Dictionary, carrier_direction: Vector2, basis: Transform2D) -> String:
	cue = configuration
	playback = VisualEffectPlayback.new(host)
	var reason := cue.validate_configuration()
	if not reason.is_empty(): return reason
	_duration = cue.duration()
	_placement = cue.placement(positions, carrier_direction, basis)
	return _placement.reason

func seek(time: float) -> void:
	if playback == null or not String(_placement.get("reason", "unconfigured")).is_empty(): return
	if time < 0.0:
		clear()
		return
	if _position < 0.0 or time < _position:
		playback.clear()
		for scene in cue.scenes: playback.play_prefab(scene, _placement.position, _placement.direction)
		_position = 0.0
	var target := minf(time, _duration)
	while _position < target - 0.000001:
		var delta := minf(SAMPLE_STEP, target - _position)
		playback.advance(delta)
		_position += delta

func clear() -> void:
	if playback != null: playback.clear()
	_position = -1.0
