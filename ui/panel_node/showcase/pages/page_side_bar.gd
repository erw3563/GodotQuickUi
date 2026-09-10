extends ShowcasePage
## 演示页·侧边栏 SideBarPanel：鼠标移到贴边收起条上展开、离开收起；
## 左上按钮组实时换贴边方向（LEFT/TOP/RIGHT/BOTTOM）。

func _ready() -> void:
	%SideLeft.pressed.connect(_on_side_button_pressed.bind(SideBarPanel.Side.LEFT))
	%SideTop.pressed.connect(_on_side_button_pressed.bind(SideBarPanel.Side.TOP))
	%SideRight.pressed.connect(_on_side_button_pressed.bind(SideBarPanel.Side.RIGHT))
	%SideBottom.pressed.connect(_on_side_button_pressed.bind(SideBarPanel.Side.BOTTOM))


## 换贴边方向。
func _on_side_button_pressed(side_value: SideBarPanel.Side) -> void:
	(%SideBar as SideBarPanel).side = side_value


## 贴边方向回右、收起。
func reset_page() -> void:
	_on_side_button_pressed(SideBarPanel.Side.RIGHT)
	(%SideBar as SideBarPanel).collapse()
