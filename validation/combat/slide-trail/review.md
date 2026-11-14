# 滑步首帧余迹接线复核

基线 5023270efac1a93d004dd1ef25bb4d2d1f6ab32b。

- W1 GetAfterimagePose、dodge_slide 剑/弓留影、SetTrail 清理接口已经在该构建提交中。
- Scene 1159–1170 的顺序符合契约；唯一 combatRig_:Update(dt) 调用，无需改共享 Scene。
- 原成功滑步入口缺一次 SetTrail(false)，现于 CombatMoves.lua:213（Play 成功后）调用；不安全起点、CD、取消窗口、动画拒绝均不会走到此调用。
- Scene 每帧按画质/战斗状态恢复 SetTrail；没有永久关闭，未改 W1 Rig。
- 新 core_moves 回归覆盖接受一次清理、地面/动画/CD拒绝不清理、前 .02s 无快照而 .04s 首份快照、后续不重复清理。
- 自查 diff：只改 CombatMoves 3 行与 core_moves 20 行。无共享文件冲突点，没有新增资源/meta需求。
- Lua5.4 全部 22 套 core/anim/enemy/weapon/audio 通过，LSP 两文件零 Error，diff --check 通过。
- 未提交、未构建、未操作浏览器；本修复不在此前 R3 实测的构建中。真实“攻击→滑步”首 .04s 余迹清除仍待下一次官方 Web 构建后观察。
