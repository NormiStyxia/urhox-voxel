# W2：背挂、收招宽限、形态切换与滑步镜头

实际HEAD a1853e0，是预期bea1788的后继（中间提交为云层/相机更新）。保留云WIP与未跟踪产物；未commit/push/build，未启动任何本地游戏Runtime。等待Lead统一官方构建。

## 改动与归属

- scripts/combat/CombatState.lua：Activity新增可选keepPose（Shift传true）；进入战斗back，只有攻击取hand。SetBusy从true→false重置宽限，收招后0.40s回背，无收刀transition锁。Q先hidden，再SetActive目标且维持hidden，原0.40s结束/weapon_ready才back；FinishTransition在探索/骑龙/死亡时不能复活武器。
- scripts/combat/CombatMoves.lua：WeaponInHand读rig请求pose（无该字段的离线端口fallback到State）；Shift保留原姿态，取手动作不再先把Rig反向改回back；收刀后新攻击重置连段并只取一次武器。移除draw结束无pending时默认light；Poll结束可消费最后160ms的单条输入，避免回背边界漏输入。Q不恢复旧active/pose，weapon_stowed不提前显目标。Play滑步带weaponInHand，且每帧GetMotion之前更新。空闲back不叠stance_combat。
- scripts/combat/CombatCamera.lua:57–61：焦点滞后幅度.30→.12m，0.06s平滑起势；距离.25→.12m、FOV+3→+.8，接攻击前推.15→.10，均平滑归零。起步不再瞬跳.30m。保留镜头开关、弓55→43及取消恢复。
- scripts/ruins/RuinsScene.lua：77/1696预览参数；删除原732–737“back回调重新hand+sheath”；1253/1264–1286 F7默认持手、O切背挂并传参；1315显示O状态；1354 Apply参数；1493基础Animate使用WeaponInHand而非ACTIVE，解谜casting不变。未改NomiController/CombatHUD/龙/云/解谜代码。
- tests/combat/core_stow.lua新增；更新core_state、core_camera、core_melee_zone、core_swap_pool。原melee_zone测试每刀等待.8s会超过新回背宽限，改.6s以继续验证真实连续三段而非三次首击。
- 主方案新增§22，明确覆盖旧2.5s、Shift强取手、回背busy锁、Q恢复旧把规则；解释C/Q/骑龙/死亡与软取消的差异。

## W1/W4合同

W1继续SetPose(hidden/back/hand)、SetActive，无新方法需求。回背仅Rig表现，不能反调Moves.Play(sheath)/设置busy；新hand请求可中断stow。Q逻辑在.40s锁期间保持目标hidden，即使Rig内部支持更短消隐，也不提前显目标。退出形态请求hidden并清特效，主武器按W1短消隐结束，后续旧事件不得再显。

W4已接：Play(dodge_slide).params.weaponInHand及每帧Update/GetMotion前SetParam（0浮背/1手持），内部τ=.05平滑；F7默认1、O切0，DebugSample同参数。基础Animate也按实际pose。24片段时序/事件/motion不由W2修改：0–.06/.06–.16/.16–.26/.26–.30四段总2.20m，.22取消1.92m；.04–.16仅残影窗。

共享冲突点：Scene仅以上战斗局部段，无同段覆盖冲突；W1 WeaponRig/weapon_rig、W4 AnimClips/CombatAnim/anim_spec及sky-fx/云贴图的并行修改均未动。全量早期曾遇到W1修改中测试不匹配，最新工作区已33套全绿。

## 验证

python3 validation/combat/juice/run_tests.py / PASS（33套core/anim/enemy/weapon） / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/tests.log

python3 validation/combat/dodge-stow/lsp_check.py / PASS（14个本轮与回归Lua文件，零Error） / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/lsp.log

python3 validation/combat/dodge-stow/allocation.py / PASS（600帧，PC .152、触屏 .191、Boss .488、范围 .191 KB/帧，与上一轮相同） / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/allocation.log

git diff --check / PASS / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/diff-check.log

/review（人工差异与状态/事件流审查） / PASS / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/review.log

新增覆盖：战斗进入/移动/Shift浮背；三连只拔一次；收招宽限与回背中重按；切换末帧缓冲；Q消隐/目标背挂/.20取消；C/骑龙/死亡/停止后旧事件不复活武器；菜单/失焦/TouchCancel弃箭与p/pitch保持；GetMotion前参数时序、基础armed；残影窗与完整运动独立；50次真实Moves→State→Rig切换（引擎端口模拟）Build/Compile/CreateVolume/grid-write/rebuild增量0。

## 未验证 / Web清单

1. C进战但不打，站/跑自然、武器浮背；剑柄朝上/弓斜挂由W1图像验收。
2. back→Shift与攻击→Shift，正侧背视频观察新W4重心/四肢、镜头软起势、.22接攻击及.26接跑；F3开关对比。
3. 三连与短/满蓄重击，收招约.4s回背；回背飞行途中再点攻击，无反复拔收、卡手或漏刀。
4. 弓松手/取消首帧与整个收招、换武器弃箭、55→43及恢复；手机真实多指/TouchCancel。
5. C/Q/上下龙/死亡/菜单/失焦反复切换，旧武器、箭槽、残影和flash无残留/延迟复活；Q目标出现时机。
6. 真实帧时间/渲染/碰撞成本与手感。离线模拟分配与几何测试不作为Web视觉或原生性能通过。
