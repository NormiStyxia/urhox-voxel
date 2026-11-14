# 战斗 Web R1 实测 — 2026-11-14

结论：部分入口和动作可用；锻造预览存在明确 Lua 错误，本轮不能整体验收通过。只操作 Cindy external/CDP 浏览器，没有改源码、提交、构建或启动本地游戏 Runtime。所有已使用键鼠已释放，F7 已退出，Forge 已关闭。

## 版本与证据边界

- 入口：https://maker.taptap.cn/app/f323832c-195d-4276-a841-0ceafd1f1cf1?localDev=1&hide_chat=1
- 同一 tab targetId=82A6CFAFF4DF3C2BCD316957A406C437；CSS 2297×1129。图像工具缩图为1280宽，不等于CSS坐标。
- Lead 提供构建提交4f02cd8；本地开始/结束HEAD均c59ac6c9810424bf1cb194e064f1739ddde1c0f1，工作区有其他会话持续修改，见baseline.log/final-workspace.log。本轮未改源码。
- 本轮03:30:20重新导航；浏览器03:31:08.324记录 RuinsScene ready in 37.06s, volumes688，画面有战斗HUD/F7/Forge。网页没有可核实Git SHA，不能仅凭本地HEAD认定精确网页版本。
- watcher仍停在03:27旧会话：watcher-tail.log。新会话证据使用browser-current-session.json（UTC时间=本地时间减8小时）。startup-runtime.log/startup-errors.log是旧会话，不可当成本轮错误。

## 实测结果

| 项目 | 结论 | 实际观察与证据 |
|---|---|---|
| 开场场景/玩家心形血量 | PASS | 场景完成加载；10颗心为两排5颗。spawn.jpg（内容为WebP） |
| C进入战斗/背部武器/按钮换组 | PASS | C按下约150ms后，背部出现剑、底部换为剑/重击/闪避/Q；combat-c-held.webp |
| 探索手光及战斗互斥 | UNDETERMINED | 探索手旁小白方粒可见，战斗截图不能充分分辨完整手光是否全灭；画面上方还有大白方块团，来源未知，不能混为同一种特效 |
| 左键三连 | UNDETERMINED | 三次真实CDP鼠标按下/释放后角色持剑并前移；sword-clicks.webp。未取得动作事件/逐段判定证据，不能认定三段连击及伤害通过 |
| 按住重击 | 部分 | 真实右键按住1.2s出现持剑动作，heavy-held.webp；蓄满判定/松手命中未验证，不能由姿势推断 |
| Shift闪避 | 部分PASS | C进战后A+Shift约170ms，角色从门前移到左侧草地，dodge-live.webp；无敌帧/精确2.6m距离未验证 |
| Q切弓/拉弓 | PASS（限切换与满蓄显示） | Q后按住左键1.3s，弓出现在手上，显示“满蓄·松手射击·闪避取消”，bow-held.webp |
| 弓松手射击/三档/取消 | UNDETERMINED | 已实际释放鼠标，但未捕捉箭体或伤害日志；三档、取消不出箭未测，不能声称射击通过 |
| 6s安静脱战 | PASS（状态/隐藏） | 闪避后不输入6.5s，恢复探索三个按钮，剑隐藏，quiet-exit.webp；手光完整互斥仍留上述边界 |
| G打开锻造 | 入口PASS，预览FAIL | G可打开库，但预览长期停“分帧组装中”；forge-open.webp/forge-loaded.webp。没有Forge preview:3d或fallback日志 |
| 换部件/背上更新 | 未验证 | 预览组装抛错后未继续改装备；ESC可退出，forge-close.webp |
| 虫/哨灵/石甲兽/前摇/敌血条/Boss条 | 未验证 | 尚在南门外。左键与数字1有限尝试后门仍在，数字1提示“古石太坚硬，只有带时之印记的物件和碎石能被打碎”，gate-key1.webp；未绕过正常路线瞬移 |
| 触屏多指/TouchCancel | 未验证 | 桌面浏览器工具不能作为真实手机触摸验收，本轮没有伪造DOM事件 |

## 可复现的明确错误

步骤：开场点击画布激活 → C/Q与弓测试 → 等待安静脱战 → G。03:37:42.790起重复：

```text
Execute Lua function failed: [string "combat/WeaponBuilder"]:348: error in function 'GetSystemTime'.
     argument #1 is 'Time'; 'Time' expected.

stack traceback:
    [C]: in method 'GetSystemTime'
    [string "combat/WeaponBuilder"]:348: in local 'clock'
    [string "combat/WeaponBuilder"]:349: in field 'StepBuild'
    [string "ui/ForgePanel"]:530: in function <[string "ui/ForgePanel"]:513>
```

完整重复日志：browser-errors.json/browser-current-session.json。该报错属于本轮新导航，不能与旧的settings.json/weapons-v1.json缺失错误混淆。未修改W1文件，请由owner对照引擎Time静态/实例绑定查修后再测。

新会话另有03:30:33 SurfaceShader警告：`opaque material has no deferred pass because of: POSITION ... Deferred rendering has no automatic forward fallback; depth-only coverage may remain.` UUID HQ-5qfZwSR37r_zXuUDQ01dw 对应HiddenVoxel.shader，不作为战斗shader编译失败结论。

## 动画截图与美术审阅

F7进入，右方向键逐片段切换，截图含左上clip id/t/phase。共22张anim-*.webp（除stance外全部片段），含三连、heavy_release、dodge_roll、bow_hold/release、hit_light/heavy、death/getup、双向weapon_swap。已实际查看animation-contact.jpg逐格联系表。

- 能看到重击举剑、弓竖直、倒地/起身等不同姿态，未发现足以由这些静帧直接断言“轴向必反”的片段。
- sword_light_1=.75、light_2=.66、dodge=.59、hit_light=.37、hit_heavy=.45、getup=.49等截图已到hold/动作结束；不可拿它们认定活动段正确。三连运动符号、翻滚方向、双向换武器穿模仍需活动段慢放/录像。
- bow_hold=.65可见右臂向右展开，sword_heavy_release=.37举剑收招；这是供美术审阅的候选，不宣称方向错误。
- 底部Pointer提示与“满蓄/拔刃”等通知重叠，遮挡人物腰腿和部分动作；bow-held.webp最明显。
- H展开的右上说明在战斗态仍写“左键蓄力碎时、Q回溯、C下降、G滑翔”，与当前战斗键位不符；heavy-held.webp/bow-held.webp。这是明确文案分流问题。
- 场景上方持续大型白方块团且有棕色弧形物，spawn/combat/quiet各图可比；来源未证实，不归责武器或手光。

优先看：forge-loaded.webp、bow-held.webp、animation-contact.jpg、combat-c-held.webp、quiet-exit.webp。本轮不需要补新图标，先修锻造运行阻塞与提示重叠/说明分流，再审动作活动段。

## 操作与工具边界

原始回执operation-receipts.json；点击/按键均Cindy允许的CDP Input命令。最初clickCoords因PortInUseError未执行，改用同一个Cindy CDP入口成功点击，未另连浏览器。首轮释放参数超过12项被拒，已按12项+2项拆分全部成功：release-inputs-final.json。

本轮无代码/静态测试/构建。后续建议：W1先修GetSystemTime调用；Web重测Forge是否实际3d或fallback；W2再修PC说明与底部通知布局；建立可慢放的动作活动段证据后由W4校准。
