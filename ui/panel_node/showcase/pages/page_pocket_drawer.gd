extends ShowcasePage
## 演示页·口袋抽屉 PocketDrawerPanel：右上一角的可点击抽屉——
## 点击小块 ↔ 展开 4×2 背包色块格，真实尺寸与锚角随状态动画切换，
## 收起块上绘制标题「包」。抽屉与其内容完全序列化在本场景里。

## 展开抽屉。
func reset_page() -> void:
	(%Drawer as PocketDrawerPanel).expand()
