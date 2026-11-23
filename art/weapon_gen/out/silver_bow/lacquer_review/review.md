# 银枝弓银漆复核

同一套三盏面光和正交相机，Cycles CPU 42 采样，AgX。

| 视图 | 改前实图 | 改后实图 | 轮廓 IoU |
|---|---|---|---|
| 左侧 | [原图](before/preview_left.png) | [原图](../preview_left.png) | 1.00000 |
| 正面 | [原图](before/preview_front.png) | [原图](../preview_front.png) | 1.00000 |
| 右侧 | [原图](before/preview_right.png) | [原图](../preview_right.png) | 1.00000 |
| 斜视 | [原图](before/preview_iso.png) | [原图](../preview_iso.png) | 1.00000 |

[并排对比](before-after.png) · [Blender 场景](../silver_bow.blend)

枝体银漆金属度 0.62、粗糙度 0.36、清漆权重 0.82、清漆粗糙度 0.16。
展示间克隆 SilverBow.xml；清漆只覆盖木枝材质通道。
