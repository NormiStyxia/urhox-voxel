# W2 自由朝向 / 近战索敌 / 弓按住瞄准

基线 HEAD 96ffec9。本轮未 commit/push/build，未启动本地 Runtime/preview/validate/surfaceless。等待 Lead 统一官方构建；视觉、手感与原生性能均未验证。

## 文件与接口

- scripts/combat/CombatMoves.lua：SelectMeleeTarget（19起），3.6m候选、意图±75°（≤1.5m放宽±90°）、高度差≤2m、活敌/视线过滤、角度优先评分；每段接受时快照，方向与 hitForward/motion/区域一致，不追踪。保留原动画0.50/0.45/0.70/0.65m，出刀不叠玩家移动速度，沿足迹/墙检测截断。StrikeZones/ZoneBoundary 与实际Hit.QueryZone共享区域，缓存预建复用。修复旧whooshTime出声后停止推进，重击slam现在能进入真实最后1/3条件。
- scripts/ruins/NomiController.lua:224：AssistMelee(enemies,cast,intent,enabled) 返回direction,target，出招前完整转身，保留camYaw。其余cc/安全返回/SpellPalm未改。
- scripts/combat/CombatCamera.lua:34：bow_draw开始0.20s smoothstep FOV55→43、look1→0.60，松手/取消0.10s回零；F3/cameraFov关闭不缩放、不降敏；不叠旧Zoom模式。
- scripts/ui/CombatHUD.lua:10,139：50份预分配点记录；真实区域预备期稀疏金色2dp点，活动期4dp点，收招隐藏；slam同源。Set投影，Render无新表/向量/字符串。遮挡/虚空点隐藏，无常驻填充圆。
- scripts/ruins/RuinsScene.lua 局部钩子：549–553 intent/aimPitch/assist；1230–1234仅拉弓锁相机朝向；1305 F7收招参数；1352–1356与1494 Apply前BowParameters隔离；1589拉弓去掉敌人加权焦点；1615–1630物理遮挡/地面筛选；1645 HUD端口与降敏合并。龙/云/回溯/解谜/GC逻辑不动。
- CombatMoves.lua:195 BowParameters(pitch)：W4松手p/pitch快照保持至收招结束；软取消播放无玩法busy锁的bow_cancel，立即清charge/pendingFire；重复blocked不清尾段。滑步/受击/切换/死亡/脱战等硬打断仍立即停止；F7 release/cancel也保持p。
- scripts/combat/CombatState.lua:24：发现隔离计时仍向Time实例调用静态绑定，改为优先Time类表，与Scene既有修复一致。无Time的离线主机才fallback；已测试拒绝实例接收器。
- 新增 tests/combat/core_free_facing.lua；更新 core_motion.lua、core_camera.lua、core_ui_alloc.lua。主方案新增§21（623起），覆盖旧35°/20°与旧弓−5°。

## 验证

python3 validation/combat/juice/run_tests.py / PASS（32套core/anim/enemy/weapon，含旧碎时/冻结/回溯/骑龙吐息/触屏分组；50次Moves→State→Rig切换，Build/Compile/CreateVolume/grid-write/rebuild增量0） / /Users/xd/Desktop/体素test/validation/combat/free-facing/tests.log

python3 validation/combat/free-facing/lsp_check.py / PASS（本轮10个Lua文件，零Error） / /Users/xd/Desktop/体素test/validation/combat/free-facing/lsp.log

python3 validation/combat/free-facing/allocation.py / PASS（600帧，PC .152、触屏 .191、Boss .488、范围显示 .191 KB/帧） / /Users/xd/Desktop/体素test/validation/combat/free-facing/allocation.log

git diff --check / PASS / /Users/xd/Desktop/体素test/validation/combat/free-facing/diff-check.log

/review（人工差异与控制流审查） / PASS / /Users/xd/Desktop/体素test/validation/combat/free-facing/review.log

分配测量使用模拟绑定和静态可见回调，不含原生投影/射线成本，不作Web性能结论。

## 对外合同与共享冲突点

W1/W4无需新增接口；继续消费GetMotion、SetBowDraw、SetSwing、SetAfterimages、PopEvents。W4 duration/events/phases/motion未修改。MeleeZone新增可选out，旧调用兼容；AssistMelee唯一Scene调用已同步。

Scene/Nomi仅以上局部修改，无同段写入冲突。工作区同时存在W1 WeaponParts/Builder/Rig、W4 AnimClips/CombatAnim/anim_spec，以及云shader/密度图/sky-fx脚本修改，均原样保留。不要把整个工作区diff归为W2。

## Web必测

1. C进战后WASD/摇杆四向、站定绕镜头；身体不强追镜头。明确意图时背/侧转身，墙后/远处/死亡不选，多目标不误打意图身后。
2. F9三连与短/满蓄重击；前迈只原动画量，墙/岛缘/桥面真实cc截断。身体方向、刀光、命中和点状范围吻合；边界在斜坡/遮挡处是否过碎过暗（无地面和被遮挡点会省略）。
3. 弓按住立即放大、肩侧瞄准；短按与满蓄射击；PC/真实手机多指菜单、失焦、TouchCancel、闪避、切武器、死亡、上龙取消不补射、缩放无残留；F3反复切换不漂移。
4. W4松手/取消首帧及整个收招手部、弓身/弦/右手贴合（单段手臂限制仍在）；F7同参数对比。
5. 原生帧时间/射线成本与HUD边界可读性，不能用mock分配替代。
