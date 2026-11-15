# 锻造 HUD 与 Q 相对手势交接

## A：证据与边界

已核对当前代码：截图所述横幅内容来自 RuinsScene 的 resumeHint→HUD.SetHint，三个技能钮来自 RuinsHUD 的 SPELL_BUTTONS；两者均在 RenderHUD 中绘制，M.Build 只挂一个自绘 Layer，没有独立 Label 或 QueueOverlay 副本。RuinsScene 没有 raw nvg 调用；它的 Banner/Say/目标也只是更新 HUD 数据。SettingsMenu、WeaponWheel、VoidRewind 是独立浮层，不生成这三个技能钮或这条 Pointer 文案。CanOpenForge 排除了设置/回溯/战斗，开 Forge 前会关轮盘。详见 render-audit.log。

ForgePanel.lua:709 PhaseValues 在 phase=open 返回 black=0、alpha=1，所以 HudHidden():968 必须为 true。Forge 的 Layer.Render:795 只把自己的绘制排到 QueueOverlay；UI/Core/UI.lua:1529 调用 HUD widget:Render，:1652 在所有 Widget 后执行 overlay queue。PushOverlay:1687 只控制命中优先级，透明渐隐区域会暴露仍在画的底层，不能替代 HUD 隐藏。

**没有本轮 Web 日志，不能证明截图的真实运行时唯一根因是 package.loaded 键失配。** 源码可确定的漏洞是旧绘制入口只认 package.loaded 的固定键，缺失/非同实例时静默继续绘制。也不能排除截图所跑资源版本不同。没有把离线模拟说成真实根因证明。

修复不再依赖该假设：Scene.OpenForge 直接把实际 require 得到的 ForgePanel.HudHidden 绑定给四个 HUD（SetForgeVisibility）；入口以直接 getter、rawget(_G,'FORGE_HUD_HIDDEN')、兼容 module getter 三者任一真为隐藏。没有独立计时或可见性状态。RuinsHUD 内外两个入口都守卫。每层首次隐藏输出一次 HUD: hidden by forge (layer=...)，不是每帧输出。Scene onOpen 仅一次输出 Forge: HUD lookup cachedSame=... getter=...，供新版本 Web 区分模块键问题。

**需 Lead 改 ForgePanel，Worker 未碰该文件：**

- 模块启动 rawset(_G,'FORGE_HUD_HIDDEN',false)，维护上一次已发布 bool。
- 保持现有 HudHidden/PhaseValues 的相位语义；Open、Update 相位推进后、Close/FinishClose 所有返回路径发布当前值。只有值变化才 rawset 并 print('Forge: hudHidden='..tostring(value))，一个打开周期的 true/false 各一次。
- 不能只在 Layer.Render/QueueOverlay 里写标志：HUD 已先渲染，会晚一帧。不可在 onClose 前漏清 false；强制关闭、异常降级及无后续 Update 的 Scene.Stop 也要清理。
- 没有生产端写入时，Scene 直接 getter 绑定仍能工作；全局后备通路的端到端日志需要上述配合后再 Web 验收。

## B：已确认的双重解锁原因与修改

原 Scene takeInput 调 pointer:SetBlocked(true)，PointerCapture.lua:69 进一步 Release('panel')，Scene release port 设置 MM_FREE/可见光标；原 WeaponWheel.Open:278 又显式写 MM_ABSOLUTE。两处均为主动解锁，而不是浏览器随机失锁。

现在 PC takeInput 只清玩法动作/拖动并跳过下一次 look，不阻断 PointerCapture 的捕获状态；Wheel PC Open/Retire 不写 mouseMode/visible/grab，也不请求锁定。原移动/攻击/镜头 blocked 门保持；补 Q-down 首帧门，避免 wheel 实例创建前相机先旋转。关闭尾帧/释放门也保持冻结。

Wheel 从 Input:GetMouseMove() 的 IntVector2 读相对像素，按 DPR 换算 CSS，累计虚拟方向并限幅；18×layout.size 死区内保持当前武器，区外使用现有 HitTest 的方向扇区。不会使用绝对 UI hover 覆盖桌面选择。Q-up 的 Confirm 消费当帧最终位移，GetFrameNumber 保证 Update/Confirm 不双加；Esc/右键优先取消，左键不确认。触屏点击/拖动/多指及原模式恢复保持。Web 若捕获丢失，一次日志 WeaponWheel: pointer lock lost...，取消且不重锁。

M.Draw、Labels、Layer.Render 源码与 HEAD 完全相同，未改选中底板或视觉。

## 验证与共享工作区

最终全量 tests-final.log：50/0。期间仅展示间并行修改曾在 forge_showroom.lua:255 失败，已保留旧 tests.log；对方更新后重跑通过，未修改其文件。targeted.log 覆盖真实 PhaseValues/HudHidden 开→半黑→展示→关闭→恢复、cache缺失/direct/global/module三通路、全部五个绘制入口零调用、120帧限频日志、实际Scene输入回调与相机门、相对方向/DPR/死区/最后帧/失锁与触屏。原生 Web 视觉和 pointer-lock 事件仍未验。

本任务改6生产文件（RuinsHUD、RuinsScene、CombatHUD、TouchControls、PerformanceHUD、WeaponWheel）和3测试文件（core_ui_alloc、weapon_wheel、weapon_select_gesture）。没改 ForgePanel/Glass/ForgeShowroom*、CombatMoves、触屏模块或动画模块。未提交、构建、启动 Runtime、操控浏览器。review.diff 仅包含本任务文件；review.log 记录人工审核。
