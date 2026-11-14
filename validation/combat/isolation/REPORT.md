# W2 战斗子系统隔离与切武器事件计时

基线 b0e54e4d8da754c136476817088dc8bc584fb8de。未提交/推送/构建，未启动 Runtime 或 Web。未改 DragonStream；保留 Lead 的预热关闭及保护。

## 改动

- CombatState.lua：独立故障隔离（Isolated）。每个固定子系统键单独 pcall，失败冷却 3 秒；该子系统最多每 5 秒一条 Isolated error: <subsystem> <msg>。不同错误也共用该子系统限频，避免交替错误刷屏。启动重置，3 秒后可恢复。成功路径不造表/闭包；计时读取自身也保护，错误对象 tostring 失败也不会让隔离器崩溃。
- RuinsScene.lua：F7动作/F7信息栏、F8/F9/F11、Moves/AfterPose、Animation Base/Params/Apply、Rig视觉准备/Update、Audio Listener/Update/Play/Stop、敌人/箭/粒子更新、Base/Combat Camera、HUD更新、GC等独立调用。移动逻辑异常时清零本帧位移与命中/无敌窗口，防止暂停期重复旧前冲；F7失败仅退出当次预览，冷却期不再反复取消正常战斗。F11输入失败中止自测。龙骑乘/姿势/普通呼吸入口、昼夜/天空/谜题调用也在Scene入口保护，未修改其实现。
- Audio port：播放/停止失败不传播进伤害或箭结算，仍允许冷播放nil且不补播。
- RuinsHUD/TouchControls 的 Render 分别保护；PixelDraw记录本模块Save/Restore深度，异常后只回收自身NanoVG状态栈，不误弹父UI保存状态。Render错误不阻断另一个控件。HUD更新失败可保留上次显示，等待冷却恢复。
- GC保护覆盖手动step和整段EndFrame逻辑；性能日志flush另一个保护段，不与GC共用失败状态。

只隔离Lua异常，不能捕获原生崩溃、硬死锁，也不能事务回滚一个抛错前已创建的原生对象。冷却降低重复分配频率，不宣称代替 DragonStream 中已修好的泄漏根因。

## 切武器计时

默认关闭。调试开启：RUINS.combat.state.swapPerf = true；关闭设为false。无需改设置模块，不占键位。

事件日志：Perf: weaponSwap total=.. rigSetActive=.. animPlay=.. hudRebuild=.. audio=.. ms window=600 hudSample=true accepted=true clock=system

- total：本次同步Swap动作入口耗时；不是600ms窗口总帧时。
- rigSetActive：包含 SetWeapon、Cancel暂存/恢复及片段事件实际SetActive调用；没有把第二次切换藏掉。
- animPlay：窗口内启动片段调用耗时。
- hudRebuild：切换后第一次实际HUD Render（含缓存失效/绘制）耗时；不是专门拆出的Yoga rebuild。未绘制则hudSample=false，避免把缺测当0耗时通过。
- audio：同一600ms窗口内战斗音频事件调用耗时（不是逐帧Audio.Update，也不是最终声卡延迟）。
- 600ms用于收齐异步片段/HUD/音频调用，下一次切换会先flush上一事件；不逐帧打印。窗口内紧接着执行其他战斗动作也可能计入animPlay/audio，应在Windows先单独连续Q复测。
- 优先Time.GetSystemTime毫秒墙钟；API不可用/抛错则CPU时钟降级，日志clock=cpu-fallback明确区分；不使用帧内不变的GetElapsedTime做耗时。

审计未找到SetActive/SetPose调用Build或建池。现有切换流程先设置目标武器，再暂回旧武器播放交接片段，最终事件提交目标武器；本轮保留动作语义，不擅自优化为瞬间可见性切换。新增测试执行真实Moves→State→Rig的50次双向切换，Builder.Build/Compile被设为抛错哨兵，原生volume/grid adapter统计created/writes/rebuilds均不增长。只证明离线调用路径无重建，80ms根因仍待Windows事件日志定位。

## 验证与证据

python3 validation/combat/juice/run_tests.py / PASS（31套，含其他worker当前交付） / /Users/xd/Desktop/体素test/validation/combat/isolation/tests.log
python3 validation/combat/isolation/lsp_check.py / PASS（12文件零Error） / /Users/xd/Desktop/体素test/validation/combat/isolation/lsp.log
python3 validation/combat/ui-gc/compare.py / PASS（隔离后稳态PC0.152、触屏0.191、Boss0.488 KB/帧） / /Users/xd/Desktop/体素test/validation/combat/isolation/alloc.log
git diff --check / PASS / /Users/xd/Desktop/体素test/validation/combat/isolation/diff-check.log

core_isolation执行实际Scene动画尾链/PostUpdate代码，注入动画、Rig、相机、法阵异常，验证同帧HUD/命中/各motes继续；检验冷却/限频/恢复/计时降级与事件日志。core_pixel_cache加嵌套NVG保存失败恢复父状态；core_swap_pool执行50次真实切换链。原有core_camera/core_routing/core_gc只调整被抽取代码边界与Safe依赖，不放宽原行为断言。

早期全量中 W1 weapon_forge 随并行修订曾失败；未修改其实现或测试，最终当前快照31套全绿。

## 文件与共享边界

本轮运行文件：scripts/combat/CombatState.lua、CombatMoves.lua；scripts/ruins/RuinsScene.lua、RuinsHUD.lua；scripts/ui/PixelDraw.lua、TouchControls.lua。
本轮测试：core_isolation.lua、core_swap_pool.lua（新增）；core_camera.lua、core_gc.lua、core_routing.lua、core_pixel_cache.lua（更新）。
共享Scene主要是抽取原有更新段成命名函数并在调用处隔离，避免每帧生成闭包；原Gameplay/动画→Rig顺序保留。未改 W1 的 WeaponRig/ForgePanel/weapon_*测试、DragonStream、NomiController、角色、天空/设置文件和其他未跟踪目录。

Web/Windows原生效果、故障恢复后的视觉/操作感、真实切换尖峰和pcall成本：未验证。
