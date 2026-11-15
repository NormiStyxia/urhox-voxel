# 合并后测试对齐

2026-11-15。只修改4个测试；运行代码、合并索引及其他WIP未改动，未commit/merge/reset/checkout/build/Runtime。

- /tmp/pxvenv/bin/python -I /tmp/run_all54.py / PASS：50 suites, failed 0 / /Users/xd/Desktop/体素test/validation/combat/merge-alignment/all.log
- python3 /tmp/all-lsp.py / PASS：ERRORS 0 / /Users/xd/Desktop/体素test/validation/combat/merge-alignment/lsp.log
- git diff --check -- tests/combat/core_hit.lua tests/combat/core_isolation.lua tests/combat/core_motion.lua tests/combat/perf_grid.lua / PASS / /Users/xd/Desktop/体素test/validation/combat/merge-alignment/diff-check.log

core_hit：一并提取实际MayIntersect与GridHit，提供局部bounds缓存及有效Node/Volume接口；断言native命中/过短距离不截断真实Grid、不走原生快路，包围球不相交时不进入trace。
core_isolation：注入UpdateAim/Puzzles.UpdatePresentation；故障与正常两轮均验证独立Base scope→Invalidate→新scope内CombatCamera/Aim/Puzzles/Sigils/HUD→End→Anchor。正常轮断言Aim读取修改后的最终相机和新revision，故障轮保留HUD/FX继续运行验证。
core_motion：按具名函数及顶层end提取Move/AssistMelee、SetCombatCamera/UpdateCamera/ApplyCombatOffset，移除中文注释作为提取边界。
perf_grid：按Component/Node绑定补IsEnabledEffective/IsEnabled及worldPosition，缓存计数改为真实Grid遍历次数，fallbackReason统一fullTrace，新增禁用volume/node均不进入DDA的断言，保留4096格装饰预算与游戏精确查询测试。

自查：没有放宽命中/距离、缓存失效、故障隔离或相机遮挡断言；只替换已经删除的EmptyOriginHit/原生快路假设。视觉与游戏Runtime未运行。
