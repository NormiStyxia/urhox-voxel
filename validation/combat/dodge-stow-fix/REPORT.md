# 近战零伤害与 F7 遮挡修复（待 Web）

基线 HEAD `a99b8c2b7084e201d24f5637375fb93a7f07a087`，2026-11-15。只做离线修复与验证，未提交、拉取、构建、刷新 Web 或启动本地游戏 Runtime。上一轮真实 Web 的 **12 PASS / 6 FAIL** 保留，本轮离线通过不等于 Web 通过。

## 根因与链路证据

- **不是 F11 夹具身体/镜头反向。** `RuinsScene.lua:1025` 的 `StartCombatTest.prepare` 按身体 forward 摆放，再调用 `NomiController.lua:275` 的 `TeleportForCombatDebug`；后者同时设置 yaw/camYaw。提取实际两段代码运行的回归证明，初始相反朝向会在 prepare 中对齐。弓另有 synthetic aim，不能证明近战方向正确。F11 夹具未修改。
- **生产近战区域坐标写丢。** `CombatMoves.MeleeZone` 原写 `out.origin.x/y/z`、`out.source.x/y/z`。`lua-scripting-guide.md:341` 明确 Vector3 是原生值类型，table 字段读取及参数传递复制值，必须整体写回。缓存区域一直停留在世界原点，场景非原点时 StrikeZones → Hit.QueryZone 无候选，尚未进入 LOS 或 Hit.Apply；影响正常攻击和 F11。旧测试普通 Lua table 可原地修改，遮蔽此缺陷。
- 基线模块通过只读 git show 载入，在模拟文档值语义的 proxy 边界下重放实际 Action→动画事件→StrikeZones→QueryZone→Visible→Apply。旧代码失败：`normal/fixture=false yaw=0 opposite=false wall=false stage=1 damage=nil origin=(0.0,0.0,0.0)`。可复现脚本 `reproduce_baseline.py`，日志 `repro-baseline.log`；无需改工作区源码即可重放。
- 修后 5 yaw × 同/反朝向 × 正常/F11 × 有/无墙，共 40 组通过。三段各 10，短/满重击 16+22，每段一次；墙前拒绝，dead/inactive/过远/过高候选拒绝。正常攻击保持意图快照转身；未扩大扇形、删除墙过滤或放松伤害断言。真实 GridHit/引擎碰撞仍待 Web 独立验收，离线墙函数不是原生碰撞证明。
- 同源范围提示还有值传递问题：CombatHUD.UpdateRange 原未接回 ZoneBoundary 返回值。现在整体写回 point.world，新回归执行实际 UpdateRange 检查非原点投影，不仅测试 helper。

## 修改范围

| 文件 | 行段与修改 |
|---|---|
| scripts/combat/CombatMoves.lua | 690–700：origin/source 整体写回；719–720：说明 ZoneBoundary 返回值合同 |
| scripts/ui/CombatHUD.lua | 23：接回范围点；139：只读 Preview() |
| scripts/ruins/RuinsScene.lua | 1159–1160：F7 提前拦截解谜快捷键并清蓄力；1258：退出等待旧按键释放；1654：同步 hud.preview |
| scripts/ruins/RuinsHUD.lua | 152、178、185、197、212、224：仅 PC F7 隐藏底部按钮、Pointer/操作提示、消息卷轴和帮助；保留原状态 |
| tests/combat/core_zone_values.lua | 新增值语义边界、40 矩阵、实际 F11 prepare/AssistMelee、候选/墙/去重、实际 HUD 世界投影 |
| tests/combat/core_preview_route.lua | 新增实际 F7 enter/exit、数字/E/Q 独占、退出释放门、正常键盘/触屏解谜恢复 |
| tests/combat/core_routing.lua | 注入预览状态，原路由断言保持 |
| tests/combat/core_free_facing.lua | 两处范围采样接回返回值 |
| tests/combat/core_ui_alloc.lua | 真实 HUD Render 验证 PC 隐藏/退出恢复，触屏不受影响 |

接口只新增 CombatHUD.Preview() 和 Scene HUD 数据 preview 布尔值；ZoneBoundary 原有返回值现在正确消费。无 W1/W4 新接口需求。任务 diff：review.diff；人工逐段复核：review.log。

## 验证

- python3 validation/combat/dodge-stow-fix/reproduce_baseline.py / PASS（准确捕获预期旧版失败） / /Users/xd/Desktop/体素test/validation/combat/dodge-stow-fix/repro-baseline.log
- python3 validation/combat/juice/run_tests.py / PASS（35/35，原 33 + 新增 2） / /Users/xd/Desktop/体素test/validation/combat/dodge-stow-fix/tests.log
- python3 validation/combat/dodge-stow-fix/allocation.py / PASS / /Users/xd/Desktop/体素test/validation/combat/dodge-stow-fix/allocation.log
- python3 validation/combat/dodge-stow-fix/lsp_check.py / PASS（18 文件，0 Error） / /Users/xd/Desktop/体素test/validation/combat/dodge-stow-fix/lsp.log
- git diff --check / PASS / /Users/xd/Desktop/体素test/validation/combat/dodge-stow-fix/diff-check.log
- 人工 review 任务差异 / PASS / /Users/xd/Desktop/体素test/validation/combat/dodge-stow-fix/review.log

600 帧停 GC 模拟绘制每帧增长：PC 0.152 KB、touch 0.191 KB、Boss 0.488 KB、range 0.191 KB，均 ≤2KB。仅 Lua 模拟分配指标，不是 Web 原生内存或帧率证明。

## 保留合同、共享冲突与未验项

保持浮背/收招宽限/连续攻击、武器切换消隐、滑步时间与位移/无敌、弓缩放与 release/cancel p/pitch、子系统隔离、静态 Time 绑定、分帧音频和无切换建池。未改 WeaponRig/AnimClips/CombatAnim、NomiController 或 DragonStream。无新增逐帧日志。

共享文件冲突：本轮 Scene/HUD 未检测到他人同时修改；并行云 shader、density/sculpted atlas、validation/sky-fx 变更与未跟踪目录完整保留，不包含在任务 diff，不回退。

待 Lead 官方构建后真实 Web：F11 六项伤害失败是否消除；普通玩家在不同身体/镜头朝向、非原点与真实墙前的命中/不命中；三连与重击接触点及同源范围提示；F7 1/2/3/4 无时间之力提示、腰腿无遮挡、退出后键鼠/解谜恢复；触屏实际操作；原生帧率/分配。未打开或操作浏览器，不抢占并行云会话。
