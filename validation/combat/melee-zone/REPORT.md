# P1 近战区域判定（2026-11-14）

实现完成，未提交/构建/推送，未启动 Runtime。Lead 报告的真实引擎 F11 失败是本轮输入证据；本报告只声称离线几何回归通过，仍须 Lead 原生/Web 重跑。

## 判定变化

- 近战不再调用 Rig.GetHit()。刀身/动画只负责表现，不再是伤害前提。
- hit_on 快照角色水平朝向；每次 AfterPose 使用当前真实角色位置平移区域，前冲会移动区域。风向/骨骼摆动不改变已开始攻击的方向。hit_on/hit_off 仍是唯一判定窗口，跨整个活动窗口的低帧率单帧保留 hitPending 一次结算。
- 普攻1/2：1.8m×reach，120°。
- 普攻3：同半径，100°，区域原点前移0.4m。
- 重击：360°，1.8m×reach；现有活动窗口最后三分之一再并入正前90°/2.0m×reach下砸区。它们共用同一 swing 账本，不增加判定窗口、不重复扣血。
- 所有区域的垂直范围为脚底−0.3m到+2.0m；球体检查与有限扇形柱体真实相交，不是只检查球心。可支持 capsule {a,b,radius}：凸区距离最小化，避免用离散端点样本漏掉穿过区域的细胶囊。
- 接触按距离排序，优先取近侧 hurtShape 表面；擦边时保留两几何体实际重叠点。正常使用接触点做墙体射线检查。最近且可见的部位确定 weak/material/part，统一 HitEvent/粒子/音频/镜头/顿帧原链保持。
- 每敌人每段只扣一次血；stone_* 石弹继续按原规则作为独立可弹反目标，不会占用敌人身体的伤害次数。
- F11 三连结束新增 CombatTest: combo_all_hit PASS|FAIL stage1=... stage2=... stage3=...，只读取实际结算反馈，不以 hit_on 冒充命中。

## 文件

- scripts/combat/Hit.lua：QueryZone 球/胶囊与扇形柱体查询。
- scripts/combat/CombatMoves.lua：MeleeZone、hit_on 朝向快照、区域查询取代刀身胶囊。
- scripts/combat/CombatTest.lua：三连整体检查行。
- tests/combat/core_melee_zone.lua（新）、tests/combat/core_selftest.lua。

本轮未触及 Scene/Nomi/地形/谜题/敌人/武器/动画；CombatMoves 中此前 §20 未提交补丁完整保留。其他会话云层/文档以及W1/W4修改均保留；没有新增游戏资源或游戏Lua文件，不需新增.meta。

## 验证与证据

python3 validation/combat/juice/run_tests.py / PASS / /Users/xd/Desktop/体素test/validation/combat/melee-zone/tests.log

25套全绿。新增测试使用真正 F9 木桩几何（脚底+1m、radius=.6，按F11近战实际起点1.35m）及 W4 实际 motion/events。刀身特意指向身后/向下，逐帧断言旧刀身查询完全不相交；10/30/60FPS 三段各10、短重16/满重22，重复AfterPose不加伤。另覆盖墙挡、扇角/径向/高度擦边、reach只乘一次、胶囊两端都在外但中段穿区、最近弱点元数据、spin/slam重叠去重、角色移动/朝向快照/取消清理。

python3 validation/combat/melee-zone/lsp_check.py / PASS / /Users/xd/Desktop/体素test/validation/combat/melee-zone/lsp.log

5个Lua零Error。

git diff --check / PASS / /Users/xd/Desktop/体素test/validation/combat/melee-zone/diff-check.log

## 原生/Web 接下来复核

- 原场景F11：三段、短重、满重应出现真实 Dummy hit 与 Combat hit，新增combo_all_hit打印三段实伤。
- F9刚生成时在3m之外直接挥刀仍可能超出本次设计1.8m范围；F11已有近战阶段安全定位到1.35m，本轮没有扩大木桩/判定半径到3m来掩盖距离。
- 真实敌人的高度/多部位/贴墙情况与360°重击范围需体感验收；离线不等于原生引擎通过。
