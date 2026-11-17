# Web 剑砍碎石：刀刃进入石体后的表面判定（2026-11-17）

用户再次反馈Web拿剑砍不动。此前Windows定向通过不能替代Web实玩验收。

## 现有Web证据

本机官方日志镜像已保存为runtime-snapshot.log。记录中的客户端时间11:44:01：sword / occluded / volume274 / destructible=true / normal=(0,0,0)，命中(-0.13616696,7.10595274,-52.3213387)，cell中心(-.125,7.125,-52.375)。11:44:05，同一碎石体积有carve-start→removed=1→native-return=0。因此已收到成功判定修复的日志，但存在内部采样点被表层阻挡的接触拒绝，不能归因于整段功能未构建。

日志是每场景每阶段去重，不能用次数推算成功率；拉取随后发生upstream MCP unavailable，旧记录不等于用户当前每刀情况，也不能凭一格成功反驳用户体感。

## 根因与修复范围

NomiController.TraceVolume 从实心格内开始时返回distance0/normal0。剑实际姿态和跨帧扫掠可能出现这种合法采样。EnvironmentDamage原逻辑向该内部点做遮挡检查，石体自己的第一层也会被当墙，整次切割取消。离线使用实际GridHit重现：旧HEAD失败，新判定通过，见focused.log。

仅修改EnvironmentDamage.Slice：遮挡首次命中仍为同一volume、它可破坏、表面法线有效、该表面格中心离当前真实刀段不超过原有radius时，改切这个暴露格，不切原先隐藏格。重新执行脚底/朝上法线保护，去重基于最终表面位置。不同volume、超出刀段接触范围、视线起点在实体内仍拒绝。没有扩大半径/伤害/每帧次数/每刀射线预算，不改弓、不改武器模型或动作。增加有界surface-contact诊断阶段。

## 验证

- focused.log：旧HEAD确定失败，新工作树通过；内部刀段、深埋刀段拒绝、不同可破坏体积遮挡、地面和嵌入视线起点保护；已有旋转/缩放/弓单格/连击/预算用例继续通过。纯Lua回归不等于Web视觉通过。
- tests.log：全量71套，70 PASS / 1原有FAIL（time_object_lifecycle.lua:35：component Dispose leaves world-owned render nodes; use RemoveVolume）。
- lsp.log：全scripts与相关测试检查；本次修改0 Error。全项目6处已有Error分布在WeaponRig、RuinsBuild、RuinsTerrain与TimeLifecycleTest，baseline-lsp.log确认对应文件与起始HEAD完全一致，未改这些其他会话文件。
- cloud-status.log / git-sync.log：起始云端main=f4729d2，cloud clean，无落后提交。本地天空未提交修改保留。

## 待验收

Web新构建需确认用户原碎石、当前站位与低帧率下接触改进，查看surface-contact与removed，以及前后可见切痕；不能提前宣布全部打不动解决。Windows只能提供额外的原生补测证据。
