# 敌人受击动作第一版 — 2026-11-18

## 改动

- `EnemyBase:ReactToImpact` 在原有局部部位回弹之外，记录方向性的身体后仰、侧倾和短退参数。
- `EnemyVisual:Update` 在敌人基础姿态上叠加受击姿态。普通命中使用较轻的 6° / 0.035m 档，重击和第三段使用较重的 10° / 0.06m 档，回收时间保持约 120ms。
- 受击方向先转换到敌人局部空间。侧击和正面命中产生不同的身体反应。
- 伤害、poise、硬直、击退、粒子数量和 shader 闪白协议没有改动。

## 验证

- PASS `enemy_logic.lua`
- PASS `enemy_visual.lua`
- PASS `enemy_revision19.lua`
- PASS `enemy_hit_event.lua`
- PASS `git diff --check`
- FAIL LSP，5 项工作区既有错误，本次改动文件没有新增错误。
- 全量离线当前 66 PASS / 9 FAIL，包含动画、相机、查询、武器 Rig、恢复姿态和既有体素生命周期失败。敌人专项回归没有失败。

尚未做 Web 真实敌人受击截图验收。shader 模板在离线 mock 中仍显示不可用，实际闪白需要 Web 构建日志确认。
