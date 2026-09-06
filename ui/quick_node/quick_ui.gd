class_name QuickUI
extends RefCounted
## 快捷系共享原语：统一「布局稳定」时序与「落笔意图」枚举。
## 位置落笔契约（原 place 静态汇入点）已并入 [class QuickHost] 中介：
## 写位置组件（QuickDrag / QuickMousePlace）只提议，经宿主按意图裁决、过
## stage 链（apply_place 契约）后唯一落笔；演出组件（QuickPopOut）
## 走租约通道。详见 [class QuickHost] 类注释。

## 落笔意图：宿主中介的固定优先级（高 → 低）——交互可打断演出，演出挡住定位。
enum PlaceIntent {
	INTERACTIVE,  ## 拖拽跟手等交互落笔：打断进行中的演出租约后经 stage 链落笔。
	PRESENTATION, ## 演出端点（QuickPopOut 屏外起止）：直写，不经 stage 加工。
	PLACEMENT,    ## 一次性定位 / 休息位登记 / 持续回收：演出租约期间被忽略。
}

## 等两帧让容器 / 锚点布局稳定（入树后采样位置、改内容后采尺寸等场景调用）。
## 等待期间节点被移除 / 释放时安全返回（如宿主移除子节点打断仍在挂起的初始化协程；
## 静态协程不绑定实例，恢复时须自行校验，避免访问已释放节点）。
static func layout_settled(node: Node) -> void:
	if node == null or not node.is_inside_tree():
		return
	var tree := node.get_tree()
	await tree.process_frame
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	await tree.process_frame
