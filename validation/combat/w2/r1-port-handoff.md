# W2 动画 R1 接口复核

2026-11-14。只做代码与离线检查，无 Runtime/构建/提交。

已确认默认20Hz量化；正常战斗每帧 GetMotion(animDt, realDt) 单次推进，Apply 后每帧 GetAfterimages 传给 Rig。普通片段结束不 Stop(nil)。修正起身后接闪避会误清保护尾段：现在仅停止被取消动作，独立保护事件在 .60s 关闭。测试覆盖 .45s 起身完成、.56s 保护仍在、.61s 关闭，以及顿帧时闪避无敌/受击免疫按正常时间流逝。

追加 Nomi GridHit 独立武器排除回调：装备、刀光、留影、方粒即使错误设为非零 collisionLayer，也不截断射线。实际 GridHit 离线模拟覆盖原生返回武器后仍找到更远墙体；保留原普通射线快路径。

Scene 订阅 EnemyAttackCue，复用 M.combat.enemyCue 保存最新事件，DebugLog 可观察；不播放声音。退出时注销。

r1-port-final.log：7 core + anim_spec + weapon_rig + weapon_forge 通过；3个本轮Lua语法与最新文本LSP零Error；git diff --check通过。W1已更新20体积断言，且 Close(true)现已可强制清理closing会话，前轮这两项阻碍已解除。

仍需协调：SettingsMenu接辅助瞄准/伤害数字两开关；spread基础散布规则；ForgePanel实际3d/fallback路径没有公开查询/回调，也未打印要求的 Forge preview: 3d|fallback，需W1在实际路径处追加日志，不能仅凭 Open 返回true猜成3d。

本轮修改：CombatMoves / NomiController / RuinsScene 与 core_moves / core_hit / core_routing。共享文件只局部追加战斗钩子。所有 Web 视觉/手感/native TouchCancel/性能仍未验证。
