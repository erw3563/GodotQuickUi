extends Node2D
## PathMorph 挂点生长演示：横向直线变形为 LightningPathGenerator 生成的分叉闪电，停顿后变回直线，循环播放。
## Morph 节点在场景中设为 GROW_FROM_ANCHOR，枝杈从主干挂点沿弧长长出、回程反向收回；
## Ribbon 节点以 PathRibbon2D 默认方式绘制 Morph 的输出。
## 一个周期：直线 0.5 秒、变形 1.5 秒、闪电 1 秒、变回 1.5 秒、直线 0.5 秒。

const HOLD_LINE := 0.5
const MORPH := 1.5
const HOLD_BOLT := 1.0
const CYCLE := HOLD_LINE * 2.0 + MORPH * 2.0 + HOLD_BOLT
const LINE_START := Vector2(173, 360)
const LINE_END := Vector2(1107, 360)
const WIDTH := 3.0

@onready var _morph: PathMorph = $Morph
@onready var _ribbon: PathRibbon2D = $Ribbon
var _elapsed := 0.0

func _ready() -> void:
	var line := Curve2D.new()
	line.add_point(LINE_START)
	line.add_point(LINE_END)
	var source := PathDefinition.new()
	source.add_path(line, WIDTH)
	var generator := LightningPathGenerator.new()
	generator.start_point = LINE_START
	generator.end_point = LINE_END
	var metadata := generator.generate_with_metadata()
	var destination: PathDefinition = metadata.definition
	destination.set_uniform_width(WIDTH)
	_morph.source = source
	_morph.destination = destination
	_morph.destination_anchors = metadata.anchors
	_ribbon.definition = _morph.output

func _process(delta: float) -> void:
	var time := fmod(_elapsed, CYCLE)
	_elapsed += delta
	var back := HOLD_LINE + MORPH + HOLD_BOLT
	if time < back:
		_morph.progress = _ease((time - HOLD_LINE) / MORPH)
	else:
		_morph.progress = 1.0 - _ease((time - back) / MORPH)

## 与 PathMorph.play_to 相同的五次缓动，端点速度与加速度为零。
static func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
