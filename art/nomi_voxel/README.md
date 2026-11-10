# 诺米修长版：局部撤回与验证

2026-11-10。衣服简化丢失设计细节，本轮选择性撤回，不重写 Git 历史。

## 当前保留与恢复范围

- 只使用修长版，保留 7c4cd05 的统一 BlockCharacter.SLENDER 配置；Q 版与 M 切换入口继续移除。
- 非头发部分的几何和顶点 RGB 精确恢复到 4860c3b，包括领口、袖口、裙褶、靴子、外套破边与配色。
- 保留 3db8f6f 的头部及独立前后发束；面部保护区的几何和 RGB 不变。
- 骨骼恢复原来的 16 根。BlockCharacter 与 DragonRide 恢复 7c4cd05 版本，不再包含被撤回的膝关节与骑乘调整。
- 此模型的衣服花纹使用顶点色；上轮细节损失来自几何替换和重新着色，并非贴图漏加载。

## 可重复生成与精确比对

依赖 Python 3、numpy、scipy、Pillow。在项目根运行：

    python3 art/nomi_voxel/voxelize.py
    python3 art/nomi_voxel/check_mesh.py

voxelize.py 负责原三视图采样；refine.py 只精修头部和发束，其余部分原样透传。
approved_head.json 是原头部保护基准，勿用新结果覆盖。
rollback_baseline.json 保存原衣服/四肢、认可的头发以及原骨骼的比对基准。
检查包括完整头部几何、544 个面部保护区三角形 RGB、非头发几何/RGB、认可的头发和原骨骼表。

preview_3d.png / compare.png 为当前修长模型离线预览；早期采样图片不代表当前游戏画面。
.tmp/nomi-review/ 为本地证据，不提交。离线预览不模拟游戏 PBR、投影和后处理。

## 无头运行检查

将 rig_validate.lua 临时复制到 scripts/_nomi_rig_validate.lua，通过 Maker 验证：

    entry: dragon_main.lua
    test: _nomi_rig_validate.lua
    mode: validate
    frames: 120
    timeout_seconds: 45

验证后删除临时脚本，不启动窗口。脚本在独立 Scene 中实例化生产角色，
检查原 16 骨骼、修长配置、无 Q 切换和待机/行走/跑步/跳跃/下蹲调用。
它是回退后的加载与运行检查，不是腿部接缝、骑乘对齐或衣物碰撞的视觉验收。

## 后续约束

旧衣服的杂色、阶梯形结构和原动画问题随局部撤回保留，尚待针对性修复。
后续清理要保留领口、装饰、裙褶、破边与靴子设计，只清除误采样噪点和不合理粘连，
不得再次以大块纯色网格替换整件衣服。
参考仍是 art/nomi_ysm/ref/ref_ysm_navy.png；用户提到的外套/内衬拆件图尚未定位。

## 2026-11-10：恢复发色细节与局部白点清理

在 5a9ea6e 基础上，完整恢复 approved_head.json 的头部 RGB（包括发缕、编发和发饰配色）。
前后独立发束的几何和颜色保持不变；所有衣服和身体几何、骨骼、比例、动画均未修改。
仅清理圈定外套胸侧、内侧袖面及破边尾片上的误采样浅色，不改领口、袖口、内裙、袜口和靴子。
detail_cleanup.json 记录逐面颜色改动；check_mesh.py 将这些改动反向还原后与原服装摘要核对，
确保未圈定细节不被一并删掉，并核对完整头部原始 RGB 和已认可的独立发束。
