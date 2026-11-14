# W4：自由朝向下的动画姿态清理

基线：`96ffec9`；开始时 tracked clean，仅有其它任务的 sky-fx 未跟踪产物。未 commit/push/build，未启动本地游戏 Runtime。并行改动未清理。

## 修改范围与依据

- `scripts/combat/AnimClips.lua`：重击的手握点已经绕行360°，原躯干再转−360°会叠加第二圈上身运动。改成40→55→8→−35→−45→0°有限转腰，保留完整手部圆弧。四种近战补右腿支撑姿态（与左腿反相，幅度65%），避免只有左腿被招式覆盖、右腿继续跑步；按最终躯干姿态重新计算头部反向补偿。
- `scripts/combat/CombatAnim.lua`：弓的瞄准方向先去除当前躯干旋转，再求单段臂IK；武器与头部也补偿躯干，防止固定6°前倾和满蓄微动叠进准星方向。右手保持在右脸外侧，目标相对肩为 `(0.06+0.02p, 0.02+0.10p, 0.32−0.17p)` 米，再施加瞄准俯仰并转换父空间，仍投影至真实固定臂长。松手先后撤最多0.03m，左手保向0.08s后随收招放下；取消拉弓沿相同姿态放松，不再突然侧转35°。
- `tests/combat/anim_spec.lua`：补自由朝向不干扰根节点、双脚覆盖步态、躯干/头部补偿、弓完整旋转链、收招和基线合同对比。`anim_mock.lua`本轮无修改。

阅读依据：项目AGENTS、Lua指南、Math/Quaternion定义、state-machine说明、R6完整调研；参考体素示例 `PlayerBody.lua`（基础步态与挥臂覆盖）、`FirstPersonArm.lua`（预备/挥出节奏）、`CameraController.lua`（相机yaw/pitch与角色姿态分层）。本角色仍为节点骨骼，不迁移AnimatedModel/FSM。

## 给 W2 的边界

1. 攻击朝向仍由W2在接受攻击时设置/快照；动画只改局部骨骼，不改控制节点或root旋转，也不改root的x/z。不需要再把身体yaw加到判定方向。
2. `duration/events/phases/motion/speedStat/realTime/cancelAt/cancelBlend`与96ffec9逐项完全一致，24个片段均覆盖。剑前冲仍为0.50/0.45/0.70/0.65m，滑步仍2.20m；消费原GetMotion即可，不添加第二份踏步。手握点圆弧与IK坐标约定均未改。
3. 每帧在Apply前用 `SetParam("aimPitch", pitchDegrees)`，正值向下，夹±35°；`SetParam("p", charge)`保持原0..1语义。进入bow_release/bow_cancel时，请在Play的params或随后的SetParam中传入释放瞬间p与pitch，否则新片段默认p=0/pitch=0。保持该p到收招结束；路径自行完成后撤/放松。
4. 完整瞄准旋转链为 `controllerFacing * body * arm * gripRest * swing`；最终弓指向`controllerFacing * Quaternion(clampedPitch,0,0)`。头部相对准星额外低4°，仍看目标区域。不要另加一次胸部俯仰补偿。
5. 继续 `nomi:Update → anim:Apply → rig:SetSwing`。HandSocket接线、默认关闭肘开关、体型/脸/衣服/头发与武器几何均未改。单段手臂仍有无法精确贴弦/贴脸的几何限制，无拉伸、无新增肘求解。
6. legacyPose=1保留原关键姿态；opts.pathIK=false保留关闭路径的入口。游戏热路径无新增Lua表或节点重建，既有缓存/队列复用不变；新增仅数值计算与四元数绑定操作。

## 检查结果

`ANIM_BASELINE_FILE=validation/combat/free-facing-anim/AnimClips-baseline.txt python3 -c 'from lupa.lua54 import LuaRuntime; LuaRuntime().execute(open("tests/combat/anim_spec.lua").read())'` / PASS（67项） / `/Users/xd/Desktop/体素test/validation/combat/free-facing-anim/anim-regression.log`

`git show 96ffec9:scripts/combat/AnimClips.lua + anim_spec基线逐项对比` / PASS / `/Users/xd/Desktop/体素test/validation/combat/free-facing-anim/contract-check.log`

`maker-lua-lsp --mode watch --http-port 19556 + textDocument/diagnostic severity=1` / PASS（4个动画/测试文件零Error） / `/Users/xd/Desktop/体素test/validation/combat/free-facing-anim/lsp-diagnostics.json`

`git diff --check -- scripts/combat/AnimClips.lua scripts/combat/CombatAnim.lua tests/combat/anim_spec.lua` / PASS / `/Users/xd/Desktop/体素test/validation/combat/free-facing-anim/diff-check.log`

`/review（人工差异审查）` / PASS / `/Users/xd/Desktop/体素test/validation/combat/free-facing-anim/review.log`

视觉、相机遮挡、前脚真实接地、武器弦与右手贴合、自由朝向转身手感：**未验证，待Web预览**。数学检查不能替代画面验收，符号仍待Web校准。
