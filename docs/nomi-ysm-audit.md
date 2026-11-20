# 诺米 YSM Blockbench 源包检查

来源：`/Users/xd/Downloads/诺米/`

这份不是只有模型的 bbmodel，而是一套完整的 YSM 动画源包：

- `诺米.bbmodel`：含 Blockbench 动画数据
- `YSM源包/models/main.json`、`arm.json`
- `YSM源包/animations/main.animation.json`：walk、idle、run、jump、sneak、swim、sit、ride、swing 等
- `YSM源包/animations/arm.animation.json`：剑、弓、盾、矛、十字弩等持械和使用动作
- `YSM源包/animations/tac.animation.json`、`extra.animation.json`
- `预览/分骨动作/`：逐帧动作参考图和 GIF

已经从 `诺米.bbmodel` 提取出可接入 CombatAnim 的基础片段：

- `art/animation/nomi_yms_walk.lua`
- `art/animation/nomi_yms_run.lua`
- `art/animation/nomi_yms_sneak.lua`

提取结果覆盖 `body/head/arm/forearm/leg/hair/skirt`，walk 为 1 秒、230 个关键帧；run 为 0.6667 秒、162 个关键帧。带 `ysm.*` 变量表达式的复杂片段暂时跳过了非数值关键帧，避免把 YSM 专用表达式误当成固定角度。

结论：这套源包比项目里当前手写的正弦步态更有价值，尤其是 `walk/run/sneak` 和 `arm.animation.json` 的持械动作。下一步可以把提取片段接入 F7 预览，再按诺米当前骨骼的坐标约定做一次轴向校准；不需要重新找外部 MC 动作包。
