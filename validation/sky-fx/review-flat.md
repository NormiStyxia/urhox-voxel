# 扁平卡片云自审

- 本轮只修改 SkyClouds.lua、SkyAtmosphere.lua（Probe）、RuinsCloud.shader、RuinsCloud.xml、云层文档及 validation/sky-fx。未修改任何 PNG，未操作 Git 索引/提交/恢复，未运行 Runtime/窗口或 Maker build。
- 对照 surface-shader.md、CustomGeometry/Material 类型声明、VideoScreen3D/ChunkMeshBuilder/SurfaceCustomLightScene 与 BayWater 的深度反投影范例检查 API。没有 CustomGeometry 第二UV接口，改用精确 RGBA8 pivot；+0.25 byte 防编码截断、shader round 解码。
- 修正 shader 位移的 CPU 剔除风险：每批2个退化保护三角形，实际扫73个偏航角全部在界内。高云/低云倾斜方向分开，双面绘制。
- 低/关闭路径零缓存读取与资源创建；Dispose 幂等；缺图和绑定失败为解析圆形卡片；缺XML可直接shader恢复，shader也失败则隐藏，绝不白块。缓存共享纹理不Dispose，只释放独占克隆材质/节点。
- 实际高档72卡/148三角/2批，中档36卡/76三角/2批；没有逐帧几何Commit。追加授权后的地面云影已改为同图集A纯色遮罩。
- check.py PASS：包含真实设置热切、600帧关闭、禁日志无format/print/probe、289时刻、资源失败路径、UV/RGBA8/边界；日志 check-flat.log。
- 独立 maker-lua-lsp 19680 对2个自有Lua Error=0，lsp-flat.log；共享19552曾缓存旧内容，没有采用其旧结果。
- flat_assets_check.py PASS：实际RGBA四格与色块/留边、现有meta、shader提取颜色插值均合法；flat-assets.log。已读取flat-palette-preview.png，符合三色平涂。此图不是Web/游戏截图。
- git diff --check PASS：diff-flat.log。
- 尚未覆盖：SurfaceShader真实编译，Web深度约定、透明排序、跨卡片交叉、正上方偏航/从另一侧观看、低云像底板、GPU透明填充/深度准备成本。需要Web目测与性能统计，不能宣称已验证。
- Lead已扩权：只改RuinsGround云影uniform/末尾采样分支，SkyAtmosphere一次绑定/生命周期；已同步validation/settings/sky-integration.lua mock与docs/游戏设置与画质档-2026-11-14.md单句云预算。地面材质其余逻辑未动。
- 复跑：天空check.py、设置sky_integration.py/quality_check.py/check.py全部PASS，日志为check-shadow.log/settings-sky-shadow.log/settings-quality-shadow.log/settings-check-shadow.log；同图集A/正负UV契约检查见flat-assets.log；最新LSP Error=0见lsp-shadow.log。检查了共享纹理不Dispose、关闭/Stop/替换旧地表清强度、失败不逐帧重试，不新增draw。
