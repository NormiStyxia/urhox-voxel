# W2 §19 战斗表现接线（离线交付）

基线 HEAD：b2cb7a7491128903b5b2791eabac43797b8b54a9。未提交、未构建、未启动本地 Runtime；没有操作浏览器。上一阶段滑步结果见 ../slide/HANDOFF.md。

## 本轮修改

- scripts/combat/CombatMoves.lua：8 槽复用 HitEvent；32 组有界 swingId 包络，群攻取最大、不重启；实际命中音效与材质、第三段/重击层；普通箭不震玩家；满蓄弱点箭例外；弓取消/释放停止拉弓音；动画事件驱动满蓄/拔收刃闪光、滑步起停音。空挥声从片段 active 边界前 .02s 派生，不产生 HitEvent。W1 Flash/SetCombatVisual 接口已接且兼容缺失方法。
- scripts/combat/CombatState.lua：cameraShake/cameraFov 默认开，bowZoom 默认关；无设置 UI 改动。
- scripts/combat/Hit.lua：保留 material/part/broke/staggered/weak 与扣血前 hitStop，避免丢失敌人复用结果。
- scripts/combat/Projectile.lua：箭与晶爆共用 arrow:n；保持 12 槽，墙/敌体插箭 .8s；优先挂实际部位骨骼，无骨骼时跟随 hurtShape；死亡/破甲/禁用部位清除。保留三档、满蓄穿透及实际伤害晶爆倍率。
- scripts/ui/CombatHUD.lua + scripts/ruins/RuinsHUD.lua：.12s 延迟 + .25s 追赶损血条，连续受击不延后；实际命中准星角收拢 2dp，弱点延亮 .10s；draw_full 一次性 .18s 满蓄提示；沿用 2× 像素图与逻辑 DPR。
- scripts/ruins/NomiController.lua：5m 战斗/6.5m Boss 相机模式，70:30 焦点 .25s 混入；输入优先、不改 yaw；弓肩偏移增量 .30m、.18s 混入、可选 FOV -3；特效后再次遮挡检测，不写回平滑跟随位置。
- scripts/ruins/RuinsScene.lua：音频 New/Preload/Update/Dispose 与 EnemyAttackCue 路由；玩家/木桩共享 W3 粒子池且不重复敌人粒子；预建 12 箭×(1箭杆+4短尾)节点、共享2材质，尾长 .42m、插箭无尾；低档32粒/关闭残影与FOV，普通档64粒；F2 震动、F3 FOV 独立开关。只消费 GameSettings 已有质量接口，不改其文件。
- tests/combat/core_{moves,motion,projectile,routing,support}.lua：统一命中/包络/音效取消/HP追赶、实际相机方法、部位插箭、事件路由及独立调试键测试。

Scene 首轮行段（续接以 integration-line-map.log 为准）：36–39 新依赖/质量标记；360–373 敌人声画事件；387–394 单份粒子消费；418–514 初始化/箭池/音频/质量；619 进战预载；861–872 F2/F3；1046 音频实时时钟；1156–1169 Rig 事件接线；1247–1283 构图/包络/准星目标；1305–1306 释放音频与质量回调。Nomi：91–96 新模式、134 输入优先、311–365 相机方法。

## 最终接口对齐（续接已完成）

- 按 Lead 最终裁定，W3 在 ApplyHit 成功结算内负责敌人反应/粒子；W2 复制其最终结果到统一 HitEvent，不再要求 OnHitEvent/deferPresentation 新接口，并已删掉可选双播路径。
- Scene 直接借用 Spawner:GetParticlePool()，每帧只 UpdateOwner 自己的 owner。退出前 ClearOwner，绝不 Release 借用池引用。玩家受击/木桩/箭撞墙使用新表参数，真实敌人不重复 Emit。箭撞墙事件每池槽复用且只触发一次。
- W1 GetAfterimagePose 与剑/弓 dodge_slide 残影已落地；Scene 顺序改为 GetWeaponPose → SetSwing → GetAfterimagePose → SlideAfterimages → SetAfterimages → Rig.Update，采样为当帧姿态。独立射线排除也涵盖新增 bowImages 和 flashes。
- W5 接口已完整核对；弱点音传 critical/weakpoint 获 +2dB，与重击层共用 hitId，危险末音 tier=danger；仅消费 EnemyAttackCue，不订阅 onEvent。
- 两个此前接口依赖已解除，可由 Lead 安排 Web 预览。CombatAudio.lua.meta 本轮检查仍缺失，官方资源元数据由 W5/Lead 在构建前补齐；W2 没有自造 UUID。

## 验证

Lua5.4 21 combat suites / PASS / /Users/xd/Desktop/体素test/validation/combat/juice/integration-final-tests.log
emmylua_ls 14 W2 files / PASS / /Users/xd/Desktop/体素test/validation/combat/juice/integration-lsp.log
git diff --check / PASS / /Users/xd/Desktop/体素test/validation/combat/juice/integration-diff.log

全套包含 core/anim/enemy/weapon/audio；LSP 零 Error。相机与动作均为离线 mock，不是引擎运行验收。review.log 是自查记录，final-version.log 是最终工作区范围。

## 共享文件冲突点

Scene/Nomi 中原 VoidRewind/GameSettings/云光接线保留；本轮仅局部加入战斗逻辑。未改 W1 武器/锻造、W3 敌人、W4 动画、W5 音频实现，也未改任何天空/地形/着色器/设置文件。工作区它们仍有并行未提交修改及 audio 资源，不能把全工作区差异视为 W2。没有新增 Lua/资源文件，因此 W2 不需要新 .meta；音频模块/素材 .meta 由对应所有者核对。

## Web 尚未验证

- F9 三连/第三段/重击/破甲：同一挥击多目标不叠震，空挥只有挥击声；F2/F3 互不影响，墙边镜头不穿、不累积漂移。
- 弓弱/中/满：普通箭不震，满蓄弱点轻震；短尾不成激光、敌体插箭随部位转动；满蓄长持只闪/响一次，菜单/失焦/滑步/切武器取消无射击和残留拉弓声。
- F8 虫/哨灵/Boss：材质命中、前摇/危险声、倒地落地声、死亡/胜利时序与血条历史层。
- 5m/6.5m 构图、70:30焦点和鼠标优先是否舒适；弓肩偏移、手光互斥与解谜态相机不变。
- 复查滑步四向/弓残影、拔收刃/满蓄小闪；真实多指/TouchCancel 仍需手机。
- 音频首次浏览器解锁、首击延迟、声部上限与CPU/GPU增量须Web取证；不声称性能预算达标。
