# R10 挥剑卡顿：玩法侧交接（2026-11-15）

本组实现已完成；最终整库门禁尚未全绿。没有 commit、build 或启动 Runtime。保留了音频、弓、相机、武器、云层等并行改动。

## 验证

- /tmp/pxvenv/bin/python -I /tmp/r10_targeted.py / PASS，11 suites / /Users/xd/Desktop/体素test/validation/combat/sword-hitch/targeted.log
- /tmp/pxvenv/bin/python -I /tmp/run_all54.py / FAIL，43 suites，11 failed / /Users/xd/Desktop/体素test/validation/combat/sword-hitch/all-final.log；首条 anim_spec.lua:283（并行弓阈值修改对应旧断言）。
- python3 /tmp/r10_configured_lsp.py / FAIL，1 Error / /Users/xd/Desktop/体素test/validation/combat/sword-hitch/lsp-final.log；CombatHUD.lua:126 的既有同名 enemy 局部变量（非本次 range/LOS 范围，未越界改动）。其余五个实现文件及六个新测试文件 0 Error。使用项目 scripts/.luarc.json 原有诊断配置、引擎类型库与配置握手后的 EmmyLua 0.23.1，未修改规则。
- git diff --check / PASS / /Users/xd/Desktop/体素test/validation/combat/sword-hitch/diff-check.log
- 手工 /review：修复了独立 SlideGround 查询可能借到旧缓存、重入 AfterPose 覆盖 contact 池、范围相切 AABB 浮点误拒绝；合并 slam 使用原有纯距离排序。复核记录 /Users/xd/Desktop/体素test/validation/combat/sword-hitch/review.log。

最早整库 42 suites / 0 failed 见 all-third.log；后续并行修改出现后，最终失败为 anim_spec / audio_spec / core_camera / core_free_facing / core_moves / core_projectile / core_selftest / core_stow / weapon_builder / weapon_rig / weapon_select_gesture。未修改这些断言迎合其他组的新行为，也不把之前绿灯当作最终整库绿灯。

## 精确文件

实现：scripts/combat/SwingPerf.lua（新增，官方生成 .meta）、scripts/combat/CombatMoves.lua、scripts/combat/Hit.lua、scripts/ruins/NomiController.lua、scripts/ruins/RuinsScene.lua（局部接线）、scripts/ui/CombatHUD.lua（range/LOS）。
测试：新增 tests/combat/perf_support.lua、perf_motion.lua、perf_queries.lua、perf_grid.lua、perf_timing.lua、perf_allocation.lua，均由官方 generate_resource_meta 生成 .meta；更新 core_motion.lua（相机源码提取匹配实际的“从当前 Grid”边界）、core_hit.lua、core_zone_values.lua、core_gc.lua、core_isolation.lua 的端口 mock／范围预算断言。

## #1 前冲

保留九点落脚、<=0.10m 子段、35°坡限、0.20m 台阶和<=0.02m 墙边二分精度。24 个墙体探针不删减，水平同直线子段借用整段射线最近命中距离；坡面／不同高度退回原来的实际探针。高度由标量选择，回调每控制器预绑定一次，落脚与墙体缓存只活在一次同步 ClipSlidePath 内（没有地形修改回调）。独立 dust/ground 查询永不使用旧缓存。

平地真实方法离线计数（ground + wall = total）：

| 位移 | 改前 | 改后 | 降幅 |
|---|---:|---:|---:|
| 0.04m | 18+24=42 | 18+24=42 | 0% |
| 0.15m | 27+48=75 | 27+24=51 | 32% |
| 0.30m | 36+72=108 | 36+24=60 | 44.4% |
| 0.70m | 72+168=240 | 72+24=96 | 60% |

>=50% 仅在上述 0.70m 长前冲样本达成，不能泛化为所有帧。二分最多三次；攻击最多八个子段/Update，剩余米数由 Moves.motionDebt 在后续有动作 dt 的帧补完；取消/新片段/碰墙清除，不在 hitstop 补位移。滑步保留完整 authored 2.2m，设置 24 子段防御上限（现有片段不会触顶）。

N:ClipAttackMotion(motion) 新增第二、第三返回 moved, blocked, remainingMeters；Scene 的既有 return 保留多返回值，Moves 已消费。C.ClipSlidePath 可选 maxSteps 参数，同样第三返回剩余米数。旧的仅取第一返回值调用兼容。

## #2 范围提示

局部边界 x/z 按角度、半径、索引缓存；每次从最新角色位置/forward 变换，不缓存世界边界。准备态四个验证点（最多8条射线），active 八点（最多16条），跨同帧重复调用共享硬预算；其余点明确隐藏，轮换抽样。Scene 的同射线缓存还核对起点/终点/mask/layer/过滤函数与只读区间 revision；虚空检查每次重做。

轻击 prepare 26→8 / active 50→16，重击 prepare 18→8 / active含slam 84→16。真实 StrikeZones 和 Hit 查询未减点。专项实际执行 Scene 的 LOS 函数，验证相机移动、mask/world scope 改变、虚空和预算耗尽不显示旧点。

## #3 GridHit

保留 ignored / emptyOrigin / timeTarget 原生异常修复和负向整数格面、棱角同时跨轴的 DDA。slab 不相交先返回 nil，不再提前 new VoxelRaycastResult；Slab/FirstCell/Next 改成模块静态函数，去掉每体积闭包。100 个不相交候选的结果对象分配 100→0，DDA 访问均为0。

N:BeginQueryScope()/EndQueryScope()：32 条固定缓存槽，精确匹配 origin/direction/maxDist/mask/world/filter；只读批次共享，默认无缓存。Scene 接入相机/HUD 与 AfterPose；每帧、每批次重置，Hit.Apply 前后 Perf.Invalidate()。引擎无公开世界 revision，所以不冒险把 Aim(Update) 与物理/地形变动后的 HUD(PostUpdate) 缓存跨阶段串起来；它们只能在调用方保证无变动的同一 scope 共享。跨阶段共享尚未实现。

GridHit(ray,maxDist,decorative)：装饰查询共享每帧4次 fallback / 4096 DDA 格 / 128体积预算；超限返回 distance=0 的遮挡结果，不缓存“预算拒绝”。真实接触/施法/相机 LOS 保持精确，**不受装饰预算截断**；记录超预算计数。为了不漏伤害/穿墙，没有对真实慢路径强行丢查询，因此真实慢路径仍可能形成峰值，需 Web 数据决定后续空间索引。

## #4/#6 缓冲与命中

Hit.Query(enemies,a,b,radius,skip,out?,pool?) 与 Hit.QueryZone(enemies,zone,out?,pool?,skip?,shapesByEnemy?) 支持调用方借用缓冲；QueryZone 先球/胶囊 AABB 粗排，再执行原来的精确区域测试。shape 缓存仅在一次 AfterPose 的 spin/slam 两个无写入查询间有效，每批清空；已命中 body 不阻止同敌人的 stone_* 独立 key。原有接触排序、每目标一次、弱点/可见性规则保持。

Scene controls、move options、HUD Query contact；Moves damaged、Play opts/params、两个 zone contact 池和形状表复用。真实 CombatAnim.Play 同步复制参数，池不可跨调用保留。enemy ApplyHit/Feedback 对外可保留的 info/result 仍创建独立快照，避免“优化”破坏引用语义；重入 AfterPose 在结算期间拒绝，异常解除保护后按原隔离边界抛出。调试木桩仅 dummy.debugHits=true 才打印。

单 contact QueryZone 离线 mock 2.3920→2.0795 KiB/次，少0.3125 KiB/次（out与contact）。mock Vector3 用 Lua table，不能据此认定原生热态每帧 <=2KiB；该总目标仍未验证。

## P0 埋点合同

默认 RUINS.combat.state.swingPerf=true；设 false 关闭计时/heap/log，预算仍有效。预建阶段 input/motion/QueryZone/HitEvent/recovery/GridHit/range，关联 attackId/combo/clip；记录 motionRays/rangeRays/substeps/gridCalls/fallbackReason/fallbacks/volumes/cells/gridBudgetExceeded/heapDeltaKB。

严格区分时钟：time:GetElapsedTime() 是帧时间戳及限频；Time:GetSystemTime() 静态类接收者测帧内毫秒（遵循R10 §4.1，不能用帧内不变的elapsed差值冒充耗时）。时钟回退丢样。阶段>=8ms或射线/fallback超阈值才打印一行，间隔>=0.5s；采样不建表/闭包、不写文件、不强制GC。heapDeltaKB 是全帧 Lua 堆净变化，含GC效果，不是累计分配或原生内存。

## 待 Lead / Web

1. 由相应并行组收齐弓/相机/武器/音频的新合同与旧测试，重跑全量；HUD 既有 shadow local 在本任务允许范围外，需负责人处理后完成 LSP 零 Error。
2. Web：确认静态毫秒钟帧内递增与单位；比较埋点开/关成本；冷/热轻击三连、重击 spin/slam、墙边/桥重建/岛缘、低帧率前冲余量与取消、hitstop音频/UI独立时钟。
3. 真机测整体帧 p95/p99/峰值和热态 Lua 分配；更长一次原生射线虽然条数更少，不代表对应百分比的耗时改善。检查轮换范围点是否过于稀疏/闪烁。所有视觉、手感、帧率改善均未验证。
