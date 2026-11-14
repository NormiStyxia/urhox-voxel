# 掌心统一访问器第一步迁移（2026-11-14）

完成与开关无关的迁移；没有开启拆肘、改动模型数据、提交/构建或运行 Runtime。

- NomiController.lua:60：castSocket = nomi:HandSocket('right')，删除本地肩下 SpellPalm 创建和偏移复制。共享节点归角色所有，不修改/删除。HandPos（113）仍返回 castSocket.worldPosition。
- RuinsScene.lua:848 AppendHandDebug：F7 按左右 HandSocket.worldPosition 测量真实掌心。肩节点只作骨长起点，不再用 shoulder+RigReference 单段向量猜手点；旧模型显示单段长度，可选 forearm 存在时显示肘在躯干局部的位置和两段世界骨长。旧轨道状态不显示残留IK目标，但仍显示真实掌心。
- CombatMoves/CombatTest/Hit/HUD/Touch 中无需要迁移的直接肩骨挂点；本轮没有修改它们。
- 主场景仍显式使用原 NomiVoxelData，USE_ELBOW_DATA 仍 false。按“先做与开关无关一步”未把主场景改接 LoadVoxelData；将来统一开启前还需迁移该加载入口并重建实例。

新增 tests/combat/core_hand_socket.lua 执行实际 Nomi 初始化片段、HandPos、F7 函数，搭配实际 BlockCharacter/旧新体素数据，只 mock 原生 Node/Geometry：验证旧偏移一致、零肘角连续、弯肘后发射掌心随前臂移动、重复访问不创建副本、F7不写共享挂点、无开关变化。

## 其他 owner 待办（本轮未改）

- DragonRide.lua:254–255 SeatPose：仍只摆 arm_right/left，开启前由龙 owner 分别处理肩/肘，默认先肘零角；不把旧角度同时加到两段。
- DragonTest.lua:20/232：当前显式旧数据，统一加载入口需与主场景一并迁移。
- CombatAnim.lua:365–378、BONE_NAMES:16、快照/混合及 DebugSample：当前按肩下 socket.position 解单段，W4需迁移可选前臂与两段长度、IK；不能直接当肩→掌心。
- GateTargetTest.lua:137/156：肩到掌心“向前”的断言仍合理，不应把肩参考替换成掌心造成零向量；owner需增加两数据分支/弯肘/挂点连续验证。
- WeaponRig.lua:197–198 已见 W1 改用统一左右访问器；本轮仅核对，未覆盖。
- DragonStream.lua 未触碰；Lead 新加 breath.rings 判空已用普通吐息离线回归验证。

索引：owned-reference-index.log / other-owner-index.log。

## 验证

python3 validation/combat/juice/run_tests.py / PASS / /Users/xd/Desktop/体素test/validation/combat/hand-socket/combat-tests.log（26套）

python3 tests/nomi/run_offline.py --focused / PASS / /Users/xd/Desktop/体素test/validation/combat/hand-socket/elbow-tests.log（W7 原模型对照及双肘契约）

Lua5.4 dofile('tests/ruins/stream.lua') / PASS / /Users/xd/Desktop/体素test/validation/combat/hand-socket/stream-test.log

python3 validation/combat/hand-socket/lsp_check.py / PASS / /Users/xd/Desktop/体素test/validation/combat/hand-socket/lsp.log（3文件零Error）

git diff --check / PASS / /Users/xd/Desktop/体素test/validation/combat/hand-socket/diff-check.log

真实引擎 GateTargetTest、F7 实际渲染与骑乘未验证；未把离线通过称为运行验收。
