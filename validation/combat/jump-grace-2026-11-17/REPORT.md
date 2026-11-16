# 平台边缘跳跃容错（2026-11-17）

## 交付状态

本地已实现，尚未提交、推送或构建；未修改云端工作区。用户提醒云端仍有进行中的改动，因此没有调用会自动提交云端改动的构建流程。
只读 fetch 时 HEAD 与 origin/main 均为 5c46d53eecf0e9b622162e0239d0ab18a0e707b1，0 ahead / 0 behind。仅证明已提交历史一致，不能证明云端工作区干净；当前插件只读接口未提供云端未提交文件清单。
发布前须核对云端进行中的 NomiController / RuinsScene 改动，按最新版本合并局部补丁，不能直接覆盖文件。

## 根因与修改

原 Move 仅在按下跳跃当帧 cc.onGround=true 时调用 Jump；没有离地宽限或落地前输入缓存，走出物理支撑边缘后按键直接丢失。

- scripts/ruins/NomiController.lua：120ms 土狼时间、120ms 输入缓冲。地面仍走原生 Jump；离地后的宽限起跳通过文档支持的 SetLinearVelocity 设置 Y=6.4m/s，保留 X/Z，不传送、不伪造 onGround。不改碰撞形状、支撑半径、步高和正常跳跃速度。
- 起跳消耗资格，观察离地再落地才能重新获得；起跳后的旧 grounded 帧不能触发二段跳。低顶棚阻止离地时，120ms 后确认仍 grounded 且竖直速度非正才允许重新按键起跳，不自动重试。
- UI/失焦/动作锁/下落攻击丢弃缓存；虚空回溯、调试传送、骑乘和上下龙重置宽限。
- scripts/ruins/RuinsScene.lua：传递 jumpAllowed，并连接骑乘/输入阻断清理。
- 新增 tests/combat/jump_grace.lua，执行实际控制器方法，覆盖30/60/120Hz、离边100ms与超窗150ms、落地前缓存/过期、禁止二段跳/自动连跳、低顶棚、输入阻断与重置。同步三个原有测试的方法加载依赖，不放宽原断言。
- 未改 ForgeShowroom/WeaponBuilder/WeaponParts/ForgePanel/UI/武器模型/天空改动。

## 验证（完整输出在同目录）

- PASS git fetch origin main：只更新远端引用，未 merge/pull；日志 git-fetch.log。
- FAIL python3 tests/nomi/run_offline.py：64套中63通过，1项原有失败；日志 tests-final.log。错误：component Dispose leaves world-owned render nodes; use RemoveVolume，位于 tests/ruins/time_object_lifecycle.lua:35。实现与测试均与 HEAD 一致，已用 HEAD 测试正文复现，见 baseline-failures.log。跳跃新增及受影响回归均通过。
- FAIL python3 validation/combat/jump-grace-2026-11-17/lsp_check.py：扫描全部 scripts Lua 与4个修改/新增测试，仅1个原有 Error；日志 lsp-final.log。错误：scripts/ruins/tests/TimeLifecycleTest.lua:275，Redefined local variable before。本次修改文件0 Error，原问题文件与 HEAD 一致。
- PASS git diff --check（本次修改的已有文件）：日志 diff-check.log。

离线测试的原生接口为 spy，不模拟引擎物理解算，不能证明真实原生起跳已成功或手感验收通过。没有启动 Mac 本地 Runtime，没有新版本 Web 画面证据。

## 后续 Web 验收

对齐云端并构建后检查：跑到平台边缘稍晚按跳仍可起跳；落地前轻点跳可接上下一跳；空中连按不二段跳；长按不自动弹跳；轮盘/失焦/骑龙恢复后无意外起跳；低矮顶棚下跳跃不会永久失效。比较正常跳高与原版一致，确认原生 CC 在宽限起跳帧不会再次贴地。

jump-grace.patch 为本次代码与测试局部差异，source-hashes.json 为验证时摘要。仅用于审阅/合并，云端有新修改时不得强制应用。
