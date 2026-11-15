# 云运动/云影自审（CPU 候选，2026-11-15）

最终范围：SkyClouds、SkyAtmosphere的云影/风段、RuinsCloud顶点、RuinsGround云影、RuinsGrassTuft云影，以及文档/验证。未提交、推送、构建或启动Runtime。共享工作区期间HEAD从efb8da9变为bd2affc（其他Forge UI提交）；本任务没有改变历史。完整status在start/end-status.log，其他玩法WIP保留。

研究先于运行修改写入云文档；读取UCAR云形成说明、GPL公开复刻的动态生命周期脚本、MIT三层云shader、CC0顶点云shader，只独立实现一般原理。没有导入这些资源/源码。

自审修正：

1. 整圈XZ平移在30分钟CPU图聚拢云朵；改成每片独立360m周期窗口，透明后回卷，保留t=0布局。
2. CPU表达式执行器曾将GLSL .a误读为Python内部数组属性，已更名内部存储，并增加vec4长度/初始alpha一致断言。最终t=0基线/候选覆盖与颜色一致。
3. 低太阳拉长遮罩可能采到图集格边内部，形成地面格缝；加边界归零的形变包络，格边仍采透明gutter。没有新导数或新采样。
4. 低档/冻结风的速度分量明确为0；位移保留/恢复与纹理异步加载生命周期验证通过。

已读最终motion-cpu.png及sun-shadow-cpu.png。清楚看到缓慢位移、错峰消隐、日夜云色保留；地面图仅是相同ALBEDO公式色块，不伪造实际PBR/草/建筑画面。自动视觉修订止于本轮，未宣称美术实机合格。

未解决/不扩大范围：真实GrassField无已验证云影入口，所以只为备用草接线；建筑未接。地面周期投影与天空共享风和形状库，但不是天球云片的精确投影，局部呼吸/重生不逐一投到地面。真实凝结侵蚀没有实现。透明层重叠、5Hz微步进、天顶切向、资源变体编译、黑屏、真实GPU成本需要新Web验证。

验收以gate.log、rotation.log、settings-quality.log、settings-check.log为准；它们没有GPU编译器或新构建。旧P0历史测试里“顶点完全不变”断言不适用于此次授权的运动改动；片元逐字不变仍强制检查。

回滚只选本任务云风/云影hunk；不要整文件恢复SkyAtmosphere，否则会删掉同期夜火/萤火虫挂接。新资产0个，现有图集/材质xml/meta不改，无待生成UUID。
