# 近战改向交接（2026-11-15）

已完成普通加速跑、五段轻击、下落攻击。未 commit/push/build，未启动 Runtime。云层/昼夜/画质等并行 WIP 保留。

## 验证

- /tmp/pxvenv/bin/python -I -u /tmp/run_all54.py / PASS：50 suites, failed 0 / /Users/xd/Desktop/体素test/validation/combat/melee-refresh/final-reviewed-all.log
- python3 /tmp/all-lsp.py / PASS：0 Error / /Users/xd/Desktop/体素test/validation/combat/melee-refresh/final-reviewed-lsp.log
- git diff --check / PASS / /Users/xd/Desktop/体素test/validation/combat/melee-refresh/final-diff-check.log

分阶段 gate：stage1-all.log 与 stage2-all.log 均为 50/0；对应 stage1-lsp-final.log、stage2-lsp.log 均 0 Error，然后才进入下一阶段。自检修复：保留触屏按钮 Draw.Button/charge 绘制；空中弓输入不被剑的下落分支拦截；真实桥面接地不因 terrain height 缺失而拒绝；实际落地接招以真实 0.25s 判断，不随 hitstop 延后。最终全量已覆盖这些修复。

## 1. Shift 普通跑

- 删除两个旧动作、DODGE层、专用位移/无敌/冷却/奖励/接招状态、短长按分类与WAIT_RELEASE、旧动作相机和声音触发。
- FootLocomotion 缩为 held-run 姿态协调，不再拥有距离积分。Nomi:Move 在探索/战斗都使用7.2m/s目标和k=12平滑；松开回普通速度。攻击缩放优先，蓄力不会被Shift加速。跑中攻击可接上，无额外根位移。
- sprint_loop、实际位移步频、八个真实鞋底点与root接地补偿保留。手机按钮改为按住“跑”，两种徒步模式摇杆满推均可跑。SampleRun(out,keyHeld)、SetGamepadRun(down) 只处理 held；龙dash独立。
- State移除旧设置和keepPose专用分支；F7、帮助和HUD更新。受击后的0.8s免伤、起身保护等独立防护保留。

## 2. 五段连击

唯一分段表 AnimClips.Combo / ComboLength=5，CombatMoves.COMBO_LENGTH读取它。前三段旧时间、位移、伤害不变。

| 段 | dur / active | 路径角 / 位移 | 范围半径/角 | 伤害/失衡 | hitstop |
|---|---|---|---|---|---|
| 4 旋斩 | .58 / .16–.30s | 340° / .55m | 2.1m / 340° | .85 / 1.6 | .06s |
| 5 终结劈 | .69 / .22–.34s | 200° / 1.00m | 2.2m / 150° | 1.9 / 2.3 | .09s |

第四段 .34s 可接招；第五段 hit_off 后至少真实 .35s 禁止新攻击，后续回第1段。其它段最后接触后 .75s 连段过期。任意段在可接招时都可转重击/蓄力，旧重击不变。每段独立六姿态、路径IK、事件与范围；角色根朝向不由动画旋转。全段profile数据和事件持续交给现有敌人消费者，新增spin/finisher来源仍遵守特殊结果优先级。第五段借共享池冲击环；whoosh复用素材按段pitch，不创建音频资产。F11遍历五段，并使用实际命中而非仅事件判定通过。

## 3. 下落攻击

- 持剑战斗空中离地≥.6m按攻击，plunge_start(.12s)→plunge_loop→真实触地plunge_land(.25s)。普通空中弓输入保留。
- Nomi:MeasureMotion写地面高度缓存，CombatAirState(out)读取物理支撑、Terrain.GroundHeight与实际速度，无新增Aim/GridHit/物理射线。桥面使用实际接地高度，空中近支撑点保留该高度；离开已知支撑且无地形时保守拒绝。
- 保留触发瞬间水平速度，朝向锁定；CC SetLinearVelocity 的竖速为−18m/s，未直接移动角色Node。镜头无额外旋转。
- 落点半径2.4m、360°、垂直[-.3,1.5]圆盘，QueryZone/LOS/每目标去重结算一次。伤害=基础攻击×1.6×min(2.2,1.4+实际下落高度×.1)，失衡×3、破甲×2；profileId=plunge、tier=heavy、combo=0，100ms顿帧。落地真实 .25s 后可攻击接出。
- 空中受击/虚空/回溯/骑龙/菜单取消清待落地状态，无迟到伤害。真实触地才冲击；保留可受击性。
- 固定朝下的bladePath抵消躯干倾斜；三clip均无水平motion。落地也用真实鞋底接地补偿。共享六槽尘石冲击环、heavy+stone现有声音组合、合成punch上限.03m。

## 文件与范围

运行文件：scripts/combat/{AnimClips,CombatAnim,CombatMoves,CombatAudio,CombatCamera,CombatState}.lua；scripts/ruins/{FootLocomotion,NomiController,RuinsScene,RuinsHUD}.lua；scripts/ui/{TouchInput,TouchControls,CombatHUD}.lua。

为删除悬空调用还最小清理 scripts/combat/CombatTest.lua 的旧F11动作场景，以及 scripts/combat/WeaponRig.lua 的旧动作专用残影分支；不改武器几何/挂点/模型数据或敌人行为。tests/combat 中原有相关套件更新并增加五段/落地边界断言；未新增Lua文件，因此无新.meta。主方案§7/§18/§22/§23/§24、移动端规范与帮助同步。

## 残留与性能

完整清点 references-after.txt：scripts两条、tests一条，仅是复用的 cmb_dodge_land.mp3 音频路径（运行/断言各一）与 StoneSentry.lua:89 历史注释（按边界未改敌人文件）；无旧动作、输入、冷却、免伤或设置的可执行引用。docs 14文件147条为历史设计/调研文字；主方案/移动端开头明确当前合同，指定章节已更新，研究原文未覆写。

保留R10的≤.10m子段、9点支撑、8步/帧余量平摊、LOS预算和完整GridHit语义。新增动作复用已有动画缓冲、音效声源和粒子槽；离线100次落地环使用同一组池槽。现有 info/result 独立快照与原生Vector/Quaternion边界未改，不能把mock固定池测试称为全链路零Lua分配；热态≤2KiB/帧和设备帧时仍需Web采样。

## 待 Web / 真机

普通跑起停与触屏按钮安全区；第四段旋斩轮廓、第五段节奏/前冲/重感；空中剑尖朝下、水平惯性、桥/坡/台阶接地与脚底不穿；下落冲击环/音量/镜头舒适度；真实攻击峰值帧时与分配。所有片段仍标“符号待 Web 校准”。
