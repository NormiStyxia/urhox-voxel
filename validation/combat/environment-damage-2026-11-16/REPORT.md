# 剑削切 / 弓单点 / 碎时范围破坏

日期：2026-11-16。用户确认：“剑削一片、弓单点、法器范围碎时；近战别每次都挖地。”

## 实现范围

- 新增 `scripts/combat/EnvironmentDamage.lua`，沿手持剑的真实 bladeRoot/bladeTip 采样；不借用对敌扇形范围批量挖地。
- 普通四段削切半径 0.24m，第五段和重击 0.32m。每挥最多 4/6 个接触点、每帧最多 2 次原生破坏、含遮挡检查最多 36 条射线。命中停顿、原地重复回调不继续钻孔。
- 脚底上方 0.15m 再加两倍破坏半径作为安全带；拒绝朝上的表面（normal.y > 0.55）。下落/落地攻击只保留原有伤害与特效，不删地面体素。
- 箭在真实飞行命中时，用精确体素中心、最小世界格长的 0.2 倍半径调用单体积 ApplyDamage。命中格删除后箭退役，不悬在空气里；瞄准预测只读，不挖洞。蓄力档不扩大环境破坏范围。
- 剑/箭只作用于已有 destructible 且属于碰撞层 1 的普通物件；地形、主体建筑、时间物件及其冻结/回溯碎片保持原保护规则。力量 3，尊重材料硬度。
- 原生连通性检查仍会让失去支撑的结构掉落；“箭一格”指直接削除的一格，不承诺断开连接的整块石头永远悬空。
- 时间法术的原有范围碎时、冻结、回溯及机关逻辑未改。没有实现统一轮盘、法器普攻、冻结敌人或切换 CD。

## 接线与保护

- `CombatMoves.AfterPose` 在敌人结算后发起环境接触，保留原有敌人伤害/窗口。敌人回调导致取消、死亡或替换动作时，不再使用旧接触姿态挖掘。
- `RuinsScene.CombatCast` 增加第二返回值（精确世界命中），仍是纯查询。箭池与近战通过独立适配器进入新模块；刀光质量开关不影响几何采样。
- `SwingPerf` 新增 VoxelSlash/VoxelArrow 分段，写入世界前后失效 GridHit 查询缓存，避免同帧命中过期体素。
- 未修改 ForgeShowroom、WeaponBuilder、WeaponParts、武器模型、ForgePanel 或其他 UI。并行会话的未提交改动不纳入本次提交。

## 自动检查

日志均在本报告目录，`*.log` 按项目规则忽略，不随提交上传。

- 定向用例：`tests/combat/environment_damage.lua`，使用 lupa.lua54 独立 LuaRuntime 执行，PASS；日志 `focused.log`。
  - 4 种体素尺寸 × 3 种缩放（含负值）、旋转后的精确箭命中、旁格保留。
  - 30/60/120Hz 削切、射线/破坏预算、重复回调、地面/承重面保护、穿墙遮挡、下落不挖。
  - 实际 Projectile 飞行与初始箭长扫掠、敌人优先遮挡、命中后退役、预测只读。
  - 实际 CombatAnim → CombatMoves.AfterPose：五段/重击、前摇/收招、取消、敌人回调取消、低帧跨 hit_on/off。
  - Scene 只读取手持刀刃坐标，背挂剑不参与破坏。
- LSP：`python3 /tmp/environment-damage-lsp.py`，PASS / ERRORS 0；日志 `lsp.log`、`lsp-server.log`。
- 工作区初次全量战斗：`/tmp/pxvenv/bin/python -I -u /tmp/run_all54.py`，55 套中 2 失败；日志 `full-combat.log`。失败位置为正在被并行修改的 `forge_showroom.lua:789` 与 `weapon_forge.lua:167`。不能将此结果表述为工作区全绿。
- 遗迹补充：lupa.lua54 逐个独立运行 `tests/ruins/*.lua`，5 套中 1 失败；日志 `ruins.log`。interaction、stream、dragon_collision、detail_geometry 通过；time_object_lifecycle 报 `component Dispose leaves world-owned render nodes; use RemoveVolume`；在未修改的 a2badf2 基线复现相同失败，非本次引入。
- 基线对照：a2badf2 原代码的 forge_showroom / weapon_forge 均 PASS；time_object_lifecycle 复现同样失败，日志 `baseline-comparison.log`。隔离基线脚本/测试后，仅覆盖本次 6 个源文件与测试文件；assets、只读 urhox-libs、历史 sword-hitch 测试夹具复用原路径。全量战斗回归 **55 套 / 0 失败**，日志 `isolated-full-combat.log`。最初隔离副本缺少资源/引擎库/历史夹具，补齐后重跑通过；没有修改或跳过测试。

- `git diff --check` PASS，日志 `diff-check.log`。新文件编码、尾随空白、末尾换行检查通过。

- 最新集成回归：武器会话提交 c9817e0 / 6ae808f（与本次文件不重叠）后，重新运行全量战斗，**56 套 / 0 失败**；日志 `integrated-full-combat.log`。上述两处锻造临时失败已随该会话提交消失。时间物件的独立旧失败仍保留证据，未修改其实现/测试。

## 真实运行的证据边界

- `.maker/logs/runtime/runtime.log` 不存在。现有采集状态最后成功时间为 2026-11-16 02:10:33（Asia/Shanghai），lastWrittenLogs=0。没有据此宣称运行无报错或 ≥8ms 帧为零。
- 离线测试使用真实 Lua 查询/动画/战斗逻辑，模拟原生 ApplyDamage；不替代原生碎块、碰撞重建、噪声边缘、GPU 和帧耗验证。
- 低帧跨过整个 active 窗口时保留一次当前刀刃接触，不是完整连续旋转 CCD。实际五段切痕连贯性待 Web 看。
- 没有启动本地 Runtime。新 Lua 文件的 .meta 由 Maker 官方 generate_resource_meta 生成。

## Web 验收

1. 靠近南门普通堵路乱石，对其侧面挥剑：应沿刀路削掉小片；前四段与第五段/重击强弱可辨，但不一刀炸空整片。
2. 同处反复普攻、重击、跳起下落攻击：站脚面应保持，落地仍有环/碎屑特效而不产生脚下弹坑。背挂剑、开菜单或取消攻击后不继续挖。
3. 用箭射普通乱石：点中哪里削哪里，一箭直接删一格；贴墙放箭也不重复破坏。只瞄准不松箭不改变石头；不可破坏墙仍挡箭。
4. 对比碎时原有范围破坏；对时间机关做碎裂→冻结→回溯。剑/箭不能绕过机关的时间状态管理。
5. 快速五段连击和连续射击后观察卡顿；如有 SwingPerf，重点查看 VoxelSlash/VoxelArrow/GridHit 的 ≥8ms 记录及 Environment.Melee/Environment.Arrow 隔离报错。
