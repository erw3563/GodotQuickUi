extends ShowcasePage
## 演示页·飞向控件与重挂：源卡片经宿主树序先 QuickFlyTo 飞到目的地卡片中心，
## 再 QuickReparent 成为目的地子节点；「复位」经 restore() 挂回原父级并摆回起点。
## 组件经场景 NodePath 绑定 ui / target，节点路径先于 _ready 解析。

## 源卡片起点（页面本地布局坐标）。
const SOURCE_START := Vector2(80, 120)
## 目的地卡片摆位。
const DESTINATION_POS := Vector2(520, 180)


func _ready() -> void:
	%ButtonFly.pressed.connect((%AnimHost as QuickUiAnimHost).play)
	%ButtonReset.pressed.connect(reset_page)
	reset_page()


## 回缺省：归还父子关系，源卡片摆回起点。
func reset_page() -> void:
	var reparent := %Reparenter as QuickReparent
	reparent.restore()
	var source := %SourceCard as Control
	source.position = SOURCE_START
