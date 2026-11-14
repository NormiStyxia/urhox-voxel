# PC 战斗可测性补强（2026-11-14）

已完成代码与离线检查；未启动 Runtime，未构建、提交或操作 Web。基线 5023270；保留前轮成功滑步入口 SetTrail(false) 补丁。

## 操作

- F7 原有选片/暂停/逐帧不变。dodge_slide：I 前、K 后、J 左、L 右，B 切剑/弓；bow_hold：+/− 每次调整 p=0.1（含数字键盘）。暂停时立即重采样当前时刻，左上显示方向/武器/p。
- 站在安全空地、无警戒、退出 F7，按 F11。自动生成缺少的木桩，逐步执行三连、短/满重击、四向滑步、.22 取消、攻击→滑步→攻击、三档箭及弃箭。仅在步骤间安全定位与切装备；每步 .35 秒中性输入落稳，所有动作走 CombatMoves.Update、真实动画事件、实际武器/箭命中链。
- 任一非 F11 键中止，并继续传递原按键；失焦/菜单/警戒/死亡/卸载中止。每步及退出清输入/弹体；只删除本次自动生成的木桩，保留已有木桩，恢复原武器与安全点。完整结束回到起点；外部中止不把玩家强行传走。
- 每步打印 CombatTest:，含 PASS/FAIL 与数值；没有命中不通过，不直接调用 ApplyHit 伪造结果。单步超时 4.5 秒失败。F11 合成瞄准对准木桩中心，仍由抛物线、扫掠和墙体阻挡决定是否击中。

## 测量边界

- controller_distance 来自两次实际玩家位置，不是 root motion 指令相加；.22 边界在下一物理步后取样，再排除后续攻击前冲。
- hit_on 同时列片段事件 action_t 与按帧观测 elapsed；前者是事件时间，后者受采样帧边界影响，不把事件预设称为实测帧时间。
- iframe_observed 取真实推进的滑步动画时钟，CD 取实际倒计时归零时刻；没有通过敌人攻击再次验证无敌拦截（仍待 Web）。滑步位移误差门限 .08m，CD/无敌允许两帧采样误差，打印 max_dt；.22 衔接还要求第三方动作实际成功开始，连段衔接要求下一段为 light_2。
- 箭速读取实际发射池实例速度，命中伤害读取结算反馈。晶簇记录实际结算后的 burst 数值；单木桩无次级目标，晶爆二次目标伤害明确 UNVERIFIED，未虚报覆盖。
- 空间不足、遮挡、武器轴向/姿态导致打不到、帧率低导致拉弓档位跨越，都应真实 FAIL，不能为过测试挪大 hurtShapes 或绕过碰撞。
- Scene 未发现 pcall/xpcall 或 Error 事件订阅；没有证据将 Web 左下错误计数归因于本文件，因此未添加无依据的错误捕获。

## 文件归属

本轮：scripts/combat/CombatTest.lua（新增）及官方生成 .meta；CombatMoves.lua（观察钩子、预览参数）；Projectile.lua（保留 Fire 布尔第一返回，增加实际池槽第二返回）；scripts/ruins/RuinsScene.lua（PC 入口、清理、预览）；tests/combat/core_selftest.lua、core_moves.lua、core_routing.lua。
共享文件 Scene 仅局部钩子；原有 VoidRewind/GameSettings/天空/龙接线未改。工作区 WeaponBuilder.lua、ForgePanel.lua、weapon_* 测试由 W1 修改，未触碰。其他 art/validation 未跟踪目录保留。

## 检查

- python3 validation/combat/juice/run_tests.py / PASS / /Users/xd/Desktop/体素test/validation/combat/selftest/tests.log（23 套，新增真实模块离线 30/60 FPS 合成输入驱动、缺命中失败、幂等清理、中止不吞键、F7 参数）。
- python3 validation/combat/selftest/lsp_check.py / PASS / /Users/xd/Desktop/体素test/validation/combat/selftest/lsp.log（7 个 Lua，零 Error）。
- git diff --check / PASS / /Users/xd/Desktop/体素test/validation/combat/selftest/diff-check.log。

离线模拟不是 Web 物理/视觉通过。下一次官方构建后先在南门外安全直路 F11 收日志，再在 F7 暂停滑步片段切四向及 B、bow_hold 调 p 看姿态。
