# 下肢保留步态与身体转向先导 — 2026-11-18

用户要求攻击时保留下肢步态，身体先转。

## 实现

- `CombatAnim.Apply` 在 `ATTACK` 层跳过 `leg_right` 与 `leg_left`，攻击片段仍保留腿部关键帧用于数据预览，运行时继续使用基础姿态或 `sprint_loop` 的腿部结果。
- 剑攻击的身体姿态改为相对于当前基础身体姿态叠加，保留移动和步态倾斜，再叠加剑招躯干转向。弓和法器不走这条剑专用叠加。
- 武器 IK、攻击事件、刀刃轨迹和体素破坏接线没有改动。

## 验证

- PASS `tests/nomi/elbow_rig.lua` 与 `tests/combat/anim_spec.lua`，覆盖双段手臂绑定、掌心挂点、动画事件、IK、腿部保留与身体叠加。
- FAIL `python3 tests/nomi/run_offline.py`，72 PASS / 2 FAIL。
  - `tests/combat/recovery_holo.lua:61` 当前低位护手断言失败，属于现有恢复姿态数据与断言不一致。
  - `tests/ruins/time_object_lifecycle.lua:35` 既有 world-owned render nodes 生命周期失败。
- FAIL LSP，5 项既有错误。改动文件没有新增 LSP 错误。
- PASS `git diff --check`。

尚未做 Web 或 Windows 真实动作截图验收。
