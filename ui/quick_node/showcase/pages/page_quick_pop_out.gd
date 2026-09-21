extends ShowcasePage
## 演示页·弹入弹出 QuickPopIn / QuickPopOut：卡片经入场宿主从屏下飞到屏幕中心，
## 经离场宿主从当前位置飞出到所选屏外端点。位置件声明比例目标——控件上的贴合点
## origin_ratio 对齐 视口尺寸 × target_ratio；「贴合点」下拉切换两端 origin_ratio，
## 卡片随新贴合点重新贴到当前目标点。起点与可见性由本页摆放。组件经场景 NodePath
## 绑定 ui，节点路径先于 _ready 解析。

const EXIT_TEXTS: Array[String] = ["向屏上离开", "向屏下离开", "向屏左离开", "向屏右离开"]
const EXIT_RATIOS: Array[Vector2] = [
	Vector2(0.5, -0.5),
	Vector2(0.5, 1.5),
	Vector2(-0.5, 0.5),
	Vector2(1.5, 0.5),
]
## 入场目标：屏幕中心。
const ENTER_TARGET := Vector2(0.5, 0.5)
## 入场起点：入场目标沿 y 轴退一屏，卡片由屏下飞入。
const ENTER_START := ENTER_TARGET + Vector2(0.0, 1.0)
const ORIGIN_TEXTS: Array[String] = ["中心贴合", "左上贴合", "右下贴合"]
const ORIGIN_RATIOS: Array[Vector2] = [Vector2(0.5, 0.5), Vector2.ZERO, Vector2.ONE]


func _ready() -> void:
	var option := %DirectionOption as OptionButton
	for item_index in EXIT_TEXTS.size():
		option.add_item(EXIT_TEXTS[item_index])
	option.item_selected.connect(_on_exit_target_selected)
	var origin_option := %OriginOption as OptionButton
	for item_index in ORIGIN_TEXTS.size():
		origin_option.add_item(ORIGIN_TEXTS[item_index])
	origin_option.item_selected.connect(_on_origin_selected)
	%ButtonPopOut.pressed.connect((%ExitHost as QuickUiAnimHost).play)
	%ButtonPopIn.pressed.connect(_play_enter)
	reset_page()


func _on_exit_target_selected(item_index: int) -> void:
	(%PopperOut as QuickPopOut).target_ratio = EXIT_RATIOS[item_index]


## 换贴合点：入口与出口件同步改 origin_ratio，卡片立即按新贴合点贴回入场目标位。
func _on_origin_selected(item_index: int) -> void:
	var origin := ORIGIN_RATIOS[item_index]
	(%PopperIn as QuickPopIn).origin_ratio = origin
	(%PopperOut as QuickPopOut).origin_ratio = origin
	_place_card(ENTER_TARGET)


## 弹出：把卡片摆到屏下起点再经入场宿主播放到屏幕中心。
func _play_enter() -> void:
	_place_card(ENTER_START)
	(%TargetCard as Control).visible = true
	(%EnterHost as QuickUiAnimHost).play()


## 回缺省：贴合点回中心、离场端点回屏下、卡片落回屏幕中心并隐藏，等待下一次弹出。
func reset_page() -> void:
	(%OriginOption as OptionButton).select(0)
	(%DirectionOption as OptionButton).select(1)
	_on_origin_selected(0)
	(%PopperOut as QuickPopOut).target_ratio = EXIT_RATIOS[1]
	_place_card(ENTER_TARGET)
	(%TargetCard as Control).visible = false


## 把卡片摆到比例点：控件上的贴合点对齐 视口尺寸 × ratio。
func _place_card(ratio: Vector2) -> void:
	var card := %TargetCard as Control
	var origin := (%PopperIn as QuickPopIn).origin_ratio
	card.position = QuickUI.global_to_layout(
		card, get_viewport_rect().size * ratio - card.size * origin
	)
