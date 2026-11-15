# R9 交接

2026-11-15。R10改动与埋点保留；未commit/push/build，未启动任何本地游戏Runtime。并行弓/近战/敌人/轮盘/云层等WIP保留。

## 验证（完整输出见日志）

- /tmp/pxvenv/bin/python -I /tmp/run_all54.py / PASS：50 suites, failed 0 / /Users/xd/Desktop/体素test/validation/combat/r9-sprint/all-final.log
- /tmp/pxvenv/bin/python -I validation/combat/r9-sprint/lsp_check.py / PASS：19文件，0 Error / /Users/xd/Desktop/体素test/validation/combat/r9-sprint/lsp-final.log
- /tmp/pxvenv/bin/python -I validation/combat/r9-sprint/compile_check.py / PASS：12运行脚本，Lua5.4 load只编译、不执行 / /Users/xd/Desktop/体素test/validation/combat/r9-sprint/compile.log
- /tmp/pxvenv/bin/python -I validation/combat/r9-sprint/contract_check.py / PASS：滑步玩法合同逐字段一致、单一来源 / /Users/xd/Desktop/体素test/validation/combat/r9-sprint/contract.log
- git diff --check / PASS / /Users/xd/Desktop/体素test/validation/combat/r9-sprint/diff-check.log

## 文件与接线

1. scripts/ruins/FootLocomotion.lua（新增）：纯Lua真实秒协调层，New/Begin/Finish/Cancel/Accepted/Rejected/Start/Exit/IsRunning；Distance/Speed为解析积分；PhaseForLegs拟合实际髋角；Soles/Ground/Debug为八鞋点视觉接地。共享输入、animOpts/params与调试记录稳定复用，10000热帧gross Lua增量0.000B/帧（仅协调层，不包括引擎userdata、动画数学mock、音频/尘粒事件）。官方generate_resource_meta已生成本文件和5份新测试的.meta。
2. scripts/combat/CombatMoves.lua：探索接受闪避不Enter/Activity、不拔武器；0.24 pending抑制0.26提前退出；0.30 EndSlide(true)接续跑；真实接受时刻计算CD/缓冲/长帧位移。取消/路径截断清pending；attack仍0.22优先。新run_step区分短按制动，EmitDustStreak可maxCount=1供单粒脚尘，保留池预留预算。未改变R10 QueryZone/子段/命中合同。
3. scripts/ruins/NomiController.lua：MeasureMotion采上一物理步实际速度/位移/时长；Move消费runDistance一次，不再双重k=12；普通探索与施法原平滑保留。跳跃携水平速度进入旧空气控制；续跑朝向≤540°/s。GroundFeet只修视觉root，不动碰撞或水平位置。
4. scripts/combat/AnimClips.lua、CombatAnim.lua：dodge_slide合并为唯一最终定义；R9八时刻姿态与pending尾分支。新增sprint_loop（空motion），LOCOMOTION=2，DODGE=5，高层攻击/受击仍覆盖；跨层0.04s归一混合。weaponInHand平滑也覆盖续跑，去掉重复bob，保留所有符号待Web校准标记。
5. scripts/combat/CombatCamera.lua、CombatAudio.lua、CombatState.lua：续跑distance≤.20m/FOV≤1.5°，.22入/.18退，与滑步max，弓/远景/低档优先；run_step复用dodge_land现有预载，cue −14dB、间隔.12s，没有生成新音频/风循环。持续跑不busy、不Activity，保持回背/脱战。
6. scripts/ui/TouchInput.lua、TouchControls.lua：evadeRun/runIntent/龙dash分离；完整合并PC/触屏/逻辑pad边沿，任一held有效；触屏新增64dp O+(-292,-32)按钮，实际sprint_s图标与“闪避/跑”标签。战斗原(-148,-32)按钮同长按合同。CD只画遮罩不禁用，pending/run画2dp环，保留捕获与取消所有权。
7. scripts/ruins/RuinsScene.lua：仅相关输入/动作/动画/相机/取消与脚尘回调接线；F7显示髋Y/8鞋点/地Y/root修正，RUINS.foot:Debug()读稳定记录；F11旧edge适配。scripts/ruins/RuinsHUD.lua仅HelpLines两组Shift文字更新（轮盘同事文案保留）。主方案§7/§18/§22.1、移动端规范§3/§7同步。
8. 新测试 tests/combat/locomotion_state.lua、locomotion_pose.lua、locomotion_input.lua、locomotion_camera_motion.lua、locomotion_support.lua；既有anim_spec/audio_spec只更新R9期望并扩充回归。

## 关键合同

- 所有时间秒；速度m/s、位移m、欧拉度。evadePressed/evadeHeld/runIntent/allowed/onGround布尔；axis为世界XZ方向。inputRevision变化硬取消；motionSampleDt是上一段实际物理观测时间。
- 按下立即闪避；held≥.24登记，.30以2接7.2/.22解析加速。完整2.20+1.012=3.212m，30/60/120FPS和.52s单帧均相等。0.20无敌结束、0.22接攻击（累计1.92m）、0.50 CD；短按有方向0.26结束（2.12m），无方向完整2.20m。
- 实际CC只一次desiredVelocity写入；GetMotion只给滑步米数，FootLocomotion.distance仅给本帧续跑部分；取消不补剩余位移。
- 取消/上龙/虚空/失焦/输入模式边界→WAIT_RELEASE；短按释放不再闪，持续held不自动连闪；空中/危险起点不扣CD且不能靠hold绕过。手机探索满推直接平滑runIntent，无闪避；龙dash原义。
- 最低root目标−.02m；实际8鞋角按几何接地，clearance .006m，立即上抬/.04s下降，SLENDER .1386m只加一次。腿/身体平级，不减body第二份角度。首步按已绘制髋角选相位，稳态腿−34/+28°、body14–16°。
- 新音效名run_step，仅复用资源。没有新玩法事件；原iframe/cancel/move/dust/afterimage事件全部保持。
- 手柄只有SetGamepadEvade(bool)逻辑端口，尚无经验证的硬件默认映射；不能宣称手柄真机已完成。

## 待Web/真机

正/侧/背录像前后左右/斜向：短按停、长按连续、滑步0.22接攻击，手持/背挂剑弓与探索/战斗各一轮。重点首帧前倾、0.30衔接、鞋底穿地/水平滑移、衣发/背武器碰插；斜坡/台阶/墙边/冻结桥/虚空、上下龙/菜单/focus取消；手机三指捕获与844×390、915×412和窄屏安全区按钮位置；相机关闭与弓缩放不残留、脚步音量；R10日志/P95与接地8射线成本。所有视觉与手感均未验证，交由Lead统一Web构建。
