# 诺米修长版：结构、配色与验证

2026-11-10。运行时只实例化修长版；Q 版与 M 切换入口已移除。
三位 GPT-6.1 Sol worker 分别完成关节、分层结构、语义色板的只读调研。

## 可重复生成

依赖 Python 3、numpy、scipy、Pillow。在项目根运行：

    python3 art/nomi_voxel/voxelize.py
    python3 art/nomi_voxel/check_mesh.py

- voxelize.py 仍负责原三视图采样；refine.py 在采样结果上完成结构化精修。
- approved_head.json 是 4860c3b 版本的头部几何和原始 RGB 基准，不要用新结果覆盖它。
- 整个头部几何保持不变；面部保护区原 RGB 原样复制，其余发面改用银白色板。
- 外套/内衬、折叠帽兜、前后发束、袖口和内裙是独立的有厚度网格。
- 外套截面与发束中心线分别定义，头发不再依赖衣背逐行深度；衣服表面不采头发色。
- 腿的关节链为 root → leg → shin。髋位于裙内，膝有闭合圆柱接合面；靴子随小腿。
- 1.35 倍腿长和身体宽深变化在顶点与挂点上烘焙，腿骨保持单位缩放。原修长版头部 .82、身体 .85/.92、整体抬高 .1386m 不变。
- 运行时的唯一体型定义位于 BlockCharacter.SLENDER，主场景与骑龙场景共用。

preview_3d.png / compare.png 为精修后的修长模型离线预览；preview.png、grids.png、mask.png 和 views.npz 是早期采样过程参考，不是当前游戏画面。
.tmp/nomi-review/ 存本轮对比与动作证据，不参与提交。
离线渲染检查真实导出三角形，但不模拟游戏 PBR、投影和后处理。

## 无头动作验证

将 rig_validate.lua 临时复制到 scripts/_nomi_rig_validate.lua，使用 Maker 本地验证：

    entry: dragon_main.lua
    test: _nomi_rig_validate.lua
    mode: validate
    frames: 120
    timeout_seconds: 45

验证后删除临时脚本；不启动窗口。
测试在独立 Scene 内实例化生产 BlockCharacter（V 脚本和游戏的模块缓存独立），
用生产 DragonRide.New / SeatPose / AttachToSaddle 验证鞍座对齐。
覆盖待机、走、跑、跳、蹲、骑乘、下龙恢复与 90° 膝弯，记录引擎实际 LocalToWorld 矩阵。
77 项断言通过；测试的是关节变换与骑乘挂点，不等于完成整场游戏交互或所有衣物碰撞验收。

最终报告：.maker/validation-evidence/8c3093c7-35b2-48af-97ee-37113a3b0148/validate.json
结果 PASS，Lua / 资源 / 引擎错误均为 0。
较早失败报告保留在 .maker/validation-evidence/：两次测试包装错误（独立模块缓存、SeatPose 非导出静态方法），随后定位并修复鞍座只按 Y 对齐的实际偏移。

check_mesh.py 检查完整头部几何不变、544 个面部保护区三角形 RGB 不变、非头部 10 色、垂发两色、后发与帽兜的静止间距、有效三角形与关节父子链。
静止间距只是静止结构证据，动作需要看捕获矩阵重建的多帧图。

本轮使用项目现存 ref_ysm_navy.png；用户提到的另一张外套/内衬拆件图尚未定位，未声称已参考该图。
