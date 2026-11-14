# 浮背 / 滑步 Web 验收（2026-11-15）

本轮只验收，没有改源码、构建、提交或启动本地 Runtime。40 张截图均经实际查看；没有录屏，这些图片不能证明连续动作平滑。

## 结论

浮背方向与静态姿势可供审美评审：剑柄朝上、刃尖朝下；弓斜挂、弦在靠身体的一侧。C 进入战斗未攻击、W 跑步和已执行的单纯 Shift 结束后仍为背挂，没有强制举手。实际重击结束后日志约 .385 秒转 idle，截图可见回背。

不能整体验收通过：真实 Web 的 F11 完整一轮 **12 PASS / 6 FAIL**，三连三个段和短/满蓄重击伤害全部为 0，另一个 FAIL 是三连汇总。四向滑步、取消衔接、三档箭和弃箭通过该实机自测。另发现 F7 的数字视角键串到解谜提示，遮挡头肩；页面左下“修复错误”从 1 增至 5，当前控制台 error 查询为空，远端日志也没有相应堆栈，原因未定。

验收中原游戏页突然消失。再次查询同一 external 浏览器只剩 about:blank（browser-end.json），我没有重开页面、切换 backend 或操作其它会话。最后一轮鼠标与 Shift 已释放，所有此前按住的 WASD 也均已有 keyUp；原页面已被关闭，无法再在原页执行额外释放确认。未恢复一个新会话冒充连续验收。

## 版本与采样边界

- 本地 HEAD：a99b8c2b7084e201d24f5637375fb93a7f07a087，父 a1853e0，见 git-state.txt；官方回执 ../maker-build-a99b8c2.json。
- 浏览器：Cindy external / Cindy-real；初查只有并行云研究 Bilibili，无游戏页。新开独立 combat-dodgestow-review 标签，未动云研究页。原 target CBA39D67685A529CB6649B07D8DFAFF9。
- 页面 00:32:56 开始导航；新场景 00:33:40 ready；只提取本轮 00:32–00:45:59 的日志。watcher 后来出现 00:46:16 / frame 99 的新场景记录，归属不明，已排除。
- F7 实际出现新增“O 持手/背挂”，以及新剑弓背挂，证明载入了本轮功能；浏览器没有暴露 Git SHA。pak 请求过滤结果为空，不能据此声称对每份远端资源做过哈希核验。精确网页 SHA 标为 UNDETERMINED。
- Git 中并行云贴图/validation 改动原样保留；本次只新增本目录证据。

## 有效图片（建议先看这 6 张）

1. `/Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/07-sword-close-back.webp`：F7 背视角、O 背挂，柄上尖下。
2. `/Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/17-bow-back-clear.webp`：F7 弓斜背挂。
3. `/Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/18-bow-side-clear.webp`：侧视确认弦朝身体、与背部有间距。
4. `/Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/10-slide-forward-087-side.webp`：前滑 t=.087、侧视、浮背，胸部前压。
5. `/Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/13-slide-right-087-front.webp`：右滑 t=.087、正视、浮背。
6. `/Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/35-real-left-slide-exit.webp`：正常操作重击回背后左滑、结束仍背挂，手臂自然下垂。

补充：03 是真实 C 后初始背挂；21 是真实 W 跑步；23 是真实 Q 后弓背挂；25 是真实无方向 Shift 后弓背挂。F7 前滑采样顺序为 14(t=.020) → 10(t=.087) → 15(t=.253) → 09(t=.320)，是不同时间点的暂停截图，不是连续视频。11/12/13 分别是后/左/右 .087 帧。

## 检查记录

本地 git show/status / PASS / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/git-state.txt

页面新功能版本特征 O 背挂 / PASS / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/07-sword-close-back.webp

远端资源精确 Git SHA / UNDETERMINED / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/REPORT.md

正常进场与本轮 Lua/native 异常检索 / PASS / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/runtime-current-sanitized.jsonl

Shader 无告警 / FAIL / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/runtime-errors.txt — `opaque material has no deferred pass because of: POSITION`（此前日志已有同一资源告警；不是新战斗 Lua 错误）。

C 未攻击背挂、手光互斥 / PASS / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/03-sword-back.webp

W 跑步保持背挂 / PASS / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/21-bow-run-back.webp（实际为剑，文件名是操作前意图，见下文）

单纯 Shift 执行及结束仍弓背挂 / PASS / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/25-shift-real-post.webp（日志 00:41:01 dodge_slide start，00:41:02 finish）

剑/弓静态背挂方向 / PASS / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/18-bow-side-clear.webp

急转/走跑中所有披风头腿穿模 / UNDETERMINED / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/REPORT.md

F7 四向暂停帧、前滑分阶段采样 / PASS / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/10-slide-forward-087-side.webp

F7 视角键与解谜隔离 / FAIL / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/12-slide-left-087-front.webp — 数字视角键后出现“无法使用时间之力”卷轴，遮住头肩。

真实四向 Shift 完整视觉录像 / UNDETERMINED / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/operations.json（手动无方向/左/前有 start 日志，右/后尝试未可靠捕获；F11 四向为真实引擎合成输入，不能替代全部手动观感）

F3 镜头开关与连续柔顺度对照 / UNDETERMINED / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/operations.json（已按开关，截图频率不足以评估 .32 秒包络）

重击结束约 .4 秒 idle/回背 / PASS / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/runtime-combat.txt（00:43:21.102 finish → 21.487 idle，实测 .385 秒；图35可见背挂）

正常轻击连续输入/回背中重按不漏 / UNDETERMINED / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/REPORT.md（远程 80ms 按压仍被延迟成长蓄；F11连段事件完整，但不是人工回背重按边界测试）

F11 完整实机自测 / FAIL / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/f11-results.txt — `END complete pass=12 fail=6`，`sword_light_1 FAIL hit_on=0.1000 damage=0.000 hits=0`。

F11 滑步四向/取消接攻击 / PASS / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/f11-results.txt（四向2.2000m；取消1.9200m；后接攻击.2200秒）

F11 弓三档命中与取消 / PASS / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/f11-results.txt（速度18/30/44，伤害4/8/14.4；取消shots=0）

人工按住弓瞄准与松手恢复 / PASS / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/30-bow-hold-zoom.webp（与31对照，画面明显放大/恢复；日志full箭一次；没有测量实际FOV数值与0.1秒参数保持）

C/Q 重复切换最终单武器、探索隐藏 / PASS / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/runtime-combat.txt（23弓、32剑、33探索隐藏；未逐帧覆盖切换消隐窗口，不能证明全程无双影）

Q锁内Shift/骑龙/死亡/菜单焦点全部形态过渡 / UNDETERMINED / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/REPORT.md

浏览器“修复错误”计数来源 / UNDETERMINED / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/40-bow-cancel-back.webp（计数5，console-error-snapshot.json为空；未打开错误面板前游戏页消失）

原验收标签持续可用 / FAIL / /Users/xd/Desktop/体素test/validation/combat/dodge-stow/web/browser-end.json — `tab not found: CBA39D67685A529CB6649B07D8DFAFF9`，只剩about:blank。

## 对失败的最小候选处理（未实施）

1. **W2：优先定位近战零伤害**。F11 已在安全地面准备站位、判定窗口触发，不能用“只是漏按”解释。当前证据尚未定位到 Zone/LOS/目标列表/测试朝向哪个环节。建议只加诊断：每段记录人物/木桩位置、hitForward、zone范围、候选数量和遮挡拒绝原因，先重现再修；不要直接扩大范围或绕过判定让测试绿。测试中先S后F11、身体与原镜头方向相反，值得特别复测正向/反向站位，但还不是已确认根因。
2. **W2：F7隔离解谜快捷键**，预览有效时视角数字键不要继续进入时间法术输入；F7专用视图隐藏底部通用Pointer提示/操作按钮，可露出髋与脚，方便审美判断。
3. **平台/输入待定位**：“修复错误”计数随几次点击锁鼠标增加，console error无记录，可能与Pointer Lock拒绝有关，仅为候选，不能定责。下轮先打开计数详情取原始堆栈。
4. **W4审美观察**：前滑侧面在.087有可见胸压，后滑同时间更接近直立；左右姿势差别较克制。静帧没有明显手臂举起，但落脚被底部UI部分遮挡，连续蹬地与退出跳帧需录屏/更密集取帧再判断。
5. **W1审美观察**：静态剑/弓方向符合要求，侧视背部间隔可见；本轮不据此宣称高速转身下无穿模。

## 证据使用注意

图片名为采集前计划，实际内容以图为准：02已自动脱战；04/20/21实际是剑；19/22/24/26/29/33/38是探索；32不是攻击帧，只是切换后剑背挂；34是重击过程；39/40实际是剑蓄力→滑步取消→回背，不是弓取消；真正弓瞄准/释放是30/31。保留原始文件不改名、不删除，避免掩盖失败的取证尝试。

F11首次在门前因木桩没有安全空地而拒绝（BEGIN FAIL no safe dummy location），随后真实S移动离开门边后才成功开始完整一轮。自测是页面现有F11入口、真实引擎运行，不是离线mock；它自身含调试准备站位，不能当作徒步走到敌人场地的证据。没有JS改玩法、传送注入或伪造触摸。没有测Web性能，也没有声称听到音效。
