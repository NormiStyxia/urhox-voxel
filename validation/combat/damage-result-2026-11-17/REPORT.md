# 剑弓破坏成功判定兼容（2026-11-17）

## 已证实的问题与边界

Windows 既有「启动本地Runtime」会话原生实测：普通石体被 ApplyDamage 删除一格，API 却返回 0。实际 Projectile → RuinsScene → EnvironmentDamage 链路也能删除一格，但原成功判定失败，箭仍 active/embedded。碎时删了112格却提示“太坚硬了”。这不是“完全没构建”的证据，也不能独自解释所有肉眼看不到破坏的情况。自然 WeaponRig 挥刀、可见切痕仍待 Windows 后续验收。

该会话 D 轮事件探针在 HEAD d53dbd58e1be7072cd68c3a5395adabb63a608c0、UrhoX main fefb855f4 / binary 1036010 完成。通过官方 maker_validate，原报告 PASS，60帧，0框架断言；结论另来自探针日志。事件在原生调用返回前同步发生：

- 单格：512→511，原返回0，VoxelDamaged.Removed=1。
- 硬度4 / power3：未删，无伤害事件。
- 静态/动态最后一格：Removed=1；本轮未观察到立即销毁体积。
- 切断支撑：伤害事件Removed=1，随后Severed分离10格；原体积减少11，世界总数只少1。因此不能用原体积总数差冒充删除数。
- 范围命中两个体积：分别Removed=8和8，原返回0；范围真实删除共16。

原始证据在 Windows 工程 `.maker/validation-evidence/073ad5d6-f54d-49e0-b499-e9f191888815/`（runtime.log / validate.json / probe-readable.log），由该会话提供；本机未复制原始文件。此前 B/C 完整场景报告的 DDS/着色器失败仍保留，不能当成完整视觉通过。

## 最小修复

- 新增 `scripts/ruins/VoxelDamage.lua`：在单次调用栈内收集同 world 的同步伤害事件，指定体积调用还匹配 Volume 身份；读事件标量，不缓存或回读旧 grid。原生异常也恢复嵌套作用域。事件数优先；没有事件时保留文档规定的原生返回值。
- 借用 RuinsPuzzles 已有 GateDamaged 回调转发，不重复注册同一世界事件，也不替换城门进度监听。
- EnvironmentDamage 的单体积删除、TimeSpells 普通体素范围删除使用该结果。弓退役、剑命中反馈、碎时成功判定沿用原有下游。
- WeaponVoxel 的 removed 阶段输出真实事件计数；与原生返回不同时另输出 native-return 阶段保留原始值。
- 不改变伤害功率/半径/次数、TimeObject保护、脚下保护、遮挡保护；不修改武器模型、锻造UI或云端剑动作。

## 并行改动

从233035f安全快进至云端d53dbd5，保留 AnimClips 新五段动作；原有三个天空修改文件同步前后SHA256一致。日志 git-review.log / git-sync.log。

首次推送被云端 RuinsScene.lua 未提交修改保护拒绝。没有覆盖或代提交云端文件；撤回本任务在该文件上仅用于追加日志字段的改动，诊断留在EnvironmentDamage，修复仍由独立模块与既有事件桥接完成。后续提交不包含RuinsScene.lua。

## 验证与待验收

初次修改后65套离线测试64 PASS / 1原有FAIL（time_object_lifecycle.lua:35）；全scripts LSP仅1处原有Error（TimeLifecycleTest.lua:275）。日志 tests.log / lsp.log。

同步云端动作后：全量 **55 PASS / 10 FAIL**，日志 tests-synced.log；LSP仍仅同一处原有Error，日志 lsp-synced.log，本任务修改文件0 Error。新增的9项动作测试失败均已在独立临时目录以 `git archive HEAD scripts tests` 导出的纯云端d53dbd5原版复现（未带本任务修改），错误与当前工作区相同，详见 cloud-baseline.log。涉及 anim_clearance（208处剑/身体相交）、anim_spec、core_camera、core_free_facing、core_melee_zone、core_moves、core_selftest、core_zone_values、perf_queries；不得称全量通过，也未为变绿修改断言或覆盖云端动作。

新增回归覆盖：原生返回0但实际删格时箭退役/剑反馈/碎时成功，硬材质仍拒绝；world/volume隔离、多体积范围、嵌套调用与异常恢复、无旧体积方法访问、真实GateDamaged转发。离线双替身不能替代原生端到端验收。

待验收：部署后Windows同步修复提交，验证真实事件桥接、弓active=false、剑反馈与碎时成功，以及自然rig五段接触和ready之后的画面。Web仍需对用户原来那块石头实击，不能把这次成功判定修复报告为全部“打不动”已解决。
