# W4 近战/下落手感收尾（2026-11-16）

## 改动
- CombatMoves.lua：PLUNGE 可调常量 hover=.10、initialSpeed=6、terminalSpeed=12、accelerationTime=.25；解析积分输出帧均竖直速度，水平惯性保持，实际 onGround 唯一落地结算。2m/4m 理论触地 .3287/.4958s（不含 CC 帧延迟/引擎重力误差）。未增加射线、未改伤害/命中窗/100ms顿帧。
- NomiController.lua：仅已批准的 plunge 分支，读取 plungeVelocity.y，清除水平 want.y。
- AnimClips.lua/CombatAnim.lua：start 多键举剑、后收；保留结束姿态供 .08s 真正交叉混合。loop 用 plungeSpeed[0,1]、plungeTuck[0,1]（已有缓存离地 .4m 内）渐变俯冲/预收腿；land −.14m squash→+.015m回弹，原0.25s收招保持。−.14m为动画请求量，现有 GroundFeet 可上抬 root 防穿地，实际下沉幅度待Web核对。单段手臂，双肘默认关。
- 五段近战保留原不同轨迹，躯干领先 .02s；接触旋转改 smoothStep、末段平滑回收，保留第五关键姿态随动过冲。第三/五段举剑握点 x 从 .15/.18m 移到 .58/.62m，蓄力握点 x=.65m，避开头部。实际路径见 paths.json。
- CombatFx.lua 新增固定池；WeaponRig.lua 仅特效初始化、真实刃尖取样、命中/落地/取消/回收接线。复用 SampleBlade 的世界坐标结果，不每帧生成节点、材质、几何或 Lua 表。未改挂点、部件和锻造界面。
- CombatCamera.lua 下坠最多 +4° FOV，落地 .12s 收回；首呈现帧 −.03m 下压，.12s ease-out；弓缩放与表现开关保持。

## 预算与接线
- Rig:BeginSlash(combo,heavy)、ImpactFx(position,forward,plunge)、SetPlunging(on)，由 Moves 调用；HitImpulse 同步取 event.pos 发4点火花。没有改 Scene。
- 落地30槽：厚环1（.28s，半径.3→2.4m）、碎块14（.5–.7s、重力落地）、短暗裂纹6（.6s）、剑尖火花8（.12–.21s）、星闪1（2/60s白，随后.15s金色退暗）。第5段用前移椭圆波、同池碎石。
- 弧光24楔片，沿实际剑尖转动插值，单帧最多8子片，30Hz单帧跨208°保留旋斩方向而非最短反向；宽 .55/.55/.65/.70/.85m，寿命 .16s（旋斩 .20s）；新生暖白随后金，第5段金蓝混合。接触火花4，合计≤28/弧。下坠另3竖条；拖尾关闭只清理弧光/下坠条带，低画质仍保留落地反馈；隐藏/Dispose 全部清理。
- 元数据由 Maker generate_resource_meta 生成，未手写 UUID。

## 检查与局限
- anim_clearance：使用当前 NomiVoxelData quads/pivots、SLENDER 几何、最长剑刃与实际 Apply 后握点前.08m→刃尖对躯干/头/双腿 OBB。60Hz、零/正常淡入淡出、4种下坠速度、2种预收腿权重共5,024帧通过。初版查出35处头部相交；进一步从握点前.08m开始检测，发现反斩淡入胸前接触，已把起手控制点移到右前侧（.55,1.25,.65），全部修复。握点允许接触仅前 .08m；实际刃根距握点 .20625m、最长尖1.18125m。
- 28片段 dur/phases/events/motion/speedStat 与5段伤害/失衡/profile/冷却相对 a9a3b2e 完全一致，见 contracts.log。
- 600帧含反复落地的 mock GC增量70.348KiB（0.117KiB/帧，含 mock FromEulerAngles 构造）；逐帧更新1.125KiB/600帧；节点创建0，FX路径 Vector3构造0。原生内存/GPU未测，mock不能替代真机预算。
- 未运行本地游戏、未构建/提交。Web五点：正侧背穿模/衔接；2–4m下坠节奏；落地鞋底与 squash；厚环碎块短裂纹完整性；五段弧光区分/低帧清晰度/遮挡与帧耗。

## 最终门禁
- /tmp/pxvenv/bin/python -I -u /tmp/run_all54.py / PASS 54 suites, 0 failed / validation/combat/melee-feel-2026-11-16/tests-final.log
- python3 /tmp/all-lsp.py / PASS 0 Error / validation/combat/melee-feel-2026-11-16/lsp-required.log
- python3 /tmp/w4-lsp.py（原完整列表加全部新增文件）/ PASS 0 Error / validation/combat/melee-feel-2026-11-16/lsp-final.log
- git diff --check / PASS / validation/combat/melee-feel-2026-11-16/diff-check.log
- 代码自审 / PASS / validation/combat/melee-feel-2026-11-16/review.json（记录最终源文件摘要；视觉/原生性能仍未验证）
