# W2 可预览交接（静态就绪，非运行验收）

2026-11-14。没有本地 Runtime、提交、推送或构建。未修改设置任务文件、W1/W3/W4 文件、地形/建筑/谜题/龙/着色器。

## W2 文件清单
- 新增：scripts/combat/CombatState.lua、CombatMoves.lua、Hit.lua、Projectile.lua；scripts/ui/CombatHUD.lua；各自官方 .meta。
- 修改：scripts/ruins/RuinsScene.lua、NomiController.lua、RuinsHUD.lua；scripts/ui/TouchControls.lua。TouchInput 使用原有接口，本轮无源码改动。
- 测试：tests/combat/core_state.lua、core_moves.lua、core_hit.lua、core_projectile.lua、core_routing.lua、core_motion.lua、core_touch.lua、core_support.lua 及官方 .meta。
- 已用官方工具补战斗 PNG 的 metadata（含心形16px、Boss条）；未改美术PNG。回执见 stage45-meta.json。validation 不提交。

## Scene 战斗行段（当前快照）
- 32–54：模块/实例与输入锁；234–241：上龙前脱战/阻止死亡和调试状态上龙。
- 330–456：独立武器射线排除、EnemyAttackCue无声占位、命中粒、锻造安全检查、真实Rig/Anim/Projectile/Spawner接线、死亡安全复活。
- 458–483：TouchControls provider、取消；542–569：Rig创建、CombatState状态/手光/取消回调、安全返回接线。
- 621：订阅 EnemyAttackCue；656–735：鼠标、键盘、失焦的锻造/战斗门控。
- 749–762：PC F6辅助瞄准、F5伤害数字；默认开/关不变，手机与触屏模式不响应。
- 779–883：战斗目标瞄准、时间法术互斥、物理步前战斗输入/移动。
- 885–981：输入释放锁、状态推进、F7片段循环/左右与方括号切换/空格暂停、战斗与锻造按键、敌人/箭更新。
- 1017–1025：Nomi Animate → CombatAnim Apply → Afterimages/WeaponPose → Rig Update → 近战判定；1040：锻造阻止快进；1067–1068：手光互斥。
- 1099–1125：法阵互斥、镜头反馈、准星/弱辅助与HUD provider。
- 1129–1160：Close(true)及可选ForceClose、战斗资源与事件清理。

NomiController：46排除回调类型，133–175移动/动画位移与地面截断，178–196一次性近战辅助，357–381 GridHit独立武器过滤。RuinsHUD：7引用，150 Boss避让时钟，160准星，174–187 PC战斗/探索按钮分流，225绘制CombatHUD。TouchControls：combat布局与顶排、取消动作保留摇杆、弓触点拖瞄、禁用/蓄力/阶梯绘制。

## 混合文件与所有权边界
Scene内还含其他任务的VoidRewind、GameSettings、DebugLog、天空云/光等未提交内容；Nomi内安全回溯、掌心/精确GridHit原逻辑仍保留；HUD/TouchControls原设置与版式逻辑未回退。不要把这些共享文件整份diff当成纯W2工作。工作区的DayNight/RuinsTerrain/TimeObject/ruins_main、云层光柱shader、LightGroup、回溯素材等均非W2交付，构建范围需Lead协调。W1/W3/W4在同工作区的combat/Forge文件也不属W2源码修改。

## 验证
`Lua54 all combat suites + LSP + git diff --check / PASS / /Users/xd/Desktop/体素test/validation/combat/w2/preview-ready-full.log`
18套离线回归（core7/anim1/enemy5/weapon5），24个运行Lua语法及最新文本LSP零Error，diff无空白错误；验证前后源码SHA256一致。W1旧10体积断言与Close(true) closing清理问题均已通过更新后的weapon_rig/weapon_forge回归。
v1不做设置界面、不做随机散布、不改角色shader闪烁；F6/F5为临时PC调试入口。

## 首次 Web 人工清单（全部未验证）
1. F7逐片段，左右/[ ]切换、空格暂停；看手臂/躯干/根位移符号与剑弧，片段预览不得伤人。
2. C拔刃、首次攻击取武器、静止回背、收刃隐藏；手掌挂点/换武器/手光与法阵互斥。
3. 三连、短/满重击、翻滚方向与岛缘截断、顿帧/无敌/击退、死亡安全复活。
4. 弓弱/中/满三档、箭抛物线/穿透/墙遮挡、自动晶箭非瞬发；闪避/换武器/菜单/失焦/取消/死亡/脱战弃箭。
5. 苔壳虫侧腹与翻身、哨灵石弹、石甲兽三招/破甲核心/半血狂暴；不把离线碰撞当真实接触通过。
6. G/触屏锻造：3D RenderTexture还是fallback、部件/颜色/应用、警戒/受击保留草稿、退出抬键保护。ForgePanel尚无公开模式查询/回调或规范日志，需W1补真实路径的 Forge preview: 3d|fallback，不可凭Open=true判3D。
7. 844×390、915×412横屏战斗按钮群、探索/骑龙切换不继承旧触点、摇杆保留、拉弓指拖瞄+独立看向指；原生TouchCancel传播仍独立未验证。
8. 两排5心、单普通血条、36dp Boss条/甲点/破甲提示、窄屏安全区、F5/F6；性能与设备帧率。
9. 解谜碎时蓄力/冻结/回溯、骑龙普通吐息/B大招、上龙强制脱战，保持原规则。
