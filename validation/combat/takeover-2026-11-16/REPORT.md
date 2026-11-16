# 战斗手感接手复核（2026-11-16）

基线：`a2badf2`，战斗实现为 `397d7a5`。已完整阅读战斗手感交接、近战与下落研究、melee-feel 验证报告。

## 当前日志证据

- `.maker/logs/runtime/runtime.log` 不存在，无法检查当前 Web 的运行报错、SwingPerf ≥8ms 记录或特效告警。结论为 UNDETERMINED，不等同于无报错。
- `state.json` 最后成功拉取为 2026-11-16 02:10:33（Asia/Shanghai），lastWrittenLogs=0、consecutiveFailures=0、lastError=null。watcher.out.log 尾部连续返回 0 条并记载 watcher stopped；watcher.err.log 为空。本轮没有重启已停止的采集器或本地 Runtime。
- Maker 状态：项目已绑定，Git/Python/LSP ready。只读查询 `get_debug_feedbacks(fetch_and_mark_processed=false,status=0,limit=5)` 仅返回 11 月 13 日反馈 49346，早于本次战斗实现，没有新的下落/五段动作/跑步反馈。未标记已处理。

## 离线复核

- `/tmp/pxvenv/bin/python -I -u /tmp/run_all54.py`：54 suites，0 failed；覆盖 `tests/combat/*.lua`（不含 support/mock），并非全仓所有测试。证据：同目录 `tests.log`。
- `python3 /tmp/w4-lsp.py`：ERRORS 0，退出码 0；覆盖交接 `/tmp/all-lsp.py` 的固定清单及 CombatFx、feel_fx、feel_plunge、anim_clearance。证据：同目录 `lsp.log`。不是全仓动态扫描。
- 原生帧耗、GPU、实际 Web 动作和特效画面仍未验证；离线通过不能替代这些验收。

## 本轮决策与待验收

没有当前错误证据或新用户反馈，保留已上线参数；未修改游戏代码、武器或 UI，没有提交、推送或重复构建，仅保存本复核证据。

下一次 Web 验收需保留对应运行日志：
1. 从 2–4m 高处下落攻击，观察悬停→加速、触地鞋底/回弹，以及环、碎块、裂纹、星闪；低画质再看一次。
2. 连续打完五段，从正/侧/背观察穿模、衔接，重点看第 4 段整圈弧光和第 5 段金蓝终结波。
3. 持续跑步，检查前倾与起步滑行；低帧率时同步核对 SwingPerf ≥8ms 行，区分日志 stage。

未决事项：本版 Web 的实际视觉反馈，以及可与本版对应的运行日志尚缺。拿到证据后再按授权范围修复，每次代码改动完成测试/LSP后提交构建。
