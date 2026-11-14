# W2 战斗 Web R1 修复与取证入口

日期：2026-11-14。基线 HEAD：c59ac6c9810424bf1cb194e064f1739ddde1c0f1。当前为共享工作区未提交补丁；没有构建、刷新 Web 或启动本地游戏 Runtime。

## 改动与位置

- `scripts/combat/CombatState.lua:14–25`：状态变更日志与事件日志节流（同 key 至少间隔 .02s、全局最多 48 行/s）。状态仅变化时记录。
- `scripts/combat/CombatMoves.lua:27–216`：动作开始/结束、取消射击、命中、玩家受击/复活日志；木桩伤害数字持续 1.2s。
- `CombatMoves.lua:345–437`：独立木桩、真实敌人锚点安全传送采样、预览阶段/事件/回退采样、独立手光粒子更新。
- `scripts/combat/Projectile.lua:25–69`：箭 weak/mid/full 档位与发射速度日志，将档位/片段带入命中信息。此文件还保留此前已汇报的晶爆倍率修复：实际命中伤害 × crystalDamageMultiplier，不再使用旧固定 crystalDamage。
- `scripts/ui/CombatHUD.lua:16–25,79–91`：底部提示只输出给 RuinsHUD；木桩数字时长；12px 多行调试信息。
- `scripts/ruins/RuinsHUD.lua:177–193,209–245`：单一底部槽优先战斗/蓄力/取消，再目标，最后 Pointer；H 帮助按战斗/骑龙/探索分流。UI Inspector 从 F9 改为 F4（调用公开 Init 配置，无库改动）。
- `scripts/ui/TouchControls.lua:327–330`：触屏模拟由 F9 改成 Shift+F9，普通 F9 交给木桩。
- `scripts/ruins/NomiController.lua:241–254`：仅新增 TeleportForCombatDebug；再次校验安全地面、清速度、设置可靠安全点、立即同步视角。其余地形/相机/瞄准与虚空逻辑不改。
- `scripts/ruins/RuinsScene.lua`：48–51 调试状态；335–342 木桩追加到战斗查询副本（不写 Spawner）；437 箭日志；549/571–576 手光独立池与进战清除；764–828 F8/F9 实现；994–1045 F7/F8/F9 输入与逐帧时钟；1058 木桩回满；1148–1159 手光状态/日志；1213–1218 调试 HUD 与手粒绘制；1230–1232 清理。
- 本轮测试改动：`tests/combat/core_moves.lua`、`core_touch.lua`、`core_routing.lua`、`core_motion.lua`、`core_state.lua`。`core_projectile.lua` 的晶爆回归是此前已交付但仍未提交的改动。没有新运行时资源或 Lua 文件，不需要新 .meta。

## 调试操作

仅 PC、非菜单、未死亡、未骑龙且游戏持有输入时接受 F8/F9。

1. F8 依次苔壳虫组 → 哨灵 → 石甲兽；根据 Spawner 真实 home/position，分别从 7m/14m 圈向外采样，地形安全、2m 承托余量、远离敌人、三高度建筑网格穿线检查均通过才传送。找不到则提示并不移动。清蓄力/箭/触点/速度，等输入释放再行动，短保护 1s；左上显示“传送：目标”。F7 预览中拒绝 F8。
2. F9 在人物正前方 3m 的安全空地生成/移除棕色盒木桩；没有 AI、物理体或正式 Spawner 注册。伤害球体、9999 HP，每帧回满，不死亡；每次有效命中打印 `Dummy hit: sword|bow clip|tier dmg=... part=body`，强制显示伤害数字 1.2s。
3. F7 进入/循环片段，左右/中括号切片段，空格暂停，逗号/句号每次后退/前进 1/30 秒。显示片段、秒数、anticipation/active/recovery、该步事件。回退重建隔离的预览动画并排空事件，不发射箭、不造成命中。暂停和失焦每帧显式 Update(0,0)，避免 Apply 跟随人物基础时钟偷偷推进。
4. 快捷键冲突已拆开：F9 木桩、Shift+F9 触屏模拟、F4 UI Inspector。库本身的初始化日志可能仍印旧 F9 文案，其实际热键来自配置 F4；库未改。

## 手光与白色方块排查

- 探索闲置手光请求值由 .12 提到 .28；施法亮度保留。战斗态请求值、平滑值、灯亮度与专属手粒数量均立即为零。
- 增加 32 槽手粒池，仍是 .06m 小四边形、寿命 .4s、位置在手边约 .16–.28m 范围。原 TimeFX 共用池中的冻结/回溯效果继续更新；TimeSpells.lua、VoxelFX.lua 未修改。
- 新运行可读 `M.combat.handEffect={requested,glow,brightness,particles}`，状态开关打印 `Combat: hand glow state=... requested=... brightness=... motes=...`。这是待 Web 确认出口，当前没有新的实际运行日志。
- 静态检查：EnemyParticles.Acquire 的 64 个体素槽在原点创建，但 active=false、节点 enabled=false；Emit 才按命中位置启用。Scene 箭节点仅 draw 回调首次发射创建；TimeFX 的 6 条 Beam 初始化隐藏、手粒池初始化隐藏；新手粒也没有原点发射。
- 因此没有发现“本轮战斗粒子在初始化可见的大白块”证据。旧 Web 图中大白方块团的真实来源仍 **UNDETERMINED**，不能仅靠排除法认定是云层。没有改 SkyClouds、SkyAtmosphere、云/光/地形 shader 或其他会话文件；需要下一次 Web 同机位观察并结合节点/粒子计数确认。

## 静态结果

Lua54 combat 19 suites / PASS / /Users/xd/Desktop/体素test/validation/combat/w2/r1-fix-offline.log

Lua54 loadfile 14 files / PASS / /Users/xd/Desktop/体素test/validation/combat/w2/r1-fix-syntax.log

maker-lua-lsp settled 14 files（零 Error） / PASS / /Users/xd/Desktop/体素test/validation/combat/w2/r1-fix-lsp-current.log

git diff --check / PASS / /Users/xd/Desktop/体素test/validation/combat/w2/r1-fix-diff-check.log

git scoped diff review / PASS / /Users/xd/Desktop/体素test/validation/combat/w2/r1-fix-review.log

19 套含 core 7、anim 1、enemy 5、weapon 6；新增真实 Scene F7 分支回归、无效安全点拒绝、调试传送清速度/相机、木桩回满/数字时长、提示槽优先级、F9 键分离、手光即时清除、日志限频。探索碎时/冻结/回溯、骑龙 breath/special、菜单/模式取消保持现有离线回归。所有离线测试均不是引擎或画面验收。

## 共享文件与待 Web

Scene/Nomi/HUD 为共享接线位置，按当前文件局部插入；没有回退 VoidRewind/GameSettings/DebugLog、龙碰撞、云层等已有逻辑。工作区还有 W1 的 WeaponBuilder/ForgePanel、龙碰撞、云层/地面 shader、回溯图片、文档/测试等其他人的未提交修改，完整状态见 baseline/review 日志；这些不属于本轮 W2 修改。

可交 Lead 协调 Web 预览，当前画面/手感全部 **未验证**。建议顺序：开场查看手光与日志 → C/F9 三连和重击命中数字/顿帧 → Q 拉弓三档与取消（按日志判断是否射击） → F7 暂停逐帧停 active 拍轴向 → F8 三处接敌/血条/预警 → G 检查 W1 锻造修复 → 探索/骑龙/战斗三种 H 文案、底部提示不叠 → 静置脱战恢复手光。手机真实多指与 TouchCancel 仍需设备验收。
