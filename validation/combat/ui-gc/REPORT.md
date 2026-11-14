# W2 HUD 分配与 GC 节奏交付

基线 HEAD：feb055e6fbf3f46fa473b734e47a08326796422d。未提交、未推送、未构建，未运行本地或 Web 游戏。

## 本轮文件

运行代码：scripts/ui/CombatHUD.lua、PixelDraw.lua、TouchControls.lua、TouchInput.lua；scripts/ruins/RuinsHUD.lua、RuinsScene.lua。
新增回归：tests/combat/core_ui_alloc.lua、core_pixel_cache.lua、core_gc.lua。

## 600 帧同条件分配对比

使用 Lua 5.4（lupa.lua54），每个模式独立 VM；预热 20 帧，完整 GC 后暂停自动 GC，用 collectgarbage('count') 比较连续 600 帧。调用真实 CombatHUD.Set、RuinsHUD Layer.Update/Render、TouchControls.Update/Sync/Render、TouchInput.EndFrame。1280×720，DPR=1；加载真实 PNG 尺寸。UI/NanoVG 为离线 adapter，NVGcolor/NVGpaint 的返回对象用 Lua 表模拟；安全区 API 也按实际 UI 库模拟返回新表。测量不含 Yoga/UI.Render 本体、原生 userdata/C++ 分配、整场景 gameplay，不能与 Windows 原生 16KB 数字直接等同。

| 模式 | 优化前总增长 KB / 每帧 KB | 优化后总增长 KB / 每帧 KB | Fill 次数/帧（前后相同） |
|---|---:|---:|---:|
| PC 战斗 | 19687.771 / 32.813 | 89.250 / 0.149 | 63 |
| 触屏拉弓战斗 | 22517.246 / 37.529 | 112.875 / 0.188 | 73 |
| 触屏+普通敌人血条+Boss+破甲提示+伤害数字 | 33097.000 / 55.162 | 292.812 / 0.488 | 113 |

离线稳态三个模式均低于 2KB/帧；原生目标尚未验证。完整输出 alloc-compare.log；复现 python3 validation/combat/ui-gc/compare.py。修改前5文件快照在 before/，不是整个工作区备份。

## 审计清单（当前行号）

| 文件:行 | 原分配 | 处理 |
|---|---|---|
| PixelDraw.lua:32 | 每次 Metrics 新安全区表、重复 UI 安全区包装对象 | 复用只读视图，每引擎帧采一次；DPR/尺寸/scale变化立即失效 |
| PixelDraw.lua:78 | 每个 Rect/Text/Image 产生 NVGcolor、默认白/灰 RGB 表 | 白/灰常量；按 RGBA 数值缓存，调用方临时颜色表也能复用 |
| PixelDraw.lua:93 | 每个贴片/图标产生 NVGpaint | 每 context/image/源片/颜色缓存；源局部 paint + 保存/恢复平移；图片尺寸变化/Release失效 |
| PixelDraw.lua:133 | NineSlice 每次8个坐标数组 | 标量计算九宫位置，保留2×铺贴和末片裁切 |
| PixelDraw.lua:188 | Arc 每帧拼接缓存键 | 半径/内径/段数数字层级索引 |
| PixelDraw.lua:212 | 帧名/图标名拼接、冷却数字 tostring | 帧名常量；仅图标/尺寸变化重建；整数文本复用 |
| CombatHUD.lua:36 | 每帧默认空表、调试字符串分行、伤害数字/投影临时对象 | EMPTY、调试文本变化才拆行、伤害值变化才转文本；投影在Set阶段复用工作区 |
| CombatHUD.lua:78/98/110 | 准星符号数组、拉弓提示拼接、破甲拼接、Render内Vector3 | 数字步进循环、三条提示常量、部位标签缓存；Render只用已投影数值 |
| RuinsHUD.lua:11/27/147/253 | PC按钮数组、消息阶梯数组、目标布局表、每帧移动端gsub、H帮助数组 | 静态描述和布局缓冲；文本变化才转换；HelpLines只初始化一次 |
| RuinsHUD.lua:41 | 换行测量创建表/闭包 | 既有缓存命中路径无分配；只在文字/布局/字体可用性改变时重建，不删文字不改换行 |
| TouchControls.lua:13/49/193/215 | 每帧live触点表、帮助数组、数字文本 | live缓冲清键复用、帮助常量、数字缓存 |
| TouchInput.lua:52 | EndFrame每帧新pressed表 | 清键复用，不改边沿消费/取消逻辑 |
| RuinsScene.lua:421/619/1571 | 木桩合并敌人列表、每次provider状态表、每帧CombatHUD数据表 | 各自稳定缓冲并清理旧引用 |
| RuinsScene.lua:1092/1464 | 瞄准目标与时钟每帧格式化 | 目标身份/状态/权限/标题变化才重建；时钟分钟/阶段变化才调用ClockText；DayNight文件未动 |

没有将像素贴片拉伸成整张图；没有改资源、滤镜、字号、整数缩放或触摸命中。静态 source-paint 缓存已实施，但 **draw/fill 次数没有降低**。没有跨不同UV片强行合并；真正合批/整面板离屏缓存需要引擎支持并另测。新平移保存/恢复可能改变原生CPU成本，须 Windows 对比，不能只凭Lua堆数据判断总收益。

## GC 开关和取证

RuinsScene.lua:97–158：默认 M.gcEnabled=true、M.gcDebug=false。启动 collectgarbage('incremental',110,300)。BeginFrame记录墙钟；EndFrame若已超过12ms则跳过，否则只执行一次 collectgarbage('step',8)。禁用或Stop恢复之前pause/stepmul，不切 generational。

调试用 RUINS.SetGCEnabled(false/true)，RUINS.gcDebug=true/false；不占用键位或设置文件。日志每秒一行：RuinsGC: heapKB / deltaKB / steps / completed / skipped / stepReclaimedKB / maxStepCPUms。

completed是本模块手动step报告的完整周期数；maxStepCPUms仅是手动step的CPU时间，不冒充全引擎自动GC的最大耗时。step(8)是工作量提示，不是可抢占的硬时间上限；原生原子阶段仍需测量。

## 进战首帧审计

- Scene StartCombat 创建 CombatMoves（8槽HitEvent）、Projectile（12槽）；箭节点及4段尾迹在启动循环创建。
- Spawner 创建时 Acquire 共享64粒池；进战调用不重建。
- WeaponRig 初始化预建 sword/bow、trail、两套afterimages与visual pools。SetActive/SetPose不批量Build；锻造Apply变更部件才重建（归W1，本轮只读未改）。
- 进战/拔刃 Preload 保留幂等登记；启动第2秒预加载以及每帧真实dt推进保持。
- 不声称攻击命中/箭碰撞或F7逐帧诊断完全无分配；这些不属于本次稳态HUD指标。

## 验证

python3 validation/combat/ui-gc/compare.py / PASS（三模式600帧，均≤2KB/帧） / /Users/xd/Desktop/体素test/validation/combat/ui-gc/alloc-compare.log
python3 validation/combat/juice/run_tests.py / PASS（29套） / /Users/xd/Desktop/体素test/validation/combat/ui-gc/tests.log
python3 validation/combat/ui-gc/lsp_check.py / PASS（9文件零Error） / /Users/xd/Desktop/体素test/validation/combat/ui-gc/lsp.log
git diff --check / PASS / /Users/xd/Desktop/体素test/validation/combat/ui-gc/diff-check.log

自审重点：修正了按临时RGB表身份缓存会无限保留paint的问题，现按数值去重；图片重载/尺寸变化可失效；source-local UV、九宫矩形、平移栈与旧铺贴契约一致。GC重复EndFrame/无Begin/禁用/卸载均不step。原生屏幕效果和真正UI.Render/自动GC峰值全部未验证。

共享文件冲突点：Scene仍混有此前HandSocket和音频预加载补丁；本轮只追加GC与HUD provider/cache。NomiController、DragonStream、WeaponRig、CombatAudio、角色数据、天空/画质与未跟踪目录都未覆盖。已保留并行会话现状。
