extends ShowcasePage
## QuickMask 演示页：纹理遮罩显隐——遮罩图案决定显隐的形状语言；「显示 / 隐藏」两个
## 按钮各自把 target_progress 设为目标端后调统一播放契约 play()，「换图案」循环内置
## 8 种遮罩图案。遮罩本体即视觉，ui 指向 Stage、矩形自动跟随。

const PATTERN_ORDER: PackedStringArray = [
	"circle", "curtains", "diagonal", "horizontal",
	"radial", "scribbles", "squares", "vertical",
]

var _pattern_index := 0


func _ready() -> void:
	var mask := %Mask as QuickMask
	mask.set_pattern(PATTERN_ORDER[_pattern_index])
	%ButtonShow.pressed.connect(_on_show_pressed)
	%ButtonHide.pressed.connect(_on_hide_pressed)
	%ButtonPattern.pressed.connect(_on_pattern_pressed)


func _on_show_pressed() -> void:
	var mask := %Mask as QuickMask
	mask.target_progress = 1.0
	mask.play()


func _on_hide_pressed() -> void:
	var mask := %Mask as QuickMask
	mask.target_progress = 0.0
	mask.play()


func _on_pattern_pressed() -> void:
	var mask := %Mask as QuickMask
	_pattern_index = (_pattern_index + 1) % PATTERN_ORDER.size()
	mask.set_pattern(PATTERN_ORDER[_pattern_index])


func reset_page() -> void:
	var mask := %Mask as QuickMask
	_pattern_index = 0
	mask.set_pattern(PATTERN_ORDER[_pattern_index])
	mask.target_progress = 1.0
	mask.progress = 1.0
