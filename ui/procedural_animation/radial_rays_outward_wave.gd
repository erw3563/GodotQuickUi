@tool
## 放射条带向外波动：继承 RadialRays，用循环 Tween 推进环形相位，
## 按条带序号错相缩放（以放射中心为原点），形成沿环行进的规律外扩脉冲。
## 重建条带后自动恢复各条带缩放并按需重启 Tween；停止时各条带缩放归 1。
class_name RadialRaysOutwardWave
extends RadialRays

@export_group("向外波动")
## 进入树并完成首建后自动循环播放向外波动。
@export var wave_autoplay: bool = true:
	set(value):
		wave_autoplay = value
		if not is_inside_tree():
			return
		if wave_autoplay:
			play_wave()
		else:
			stop_wave()

## 相位走完一整圈（0→TAU）的时长（秒）。
@export_range(0.05, 30.0, 0.05, "or_greater", "suffix:s") var wave_duration: float = 2.0:
	set(value):
		wave_duration = maxf(value, 0.05)
		if _wave_tween != null and _wave_tween.is_valid():
			play_wave()

## 缩放振幅：条带缩放 = 1 + 振幅 × sin(相位 + 错相)；0 时保持原尺寸。
@export_range(0.0, 1.0, 0.01) var wave_amplitude: float = 0.18:
	set(value):
		wave_amplitude = maxf(value, 0.0)
		_apply_wave_scales()

## 环上一圈的波峰数量；越大相邻条带相位差越密，波动越碎。
@export_range(1, 16, 1) var wave_crest_count: int = 2:
	set(value):
		wave_crest_count = maxi(value, 1)
		_apply_wave_scales()

## 当前波动相位（弧度），由循环 Tween 推进；也可直接赋值预览某一帧姿态。
var wave_phase: float = 0.0:
	set(value):
		wave_phase = value
		_apply_wave_scales()

var _wave_tween: Tween

func _exit_tree() -> void:
	stop_wave()

## 重建几何后恢复波动缩放，并在自动播放开启时重启循环 Tween。
func _rebuild() -> void:
	super._rebuild()
	_apply_wave_scales()
	if wave_autoplay and is_inside_tree():
		play_wave()

## 启动（或重启）向外波动循环；已在播则先停再开。
func play_wave() -> void:
	_kill_wave_tween()
	if not is_inside_tree():
		return
	_wave_tween = create_tween()
	_wave_tween.set_loops()
	_wave_tween.tween_method(_set_wave_phase, 0.0, TAU, wave_duration)

## 停止波动并把各条带缩放恢复为 1。
func stop_wave() -> void:
	_kill_wave_tween()
	if wave_phase != 0.0:
		wave_phase = 0.0
	else:
		_apply_wave_scales()
	for ray in get_rays():
		ray.scale = Vector2.ONE

## 波动是否正在由 Tween 驱动。
func is_wave_playing() -> bool:
	return _wave_tween != null and _wave_tween.is_valid() and _wave_tween.is_running()

func _set_wave_phase(phase: float) -> void:
	wave_phase = phase

func _kill_wave_tween() -> void:
	if _wave_tween != null:
		if _wave_tween.is_valid():
			_wave_tween.kill()
		_wave_tween = null

## 按当前相位与振幅，把各条带缩放到 1 + 振幅 × sin(相位 + 环向错相)。
func _apply_wave_scales() -> void:
	var rays := get_rays()
	var count := rays.size()
	if count < 1:
		return
	for index in count:
		var phase_offset := float(index) / float(count) * float(wave_crest_count) * TAU
		var scale_factor := 1.0 + wave_amplitude * sin(wave_phase + phase_offset)
		rays[index].scale = Vector2(scale_factor, scale_factor)
