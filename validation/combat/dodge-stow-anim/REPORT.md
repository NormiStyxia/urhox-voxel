# W4：滑步重心与浮背臂态，2026-11-15

实际起点HEAD=`a1853e0`；与预期`bea1788`相比，三个动画归属文件逐字一致。云层WIP与其它任务输出保留。未commit/push/build，未启动本地游戏Runtime。

## 改动

仅修改 `scripts/combat/AnimClips.lua`、`scripts/combat/CombatAnim.lua`、`tests/combat/anim_spec.lua`；本轮没有新Lua文件，无需新.meta。

- 取代夸张固定低姿：root最低从−0.24m改为−0.10m，前滑胸部最大16°、侧倾最大6°。起步稍反向收重心，蹬地后躯干跟进，末段反向制动再归位。
- 六姿态错相：腿在0/.04/.075/.16/.24/.32s，躯干在0/.04/.10/.18/.26/.32s，肩臂在0/.055/.12/.20/.27/.32s。插值使用smoothStep，关键姿态两侧角速度连续；不添加不存在的膝骨。
- 正常视觉淡入0.04s、淡出0.08s，使用平滑权重；root首尾偏移归零。核心滑行期间双腿完整覆盖基础跑步，收尾平滑交回新基础姿态。攻击取消仍保留原0.04s互补交叉混合，不修改接招窗口。
- 持剑臂不再从−65°猛甩到+55°；改为−50°至−24°的小幅随动。浮背时双臂自然前后平衡，最大pitch18°；八方向根据运动方向投影，并交换侧向支撑/领先腿。头抵消部分胸部pitch/roll/yaw。

## 接线合同（给W2/F7）

`weaponInHand`为无单位数值，0=武器浮背/不握持，1=在手，**默认1兼容**；输入夹到[0,1]，允许中间值表示飞行过渡。

```lua
anim:Play("dodge_slide", {params={
    moveX=localDirectionX, moveZ=localDirectionZ,
    bow=isBow and 1 or 0, weaponInHand=isHeld and 1 or 0,
}})
-- 后续每帧在 Update/GetMotion(dt) 前更新；无须修改骨骼或socket。
anim:SetParam("weaponInHand", isHeld and 1 or 0)
```

Play初始化直接采用该值；之后参数变化通过每轨道标量缓存按真实秒平滑，时间常数0.05s，30/60FPS结果一致。Stop时冻结当前臂态，直接混入下一攻击，不先变握剑待机。F7用 `DebugSample("dodge_slide",t,{moveX=...,moveZ=...,bow=...,weaponInHand=0})`可查看纯浮背姿态；DebugSample是静态目标，无时间平滑历史。

`moveX/moveZ`继续只在Play快照，不随每帧输入重定向。body局部小幅扭转只是肩髋表现，不改controller/root朝向。基础Animate的armed状态与浮背/在手一致性仍由W2负责，否则收尾回到基础层时可能重新抬成持剑臂。

## 未改的合同与注意点

- 24个片段的dur/eventDur/events/motion/phases/speedStat/realTime/cancelAt/cancelBlend与基线递归精确相等。
- 滑步仍0.32s、总2.20m、0.22s取消累计1.92m；Stop后未消费/未来motion清零，攻击不继承冲量。
- 实际源码中的 `.04–.16s` 是残影窗口，已原样保留。实际位移仍0–.06s/.06–.16s/.16–.26s/.26–.30s四段，分别.72/.90/.50/.08m；本轮未把位移擅自压缩进残影窗口。
- 全程真实秒与逐帧采样不变；无敌到0.20s、取消0.22s、dust_stop0.26s、move_end0.30s等事件不变。
- 新增的轨道表仅在模块加载时创建。Update新增标量平滑，Apply只复用现有轨道/输出；无新增每帧Lua表或节点创建。
- 只读检查发现相机仍有既有0.30m焦点滞后、0.25m距离脉冲和+3FOV，这些可能影响“僵硬/顿挫”的主观观感，归W2处理；本轮未改Camera或增加镜头旋转/抖动。
- 单段腿只能通过髋旋转、重心和时序表达蹬地，不能声称实现膝盖折叠或脚底锁地。角色体型/脸/头发/服装/肘开关/HandSocket均未改。

## 验证（完整日志）

`ANIM_BASELINE_FILE=validation/combat/dodge-stow-anim/AnimClips-baseline.txt python3 -c 'from lupa.lua54 import LuaRuntime; LuaRuntime().execute(open("tests/combat/anim_spec.lua").read())'` / PASS（74项） / `/Users/xd/Desktop/体素test/validation/combat/dodge-stow-anim/anim-regression.log`

`git diff bea1788..a1853e0 -- owned-files + anim_spec基线合同对比` / PASS / `/Users/xd/Desktop/体素test/validation/combat/dodge-stow-anim/contract-check.log`

`maker-lua-lsp watch --http-port 19558 + textDocument/diagnostic severity=1` / PASS（4文件零Error） / `/Users/xd/Desktop/体素test/validation/combat/dodge-stow-anim/lsp-diagnostics.json`

`git diff --check -- scripts/combat/AnimClips.lua scripts/combat/CombatAnim.lua tests/combat/anim_spec.lua` / PASS / `/Users/xd/Desktop/体素test/validation/combat/dodge-stow-anim/diff-check.log`

`/review（人工差异审查）` / PASS / `/Users/xd/Desktop/体素test/validation/combat/dodge-stow-anim/review.log`

## 待Web正/侧/背录像验收

1. 无遮挡地面，站立→Shift→站立与跑步→Shift→继续跑，各以前后左右/四斜向录制；观察起步压重心、领先腿蹬出、制动落脚和收尾，不只看单帧。
2. 武器浮背时双臂自然平衡；持剑/持弓滑步轮廓；飞行途中切换0/1有无突然抬肩。
3. 0.22s接轻击/拉弓、0.26s交回跑步：无待机一闪、无额外前冲或突然转头。30/60FPS各录一组。
4. 正侧背检查刚体腿是否交叉/穿地、剑弓是否扫脸/衣服；先固定镜头或关镜头特效，再恢复跟随镜头区分姿态与相机问题。

**视觉、真实脚底接触、碰撞场景与手感均未验证，符号仍待Web校准。**
