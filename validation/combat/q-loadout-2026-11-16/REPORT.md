# Q 统一装备选择（2026-11-16）

用户要求：把 Q 切换修正一起做。基于此前已确认的剑 / 弓 / 时间能力共用轮盘方向，此次只修切换与输入归属。

## 行为

- 徒步时无论当前是剑、弓还是时间能力，按住 Q 都打开同一个三项轮盘；移动方向选择、松 Q 确认。取消与同项确认保留原选择。
- 时间项名为「时间法器」，复用现有手部施法表现，没有新增法器模型或将 time 传入只支持剑弓的 WeaponRig。
- 敌人警戒、受击、闲置 6 秒不再自动更换玩家选择。时间状态可以在敌人仇恨存在时保留。受击动画、施法受击锁、死亡/骑乘限制仍有效。
- Q 不再施放回溯；回溯改 R，数字 3 保留。E / 2 冻结、左键 / 1 碎时保持。任务说明、目标提示、HUD、手机键盘映射、菜单/虚空回溯释放锁同步更新。
- 手机原顶部收放入口改为「切换」，在时间状态也能打开三项轮盘；交战仇恨不禁用它。布局坐标和轮盘绘制未改。
- 切换取消旧的弓蓄力、待发箭、挥砍命中及法术蓄力；关闭淡出和按键释放保护继续有效。
- C 保留为时间能力与上次物理武器之间的快捷切换，也经过相同动作限制；不再是使用 Q 的前置步骤。
- 不新增全局切换 CD，移除主场景旧的收刃后 1 秒施法等待。保留已有武器切换动作时长和不可取消窗口、法术自身冷却。
- 未扩展法器普攻伤害、冻结敌人、近战后的冻结 CD、轮盘暂停或减速。此次没有调整技能射程数值。
- 锻造仍沿用既有入口条件：时间能力状态、无仇恨、其他动作/菜单不阻塞；没有重做锻造工作流。

## 关键文件

- `scripts/combat/CombatState.lua`：主场景显式选择模式、GetSelection、仇恨/闲置不换装、时间能力受击锁。旧默认配置仍供独立调用者使用。
- `scripts/combat/CombatMoves.lua`：SelectLoadout 统一入口；保留物理武器原 Swap 和首次攻击拔出流程。
- `scripts/combat/WeaponSelectGesture.lua`：可注入选项、读取当前选择、执行选择，保留既有手势/关闭流程。
- `scripts/ruins/RuinsScene.lua`：三项轮盘接线、所有模式 Q、R 回溯、手机入口、时间状态的受击动画。
- HUD / TouchInput / TouchControls / SettingsMenu 只更新相关提示、按键和输入门禁；未修改 ForgePanel、ForgeShowroom、WeaponBuilder、WeaponParts 或模型资源。

## 验证

- PASS：`/tmp/pxvenv/bin/python -I -u /tmp/run_all54.py`，57 套 / 0 失败。完整日志 `full-combat.log`。
- PASS：`python3 /tmp/q-loadout-lsp.py`，ERRORS 0。日志 `lsp.log`、`lsp-server.log`，包含本次所有修改的 Lua 文件及新增测试。
- 定向回归 7 套通过，日志 `focused.log`。新增 `tests/combat/loadout_selection.lua`；扩充实际 Scene + WeaponWheel + Gesture 组合测试，覆盖时间态 Q 开启、三项逐个选择、真实延迟 onClose、仇恨/闲置、弓取消、动作锁、受击/死亡/骑乘、手机 R 与 Q 分离。
- `core_routing.lua` 验证真实 HandleSpells 的 Q 不施法、R 回溯及错误选择提示。
- `git diff --check` 与精确提交范围检查在提交前执行，日志 `git-check.log` / `commit.log`。新测试 .meta 使用官方 generate_resource_meta。
- 全量回归后，武器会话新增 ea70015，仅涉及武器生成器/展示模型/美术，没有覆盖本次文件。补跑 `tests/combat/forge_wing_sword.lua` PASS，日志 `concurrent-wing-check.log`。
- 没有启动本地 Runtime。PointerCaptureTest 与 HUD 原生截图夹具同步了新按键，但本轮没有宣称原生 Web 指针锁或截图验收通过。

## Web 重点验收

1. 刚进入游戏不按 C，按住 Q：出现剑 / 弓 / 时间法器三项，第一帧拖鼠标不转镜头；松开确认。
2. 剑→弓→时间法器各切一次，再试右键取消、原项确认；关闭后移动/攻击应恢复，开关轮盘不误射或误施法。
3. 被怪追时选择时间法器，确认不会马上被自动切回剑；此时 E / R 可继续对合法时间物件施法。受击硬直期间不能施法。
4. 持剑静置超过 6 秒：可以背挂，但当前选择仍为剑，左键仍进入近战，不会突然变成碎时。
5. 手机时间状态点顶部「切换」进入同一轮盘；回溯按钮只触发回溯。菜单、失焦、死亡、骑乘时轮盘正确退出。
