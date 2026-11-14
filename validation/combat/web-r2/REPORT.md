# Combat Web R2 实测记录（部分完成，最终受页面空白阻塞）

时间：2026-11-14 04:13–04:34 +08:00。仅 Cindy external/CDP，同一 target 82A6CFAFF4DF3C2BCD316957A406C437；未启动本地游戏 Runtime，未改源码/提交/构建。
入口：https://maker.taptap.cn/app/f323832c-195d-4276-a841-0ceafd1f1cf1?localDev=1&hide_chat=1

## 版本和证据边界

- 开始本地 HEAD=9abae21d4e14f8e4f48f0043e829796ca61745db（baseline.log）。使用 Lead 指定新构建后导航；页面未提供可直接读取的 commit SHA，不能仅凭本地 HEAD 证明服务器运行 SHA。
- 浏览器控制台在04:14:32与04:17:29有两次场景 ready。第二次非本轮显式导航，原因未知。04:30 继续取证时游戏区白屏，浏览器仍 external/running；一次原 URL 恢复导航成功回执后仍白屏。没有对该白屏归因于战斗代码。
- 收尾 HEAD 已为 b2cb7a7491128903b5b2791eabac43797b8b54a9，另有 RuinsCloud.xml/RuinsCloud.shader/SkyAtmosphere.lua/SkyClouds.lua 未提交修改（final-workspace.log），均未触碰。服务器是否随之换版未知；本次不能把所有截图绝对绑定到9abae21。
- runtime watcher 同时收到其他运行会话内容，不能把其中不属于本页的敌人伤害/解谜日志充作本轮操作成功。以目标页浏览器控制台时间戳和图像为主。旧03:26报错排除。
- 原截图虽后缀 .webp，浏览器回执部分实际 MIME 为 JPEG；使用图片工具可直接读取。所有采用的图片均已查看，另有 review-contact.jpg 汇总。

## 结果

| 项目 | 结果 | 实际证据 / 限制 |
|---|---|---|
| 初次加载并进入场景 | PASS（当时） | spawn.webp；04:14/04:17 ready，后续白屏另列 |
| settings.json、weapons-v1.json 缺失报错消失 | PASS（本次启动范围） | browser-mid.json / startup-check.log 未见新报错；未清存档、不证明所有全新账号 |
| 旧 WeaponBuilder GetSystemTime Lua 异常 | PASS（未复现） | 本次开锻造未出现旧错误 |
| 锻造 3D 或 fallback 可见 | FAIL | forge-open.webp、forge-loaded.webp、forge-second-open.webp：中央预览持续空白；未捕获 Forge preview: 3d 或 fallback 日志；每次打开伴随下述 VoxelJobSystem 错误 |
| 选择剑部件/换主色→背上显示 | PASS | G→Sword→宽刃→主色金色→顶部关闭→C，forge-parts-colors.webp / forge-equipped-gold.webp 可见金色宽剑 |
| 锻造关闭按钮清理 | PASS | 顶部 Close 后正常回游戏并恢复输入 |
| Esc关闭、警戒拒绝/强制关锻造 | UNDETERMINED | 未完成，后续白屏阻塞 |
| C 进待机→安静6s脱战 | PASS | 04:19:21 EXPLORE->COMBAT_IDLE manual；04:19:27 COMBAT_IDLE->EXPLORE quiet |
| 探索/战斗手光互斥 | PASS（状态及有限画面） | 探索 requested=.28 brightness=.198；战斗 requested=0 brightness=0 motes=0；退出后亮度恢复爬升；艺术可读性仍交Lead |
| 战斗H文案、底部单提示槽 | PASS（所拍状态） | forge-equipped-gold.webp、anim-light-1.webp；骑龙H未测，不声明三态全部通过 |
| F9木桩与短蓄重击命中 | PASS | dummy-spawn.webp；04:21:09 Dummy hit: sword sword_heavy_release dmg=21.60 part=body；Combat hit poise=10.80 |
| 实战轻击三连、满蓄重击、闪避取消、顿帧时长 | UNDETERMINED | 原短点击在分次浏览器操作延迟下被识别成重击，不能当轻击通过；没有实际完成其余项目。dummy-combo.webp 名称不代表轻击三连 |
| 弓弱/中/满、取消、飞行与命中 | UNDETERMINED | F7姿势不等于实际发箭；未完成玩法输入 |
| F8三类敌人、预警、Boss/破甲、玩家死亡 | UNDETERMINED | 未完成，不能借用混流 runtime 日志 |
| F7暂停和逐帧截图 | PASS（已拍片段） | 逗号回退1/30s、暂停帧在后续截图维持同一t；有效帧见下表 |
| 当前页面可继续验收 | FAIL（加载状态） | resume-current.webp、resume-after-navigation.webp：游戏iframe区域空白；恢复后控制台没有新的游戏记录。具体原因未知 |
| 触屏多指/TouchCancel | UNDETERMINED | 桌面可信键鼠不替代真机触摸，未合成DOM事件 |

### 新引擎错误原文

04:15:27.327、04:18:18.054（+08:00），均紧随本轮 G 开锻造：

> ERROR: VoxelJobSystem: foreign WorkQueue work in flight at physics step start. The engine-wide pulse convention is violated; physics parallelism will degrade. Find the system leaving cross-frame WorkItems and reconcile it with the physics step.

证据 browser-mid.json、browser-combo-actual-events.log。时间关联明确，尚不能从日志证明具体哪个系统遗留WorkItems。另有 HiddenVoxel 的 POSITION/deferred-pass 警告；本次未捕获新的战斗Lua栈异常或shader编译失败，不声称所有资源绝无错误。

## F7 有效截图与语义判断

| 片段 | 文件 | 画面时间/阶段 | 判断 |
|---|---|---|---|
| sword_light_1 | anim-light-1.webp | .166 active | 剑路大部分被后背遮住；无法确证右→左是否反了 |
| sword_light_2 | anim-light-2-active.webp | .144 active | 剑较竖直贴右肩，斜撩读感弱；作为复核候选，未证明轴向反转 |
| sword_light_3 | anim-light-3-active.webp | .167 active，hit_on | 身体前压可见，剑/双手部分遮挡；下劈落点需侧视复核 |
| sword_heavy_release | anim-heavy-active-corrected.webp | .253 active | 角色已旋转朝镜头，符合回旋语义；单帧不能确认整圈路径或穿模 |
| swap sword→bow | anim-swap-sword-bow-boundary.webp | .200 recovery，weapon_stowed/cancel_open | 仅边界帧，非active；手与背负交接需动态确认 |
| swap bow→sword | anim-swap-bow-sword.webp | .235 recovery | 未获得active；不判通过 |
| bow_hold | anim-bow-hold-active.webp | .400 recovery（目录默认phase） | 左弓/右臂分工可见，缺正侧面，弦与右手贴合未确认；文件名active不代表画面阶段 |
| bow_release | anim-bow-release.webp | .200 recovery | 仅收招，不能证明射出/回弹；anim-bow-release-early.webp 已是空白页，不采用 |
| dodge_roll | anim-dodge-active.webp | .428 recovery | 不是翻滚active，待补 |
| hit_light / hit_heavy / death / getup | 无 | 未验证 | 白屏中断前尚未拍到 |

对照设计§13.3，当前没有足够证据列“确定轴向明显反了”的片段；轻2剑贴肩、轻3剑路被遮挡、弓手弦关系列为需要更近侧视的候选，不能把看不清当作合格。F7不模拟伤害和物理验收。

大白块团与上方棕色弧在手光=0时仍可见（forge-equipped-gold.webp及动作图），因此不能归为本轮隔离的handGlow池；具体归属未证明，未改其他任务文件。

## 操作与收尾

- 浏览器真实CDP键鼠；坐标按2297×1129 CSS视口。UI点击先 mouseMoved 再 pressed/released；早期未移动鼠标的误选不作为UI命中错误。
- G开面板→选择宽剑/金色→顶部Close→C待机；F9木桩；W靠近，按住/松开左键实际触发短蓄重击；F7→方向键选片段→Space暂停→逗号/句号微调截图。
- 04:30发现白屏后仅做状态/快照/截图、一次原URL导航恢复；未反复重建或切换模式。最后CDP释放W/A/S/D/Shift/Space、左右鼠标成功回执。旧F7/木桩内存随重载已不能观察；不再盲发切换键。
- operations.json 保留脱敏操作回执；browser-*-events.log 为关键事件摘录；browser-after-recovery.json 无新的可用游戏记录。
- 本轮只新增 validation/combat/web-r2 证据。最终git diff --check通过；已有他方4文件修改保留。未做额外离线测试冒充本次Web结果。

## 建议Lead下一步

先由W1/引擎侧核查 Forge 预览空白及 WorkQueue 错误，确认正在服务的预览版本和页面能稳定加载，再继续未测实战与F7侧视。需Lead美术审阅最有用图：forge-equipped-gold.webp、anim-light-2-active.webp、anim-light-3-active.webp、anim-heavy-active-corrected.webp、review-contact.jpg。无需额外新素材才能推进；目前主要是预览运行稳定性与取证视角。

