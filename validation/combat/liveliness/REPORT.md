# §20 镜头、接线与 F7（2026-11-14）

代码与离线回归完成。未提交、推送、构建、刷新 Web 或启动任何本地 Runtime。视觉/手感/真实原生碰撞均未验证。

## 本轮实现

- 新 CombatCamera.lua：每帧真实时间一次更新，输出可复用的焦点偏移/距离/FOV/灵敏度/准星收拢。滑步仅成功接受时触发：初始后滞 .30m，解析二阶弹簧阻尼 .745、首次追平 .18s、过冲约 3%；距离 +.25m（.08/.25s），FOV +3°（.05/.20s）。接攻击时结束拉远，.04s 进入 -.15m 前推，再 .14s 回收。F3 默认沿用 cameraFov=true，关闭全部动作镜头/FOV；F2 仍独立控制命中震动。
- 攻击：读取现有动作时间与片段 active 开始，前 .06s 蓄势后拉最多 .08m；第三段 hit_off 触发 .03m 下压；重击 +2° 与现有命中 FOV 取最大，避免双叠。所有位置偏移在基础相机碰撞回缩后合成，并再次检查最终相机路径；不写回跟随累计状态，不更改 yaw/pitch/roll。
- 弓：p 驱动 -5° 收镜，最多 .5s 跟上；拉弓灵敏度 .65，释放 .1s 回零；满蓄事件仅一次 .006m 小抖。准星中心固定，四臂以 2px 整数阶梯收缩，保留原 UI DPI/NEAREST/12px/24px 流程。
- W4 前冲：动画 motion 仍唯一位移源；剑普通/重击接 Nomi ClipAttackMotion，复用滑步的 <=.10m 子段、碰撞半径+.10m 足迹、坡/高差/墙检查。无地面/空中返回零；重建桥以真实碰撞承托为准，不能因 Terrain 岛域 mask 把桥误判虚空。原 cc 速度接线保留，不瞬移。
- 接入 SetBowDraw(p)、aimPitch（相机 pitch，±35°），每帧只调用一次 Rig.Update。PopEvents 在 Update 后消费一次：materialize 复用低音量 blade_draw 提示（没有另造音频），blade_draw/blade_sheath 到达事件播对应音；新 Rig 的 ArrivalFlash 自管一次闪光，移除旧动画事件的双播/抢先闪光。方法不存在时兼容旧接口。
- dust_streak：四个地面方粒，沿滑向反向铺开 .54m、寿命 .14–.20s；复用 Spawner 共享池，压低装饰优先级，不另开池，不碰敌人保留槽。现有 Emit(dust) 固定六粒，因此适配器只调整此次 owner+serial 新槽并收回两粒；当前实现依赖池的 slots/serial/Hide，若 W3 后续封装专用接口应替换该适配器。发现新 dust_streak 片段后关闭旧起步/刹停 motes，避免重复粒子；音效事件保留。
- F7：1/2/3/4 前/侧/背/斜，2.6m、胸口焦点，鼠标左右限定 ±25°，不写入正式 camYaw/camPitch。保留 IJKL/B/+/− 和暂停逐帧。显示片段、时间、阶段、方向、p，以及 W4 GetIKDebug（缺失时 DebugSample._ik）的躯干局部目标；实际握点由本帧骨骼 LocalToWorld→body.WorldToLocal 求得。无轨迹片段明确提示。相机仍走原 ThirdPersonCamera 库与体素防穿透；墙边实际距离可能小于2.6m。

## 所有权与共享修改

本轮仅以下文件：
- scripts/combat/CombatCamera.lua + .meta（官方 generate_resource_meta 生成）
- scripts/combat/CombatMoves.lua
- scripts/ruins/NomiController.lua
- scripts/ruins/RuinsScene.lua
- scripts/ruins/RuinsHUD.lua
- scripts/ui/CombatHUD.lua
- tests/combat/core_camera.lua

共享 Scene 局部行段见 line-map.log：初始化/运动与尘线 425–446，鼠标预览 762/1110，F7参数 1155，IK诊断/武器接线约1250–1320，PostUpdate镜头1390–1439，卸载1459。Nomi只新增 UpdateCombatPreview 与 ClipAttackMotion（317附近）。未改 W1/W4/敌人/音频文件；未改并行会话云层材质、shader、SkyAtmosphere/SkyClouds；未覆盖 docs 方案或未跟踪目录。entry status 和 final status 均留存。

## 验证

python3 validation/combat/juice/run_tests.py / PASS / /Users/xd/Desktop/体素test/validation/combat/liveliness/tests.log

24 套全绿，包括 core/anim/enemy/weapon/audio 与新增：解析弹簧3%过冲、30/60 FPS一致、F3关闭与回零、弓释放/满蓄单次、真实W4前冲经过裁剪端口、共享尘线4粒/空气不发/敌人槽不动、F7不污染游戏视角、成功接受才触发滑步包络、到达事件不重复闪/音。中间 W1 尚在改动时出现的旧断言失败留在 tests-initial.log，最终全量已通过。

python3 validation/combat/liveliness/lsp_check.py / PASS / /Users/xd/Desktop/体素test/validation/combat/liveliness/lsp.log

7个本轮Lua零 Error。

git diff --check / PASS / /Users/xd/Desktop/体素test/validation/combat/liveliness/diff-check.log

已审查 review.diff；没有修改引擎/配置/他方文件。离线结果不代替 Web 视觉判断。

## 第一次 Web 要看

1. F7 暂停 light1/2/3、heavy、四向slide、bow_hold；1–4视角，左右微转，读目标/实际握点与武器握持是否吻合。
2. 弓 p 0/.5/1，向上/下瞄准：箭/弦/手臂是否同向；FOV与准星是否自然；松手/取消 .1s 回位、满蓄不反复抖。
3. 滑步后滞是否够明显、F3关闭对照；.22接刀是否从拉远切到前推；墙边镜头不得越墙，准星中心不跳/不滚转。
4. 近岛边/墙边三连和重击的前冲截断；真实cc/帧率差异需Web确认。
5. 背后浮现→飞手→收回只听到一次到达音且只闪一次；尘线不悬空且不与旧motes叠发。

## W4 交付接线补记

正式接口已复核：dust_streak、真实 motion 裁剪、Apply 后握点诊断均已接入。Scene 每帧持续发送弓 p（包含 release 姿态段），aimPitch 保持引擎符号。F7 增加 P 键切换 legacyPose=0/1，暂停时重采样同一 t；仅预览内生效，显示当前路径/旧轨道状态，旧轨道不展示残留 IK 目标。此次只追加修改 Scene 与 core_camera 测试。

python3 validation/combat/juice/run_tests.py / PASS / /Users/xd/Desktop/体素test/validation/combat/liveliness/w4-tests.log（24套）

python3 validation/combat/liveliness/lsp_check.py / PASS / /Users/xd/Desktop/体素test/validation/combat/liveliness/w4-lsp.log（零Error）

git diff --check / PASS / /Users/xd/Desktop/体素test/validation/combat/liveliness/w4-diff-check.log

仍未构建/提交/运行；P 键新旧姿态差异待 Web 实拍。
