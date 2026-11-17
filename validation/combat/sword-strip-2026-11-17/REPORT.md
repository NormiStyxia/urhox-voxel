# 剑的横向连续切带 — 2026-11-17

## 用户确认
横向连续削切，下缘避开脚底；保留脚底/隔墙/弓单格保护。

## 现象与根因
Windows 在 cd234dc 的实测是第一刀27格、同位置法器46格；靠近后的第五刀20格、法器44格。脚底保护把半径缩成 .4825/.3575，使低处第五刀反而更弱。另旧横向目标在法线方向向内偏移、从玩家脚点+.9发射，实际表面交点向中央收拢；实际格中心被用作下一颗球心，导致采样不连续。

## 改动与边界
生产只改 scripts/combat/EnvironmentDamage.lua；没有改动作/武器模型/锻造/UI/天空。
- 0.50m 半径的重叠球组成浅横带，间距0.45m；普通7个候选，重击/第五9个候选。名义宽度3.7m / 4.6m，厚度相同；不是广播胶囊/盒形伤害。
- 下缘保留脚点以上0.16m，按2倍噪声半径保守计算。低接触时适度抬高整个切带，最大0.40m，不缩掉横向宽度；过低接触仍拒绝。
- 球心固定在最初石体表面坐标系。逐候选从玩家发射射线，穿过准确的横向表面目标再沿同一视线延伸；只接受原volume且在原表面0.40m浅层内、候选球内的可破坏格。每次原生损伤后重新查询，不读缓存grid/追逐新碎块。
- 保留初次真实刀刃接触、支撑面/脚底/距离/遮挡/材料硬度/时间物件保护，power仍为3；弓原来的单命中格逻辑完全未改。
- 每挥刀只1次burst/1次聚合反馈，首接触后候选阶段每球至多1条可见性射线。全挥刀36条预算保留；几何回归的有效刀总9/11条以内。未宣称原生毫秒性能通过。

## 验证结果
PASS 两种半径边界(1x/2x)下真实Melee入口+GridHit离线回归 — focused.log。
以0.25m整块石体测试低位第一刀(1.125m)/第五刀(.875m)：普通边界删97/119格，连续核心66/90格；最坏2x边界删346/536格，脚底整排仍完整。核心断言覆盖2格深×3格高×整段横向，不仅看总格数。
同高位新鲜几何：剑89/法器98/第五107，名义宽度3.7m/4.6m。以上全为Lua适配器数字，不能替代Windows/Web实际石体结果。
PASS 整排地面/头顶保留、隔墙不伤后方、弓单格与退役、重复帧不重复破坏、同步回调移除原volume后不读旧grid、原生返回0的事件成功判据 — focused.log。
FAIL python3 tests/nomi/run_offline.py — offline.log；72 PASS / 1既有FAIL：time_object_lifecycle.lua:35 Dispose leaves world-owned render nodes; use RemoveVolume。
FAIL python3 validation/combat/sword-strip-2026-11-17/lsp_check.py — lsp.log；5项既有Error：RuinsBuild/RuinsTerrain world/scene注释、TimeLifecycleTest重复before。本次改动文件0 Error。
PASS git diff --check — diff-check.log。

## 尚未验证
- Windows真实南门石体的连续切口、第一刀/第五刀与同hit法器的Removed事件比较。
- 原自然第五刀远站位无接触：本次不改动作轨迹/站距，不承诺把no-contact变成命中。
- 原生GridHit/LOS成本与截图外帧时间；之前17–24ms不能凭离线射线预算判修好。
- Web真实输入和可见网格；没有用单张图或mock宣布最终通过。

## 并行与发布
本机他人的SkyAtmosphere/sky-fx以及未跟踪目录全部保留。
两次官方cloud-status返回 fetch failed；插件动态工具目录也没有独立cloud-status接口。目前无法确认云端正在编辑的内容是否已经提交，因此没有调用会自动提交云端脏改动的构建入口。本次先本地独立Git提交；Q轮盘的f248c31仍随当前分支保留。待恢复云端只读状态后，再同步/构建并进行Windows真实复验。
