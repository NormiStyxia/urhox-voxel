# §18 滑步逻辑交接（2026-11-14）

状态：核心逻辑与静态回归已完成；留影显示仍需 W1 补两个接口条件。没有启动本地 Runtime，没有构建/提交；Web 视觉、墙角碰撞手感、手机真实性能均未验证。

## 本轮8文件

- scripts/combat/CombatMoves.lua：SlideFootprint/ClipSlidePath（20–66），滑步接受/取消/方向快照/续段/奖励，Update分段推进到.22/.26；dust事件与2条留影池。
- scripts/combat/CombatState.lua:10：dodgeFov=false，保留GetSetting/SetSetting，无设置界面修改。
- scripts/ruins/NomiController.lua:158、177–218：已检查滑步位移不再走旧endpoint裁剪；真实物理表面射线+双方mask，控制器仍负责胶囊扫掠、不Teleport。避开昂贵的瞄准逐体积修复路径，不改GridHit。
- scripts/ruins/RuinsScene.lua:410–422：slideStart/slideMotion/dust注入；953–954：滑向和朝向分离，取消帧不叠普通走动；1114–1120：可选留影位姿端口；1214–1218：可选FOV+1.5，默认关。
- scripts/ui/TouchControls.lua:79：提示“翻滚”改“滑步”；原BeginTouch即Set→Press链已满足独立按下，不改布局/换组/取消规则。
- tests/combat/core_moves.lua、core_motion.lua、core_touch.lua：追加§18离线真实模块测试。

## 行为

真实W4 dodge_slide已在共享工作区，接入其Play params(moveX/moveZ/bow)、真实时钟、cancel_open等事件；不调用旧roll。滑步2.2m，.32s，.5sCD；方向接受时快照，死区.18，无方向后撤。取消窗口仍读取片段事件，不另写攻击窗口数字表。

.22跨帧有攻击缓冲时精确截到1.92m，Poll后同帧换到攻击/.04混合；不补.28m，不把旧滑步冲量带入攻击。剩余帧只推进独立真实时间尾段，新的动作时间从下一帧继续。走动在.26停止旧滑步（2.12m），丢弃最后.08m。攻击首段前冲保守统一封顶.35m（贴身必满足，远处也应用该上限，留待Web调参）。连段保留.60s；受击/切武器/取消清理。精准回避前.10s实拦，.8s内下一剑poise×1.5一次，普通滑步不增伤。

安全：中心+8点足迹，半径+.10m；每<=.10m子段，失败后二分至<=.02m；法线坡度<=35°/邻段高度差<=.20m。墙探针在脚踝/身中/头部，实际移动仍经CC，未设置任何隐形墙或直接改角色坐标。起点cc.onGround且足迹完整才接受；截断后不返还CD、不截无敌时钟。桥面用真实物理支撑，不因Terrain环形空隙拒绝已修桥。

尘土起3刹2、寿命.12-.20/粒径.025-.045，经fx_.motesB现有池且cc.onGround门控；中断最多一次刹停，输出Combat: sfx dodge_start/dodge_land，不播未到素材。没有新增资源/meta。

## 未完成的跨owner留影显示（需Lead协调W1）

当前WeaponRig:UpdateImages只接受shot.clip以sword_开头，Update还有active~='sword'门控；也没有返回当前武器世界位姿的公开口。W2不能修改该owner文件。

W2已准备：SlideAfterimages(position,rotation)；0.04–0.16事件门控，0.04s最小间隔，最多2条，life=.08/age/alpha；Scene可选调用rig:GetAfterimagePose() -> worldPosition, worldRotation，并把clip='dodge_slide'真实标记的数组交SetAfterimages，绝不冒充sword片段。

请W1提供GetAfterimagePose（当前active武器实际pivot或等效当前骨骼/SetSwing组合的世界位姿），并让SetAfterimages/Update接收dodge_slide、life=.08，支持剑/弓滑步；滑步留影只显示武器/轮廓，不额外吐刀光线与重击方粒。Scene目前在rig:SetSwing/Update前取样，建议W1端口能返回当前骨骼+当前swing位姿，或回告我需将取样移到Update之后。未有接口时守卫跳过，不报错，但留影**尚不显示**。

## 验证

- Lua54 core+animation PASS：owned-final.log；含30/60FPS完整位移均2.200000、.22取消1.92、.26走动2.12、CD/精准奖励、弓弃箭/旧held不重发、所有取消窗口、子段地形/墙/坡/边缘、触屏down单次、尘土/留影生命周期。
- 全19组（各独立Lua54）14 PASS / 5 FAIL：all-suites-final.log。全部core、anim、weapon通过。5个enemy套件均EnemyParticles.lua:49 attempt to compare table with number；共享EnemyBase等正被W3修改，观察到ApplyHit把表传给原Emit(owner,count,death)的count位置。未擅改它们。
- LSP新进程EmmyLua0.22.2，8文件零Error：lsp-current.log。旧19542桥已停，连接失败留lsp-initial.log；使用同一本机已安装分析器stdio离线检查，无游戏Runtime。
- git diff --check PASS：final-diff.log。日志与验证工具都只在validation/combat/slide/，不提交。

## 共享冲突点

本轮Scene/NomiController只有上述局部战斗钩子；未改VoidRewind/GameSettings/DebugLog/云/龙。当前同批还有W4动画、W1武器/锻造、W3敌人、其他会话SkyClouds/SkyAtmosphere/云shader与docs修改，完整清单current-scope.log/final-diff.log。不能把整个dirty工作区当作W2提交清单。本轮未发现同时修改相同行块的冲突。

Web待验：四方向攻击→滑步→续刀、贴Boss不转身/不过冲、弓准星与弃箭、桥/边缘/阶梯/墙角截断、.22衔接手感、尘土/留影(待W1)、移动端物理探针开销。物理探针次数随路径长度线性增长，约每.1m为9地面+24短墙射线，另有起点/边界二分；不创建新体素或重建网格，真实移动端开销仍需Web测。

