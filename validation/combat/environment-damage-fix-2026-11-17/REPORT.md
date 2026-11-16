# 剑弓碎石不破坏：证据与有界诊断（2026-11-17）

## 当前结论

根因仍未确认，没有宣称已修好。线上 build 110 的实际 manifest 包含 combat/EnvironmentDamage.lua，资源 hash a12cb1b6；已经存在破坏模块，不能解释为整段功能没有构建。清单不是实际命中成功的证据，也不能证明玩家当前页面已重载这个版本。

代码核对：真实 Projectile worldHit 传入 EnvironmentDamage.Arrow；剑在 AfterPose 读取持剑 root/tip。共同路径为 Eligible → Cell → 原生单 volume ApplyDamage。明确保护时间物件、不可破坏体积、非世界图层；剑额外保护脚下与朝上的支撑面。南门堵路石堆 destructible=true、0.25m 格、材质142/143/144硬度1，按当前规则应可破坏，不能仅凭保护规则解释其完全不动。

## 本次修改

- scripts/combat/EnvironmentDamage.lua：细化拒绝原因，追加可选 trace sink；每个 kind/stage 在场景生命周期内最多记录一次，总计最多24条。记录无命中、不可破坏、禁用体积/节点、非世界层、时间物件、无持剑端点、无效体素、脚底保护、遮挡、进入原生删除、removed=0 或 removed>0。
- scripts/ruins/RuinsScene.lua：接入 WeaponVoxel 日志，含 volume id、destructible、layer、voxel、material、命中点/法线、cell世界中心、半径和removed值。
- 诊断 sink 用 pcall 隔离，失败不能改变游戏破坏结果。未改伤害/半径/坐标/碰撞/敌人/时间物件规则，没有广播删除兜底。
- tests/combat/environment_damage.lua：补充诊断去重、实际返回、拒绝不修改数据以及坏sink隔离回归。

## 验证

- FAIL python3 tests/nomi/run_offline.py：64套63通过，1项原有失败；完整日志 tests.log。唯一失败 tests/ruins/time_object_lifecycle.lua:35：component Dispose leaves world-owned render nodes; use RemoveVolume。基线复现见相邻 jump-grace-2026-11-17/baseline-failures.log。环境破坏与跳跃回归均通过。
- FAIL python3 validation/combat/environment-damage-fix-2026-11-17/lsp_check.py：本次修改0 Error；全量唯一旧错误 scripts/ruins/tests/TimeLifecycleTest.lua:275 Redefined local variable before。完整日志 lsp.log。
- PASS git diff --check（环境破坏相关文件）；日志 diff-check.log。

## 实测边界与下一步

Maker 构建后日志 watcher 恢复工作，当前收到的时间段主要为 SwingPerf，无实际剑弓命中错误，不能将“没错误”当作功能通过。专用 Chrome 游戏页要求 TapTap 登录，未重试用户已取消的登录接管、未绕过登录。

原 Windows「启动本地Runtime」会话已收到继续验证任务：使用官方 Maker 非交互原生 Runtime 检测真实体素删除，避免依赖桌面按键；待回报。该任务是已有跨设备普通会话交接，不是 Orca Worker 或原生子代理。

部署本诊断版本后，对同一可破坏石体挥剑并射箭，读取 WeaponVoxel 首次各阶段日志；优先根据真实失败阶段修复，不再用 mock ApplyDamage 全绿替代原生验收。
