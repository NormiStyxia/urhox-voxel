# 战斗 Web R3 实测报告

日期：2026-11-14（Asia/Shanghai），约 05:26–05:49。结论：**部分通过，整体 UNDETERMINED，不能作完整战斗验收通过**。

## 环境与证据边界

- 本地 HEAD 前后均为 5023270efac1a93d004dd1ef25bb4d2d1f6ab32b，未改项目代码，未构建/提交，未启动本地 Runtime。最终 tracked diff 为空；他方未跟踪目录保留。
- Cindy 专用 external Chrome，同一 island-void-review / targetId 82A6CFAFF4DF3C2BCD316957A406C437；2297×1129 CSS，WebGPU，高画质。
- 使用原 Maker 页面重新导航两次：第一次 05:26 开始，05:27 场景可见；第二次 05:43 为隔离敌人干扰回出生点，05:44 场景可见。第二次曾停在加载 81%，最终正常启动，未认作白屏。
- 页面未暴露可核验的 commit SHA。本地 HEAD + Lead 官方构建回执 + 页面新 dodge_slide / Forge fallback 特征相互支持，但不以 HEAD 单独证明网页精确版本。
- 全部截图已实际查看。*.jpg 文件部分实际为 WebP（浏览器返回原字节），常规图片查看器可打开。
- 所有时间与事件详见 events.log；完整控制台 final-console.json；Web watcher 副本 runtime-sanitized.jsonl；操作回执 operations.json。登录参数已脱敏。

## 1. 首屏、报错、音频加载

**PASS（限定范围）**：两次场景启动；在收集到的控制台与 Web watcher 日志中，ERROR / attempt to / stack traceback、Could not open file、VoxelJobSystem foreign WorkQueue、CombatAudio failed/error/degrad 均未匹配。未再捕获 settings.json / weapons-v1.json 缺文件错误。不是全局无错证明。

**FAIL（干净渲染日志验收）**：两次均有下列告警，UUID 对应 assets/Shaders/BLGL/HiddenVoxel.shader.meta，归属渲染/隐藏体素材质，非已定位的 CombatAudio 错误：

> SurfaceShader .../HQ-5qfZwSR37r_zXuUDQ01dw-668d00f6.shader: Warning: opaque material has no deferred pass because of: POSITION. Use a forward render path or remove these features. Deferred rendering has no automatic forward fallback; depth-only coverage may remain.

另有 Graphics::SetMode 0x0、Could not get application preferences directory、DownloadManager no resources resolved、ScriptProcessorNode deprecated 等告警，原文见 error-scan.log / final-console.json。

**未定位异常**：页面左下“修复错误”计数第一场从 1 增至 6，第二场至 5；工具控制台和 watcher 未返回对应异常堆栈。不能把计数直接归因战斗 Lua，也不能据日志零匹配宣布全绿。点击过一次该按钮仅得到复制提示，未获取到具体内容；随后停止此路径。需 Lead/平台侧核对页面汇总错误来源。

**可见视觉问题**：出生与交战上方均有大块纯白方片团，后续有大型暗色几何经过镜头；明显遮挡画面。见 startup.jpg、dummy-bow-aim.jpg、anim-swaps-active-2.jpg。本轮未确认其节点/模块来源，不能归因命中池或云层；未改任何源文件。

## 2. 锻造

- **PASS**：G 打开；05:28:08 日志 Forge preview: fallback (mesh)。真实显示武器剪影/部件拆解图，非空白。选择直刃和蓝色后，预览与背上武器有变化；Esc 关闭面板无残留。
- **未验证**：3D 路径未启用（实际走 fallback）；不存在“3d 通过”的证据。警戒时按 G 未出现面板，但当时本就在战斗态，不能证明“探索态面板遭警戒自动关闭”完整链路。
- 本次打开与操作未捕获 foreign WorkQueue。
- 证据：forge-open.jpg、forge-colors.jpg、forge-blue-close.jpg、forge-blue-close-2.jpg、blue-equipped-dummy.jpg、forge-console.json。归属 W1 ForgePanel/Store/Rig；入口 W2。

## 3. 木桩、剑与滑步

- **PASS（命中结算）**：05:31:01.096，Dummy hit: sword heavy dmg=16.00 part=body；Combat hit training_dummy poise=10.80。短蓄重击命中一次。
- **PASS（触发，非整套连段）**：第二场轻击 sword_light_1、sword_light_2 start 实际记录；未取得完整 1→2→3 连段及三段分别命中的证据。
- **未验证**：满蓄重击伤害、精确顿帧。第二场确有约 2.4s charge→release，但没有该次命中或满蓄事件日志，不能与短蓄伤害作对比。
- **PASS（触发，非参数验收）**：A/D/W/S + Shift 分别触发 dodge_slide start 与 dodge_start/dodge_land 接口日志，截图见 full-charge-slide-left-2.jpg、slide-right-forward.jpg、slide-right-forward-2.jpg、slide-back.jpg。
- **未验证**：2.2m 距离、0.20s 无敌、0.50s CD、边缘截断、精准奖励、攻击→滑步→攻击无缝衔接；没有坐标/来招窗口的可信观测。截图期间方向键仍可能带来普通行走，不能按总位移推算滑步距离。
- **未验证**：剑/弓留影和尘土短窗口。截图发生在动作之后，不将“没拍到”判为“没生成”。
- 输入限制：单步工具调用有明显延迟，最初 80–150ms wait 的短点击被实际拉长为重击/满蓄；后来同一 CDP commands 中 down/up 才触发轻击。所有结论按实际 Combat 日志，而非请求的等待值。
- 归属 W2 Moves/Hit/Controller，W4 片段；留影 W1。

## 4. 弓

- **PASS**：满蓄持有提示、松手 fire tier=full speed=44.00；05:46:37.656 及 05:47:02/04 三次 Dummy hit: bow full dmg=14.40 part=body，poise=4.00。画面显示木桩血条与伤害数字。
- **PASS（本次取消）**：05:37:10.603 Combat: arrow cancel dodge；画面“已取消拉弓”，这一取消操作没有紧接着出现 fire。
- **未验证**：弱/中档（尝试仍因输入延迟成为 full）；飞行尾迹、贴部位插箭的可见形态（44m/s、近距离命中在截图前完成）；满蓄穿透与晶爆。
- 证据：bow-hold-fire.jpg、bowcancel-beetle-forge.jpg、dummy-bow-aim.jpg / -2.jpg、dummy-arrow-tiers.jpg；对应 *-console.json。归属 W2 Projectile/Moves，箭造型 W1。

## 5. 三类敌人

- **PASS**：F8 到苔壳虫组、哨灵、石甲兽安全边缘，三种模型实际可见；进一步走近石甲兽后顶部 Boss 窄条出现。
- **PASS（基本链路）**：受到 9/10/18/20/22 等伤害，像素心条减少；05:37:29 hp=0→death，05:37:30 respawn hp=100→getup；后续 Boss 区亦再次死亡/复活。不能由此证明所有复活落点攻击清除或保护时长。
- **未验证**：完整前摇预警圈时间、接触点粒子喷出方向、部位破甲、敌人倒地不压扁、敌人死亡解体、Boss 半血狂暴；实际输入被敌人连续受击打断，没有打到目标状态。不得拿玩家 death 代替敌人死亡验收。
- 证据：bowcancel-beetle-forge-2.jpg / -3.jpg、enemies-three.jpg / -2.jpg / -3.jpg、boss-and-preview.jpg / -2.jpg、enemies-console.json。归属 W3 敌人；玩家 HP/复活 W2。

## 6–8. 音效、闪光、镜头

- **音频 UNDETERMINED**：点击画布后继续操作；未捕获 CombatAudio 失败/降级日志，存在 dodge_start/dodge_land 接口日志。这不是实际可听声音证据；本工具无有效听音观察，未验证播放、材质分层、响度或空间定位。归属 W5 资源播放 + W2 接线。
- **闪光/刀光 UNDETERMINED**：未可靠捕获 0.08s 拔收刃/满蓄闪光、连续刀光；F7 图中可见剑条，但不等价真实 hit_on 刀光验收。
- **镜头部分可见，整体 UNDETERMINED**：弓构图偏肩、Boss 近距离构图可见；未观察到可量化的累计漂移，不代表无漂移通过。大型前景几何/敌体遮挡角色下半身，影响动作判读。归属 W2 Camera + 待查场景特效。
- 探索手光恢复、战斗 brightness=0/motes=0 状态互斥 **PASS**；巨白方片团两态都在，不能拿它当手光互斥失败。
- 底部满蓄/取消/拔刃与 Pointer 在已拍画面只显示一个提示槽 **PASS（采样）**。战斗 H 文案已是攻击/重击/Shift/Q/C/脱战后锻造/F5/F6 等 **PASS**；本轮未骑龙，骑乘 H 未验证。

## 9. F7 动画图片

F7 暂停、逗号/句号逐帧、左右切片段实际可用。已取以下时间：

| 片段 | 实拍 t / HUD阶段 | 图片 |
|---|---|---|
| sword_light_1 | .166 active | anim-light-active.jpg |
| sword_light_2 | .132 active / hit_on | anim-light-active-2.jpg |
| sword_light_3 | .162 active / hit_on | anim-light3-heavy.jpg |
| sword_heavy_release | .263 active | anim-light3-heavy-2.jpg |
| dodge_slide | .126 active，默认后撤 | anim-slide-bow.jpg |
| bow_hold | .853，HUD为 recovery | anim-bowhold-release.jpg |
| bow_release | .029 / fire，HUD为 recovery | anim-bowhold-release-2.jpg |
| hit_light | .067，HUD为 recovery | anim-hit.jpg |
| hit_heavy | .100，HUD为 recovery | anim-hit-2.jpg |
| getup | .165，HUD为 recovery | anim-getup-death.jpg |
| death | .597，HUD为 recovery | anim-death-swap.jpg |
| weapon_swap_bow_to_sword | .193 active / weapon_stowed | anim-swaps-active.jpg |
| weapon_swap_sword_to_bow | 显示 .200 active / weapon_stowed,cancel_open（显示有舍入） | swap1-settings.jpg |

- **不能确认轴向反了的片段：暂无确证。** heavy_release 在 .263 面向镜头符合大回旋斩语义，不能直接判 yaw 错。其余受背面、小尺度和下半身遮挡限制，不能宣布“无穿模”。
- 弓看起来接近侧缘，不能从这张后视图确认右手是否贴弦/左手握把；需清晰侧视复核。
- death 可见身体下沉前伏，但 getup/death 腿部被前景敌体/草遮挡；无法判完整起身和腿部穿插。
- F7 当前只传片段 id，没提供四向 params 控件；仅拍默认后撤滑步。真实玩法四向触发另有日志，但不是四向暂停姿态。
- **调试标注缺口（W2/W4）**：bow_hold、hit_light/heavy、death、getup 等 HUD 都标 recovery，没有可选 active 区段；已拍动作代表时刻，不冒称 active。要便于美术验收，后续需清爽侧视机位/无遮挡，四向参数与状态类阶段标注。

## 10. 性能粗采样

- 第二场出生探索：31 FPS / 32.7ms（spawn-lights-fast.jpg）。
- 出生附近木桩/剑：29–30 FPS / 34.2–33.5ms（dummy-lights-close.jpg、spawn-lights-fast-2.jpg）。
- 木桩拉弓：33 FPS / 30.7ms（dummy-bow-aim.jpg）。
- 第一场 Boss 附近交战：31 FPS / 32.3ms（perf-combat-help.jpg）。
- F7 暂停时 38 FPS / 26.7ms **不是战斗样本**。
- 不同位置、昼夜、输入状态的少量读数，不是压测/同机位回归。多个敌人+木桩+箭同时负载未验证，不能宣称性能达标或回退。

## 收尾与优先复核

- 已退出 F7，移除 F9 木桩，关闭设置与锻造，恢复 perfHud 关闭、debugLog 仍关闭，释放 W/A/S/D/Shift/Space/Control/Alt 与左右鼠标。最终停在南门前探索态，截图 final-released-2.jpg；不再操作浏览器。
- 没有录音证据；手机多指/TouchCancel 全部未验证。
- 优先处理：页面错误汇总可读性与 HiddenVoxel 告警；定位遮画面的大白方片/大型暗几何；让动作审查在无遮挡侧视进行。完整弱/中箭、三连命中、滑步衔接/来招窗口仍需人工低延迟实测，不能凭离线结果补 PASS。

## 检查回执

- git rev-parse/status/diff --stat / PASS / /Users/xd/Desktop/体素test/validation/combat/web-r3/final-worktree.log
- python3 collect_evidence.py / PASS / /Users/xd/Desktop/体素test/validation/combat/web-r3/collection.log
- captured console/runtime error-pattern scan / PASS / /Users/xd/Desktop/体素test/validation/combat/web-r3/error-scan.log（仅指定错误模式零匹配，含渲染 warning，页面 badge 未定位）
- full Web combat acceptance / FAIL / /Users/xd/Desktop/体素test/validation/combat/web-r3/REPORT.md — 关键证据未覆盖，且存在未定位页面错误计数；行为总评保持 UNDETERMINED。

