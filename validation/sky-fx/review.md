# /review — 离线实现复查

范围：owned-files.txt，RuinsScene 仅本 worker 的 require/New/Update 三行。工作区其他会话同时修改的 VoidRewind、NomiController、TimeObject、ruins_main、TouchControls 等均未修改、未归属本任务。

复查结果：无未解决的离线代码阻断项；真实渲染验收仍待 Web。

- 发现并修复：密集数值面表触发 LSP 索引推导错误；改为明确命名顶点/面函数，实际法线绕序测试通过。
- 发现并修复：光柱太阳 yaw 的 x 方向最初反号，已改为 atan(direction.x,direction.z)；顶端朝向与太阳反方向一致。
- 发现并修复：粒子生命周期/透明度帧时间不一致；现固定 6 秒，6 秒归零，预算48/96。
- 发现并修复：shader 材质加载失败可能 nil:Clone；云使用基础材质兜底、光柱禁用，mock缺失材质测试通过。
- 平台能力：Web/mobile 高档也不会开启真实体积雾；仅桌面compute可开，quality off立即关闭所有新氛围特效。
- 单独开关：七项有效；关闭Bloom强度保留ACES合成，不调用Bloom Enable=false。
- 阴影：新云/光柱/粒子均不投影；关闭preset自动级联以确保手动距离/级数生效。
- 昼夜：捕获节流和下半球配色未回退；原DayNightTest节流fixtures通过。
- 云/粒子：云无逐帧顶点重建；新Update没有Vector3构造或table创建；浮光传送清空、单批固定上限。
- 资源：9个新增Lua/shader/material资源均通过官方generate_resource_meta生成元数据，没有编造UUID。
- Shader：地表新增分支置于所有导数之后；云影不处理岩底；所有新shader为上层SurfaceShader，无底层GLSL/Technique自造路径。

已知而非离线阻断：假光柱仅深度遮挡、不算云/建筑内部真实投射；云影只到RuinsGround，不到草叶/建筑；透明填充、shader编译、低档阴影外观、真实GPU draw pass数量未验证。详细Web清单在交付文档。

## 追加设置契约 /review

本节取代首轮24/18朵等旧预算描述，以最终GameSettings.PROFILES为准。已检查真实GameSettings和SceneQuality的接线。

- high24云/8光柱/80浮光，medium12/3/28，low0/0/0；高档1440云三角和32光柱三角，均来自实际构造mock计数。
- 全关首次加载不建效果；关掉/降档显式Dispose旧节点/独占材质/粒子效果/程序纹理，重新开启才生成；重复相同profile不重建。
- 初始ConfigureScene只设置照片级基础光照；skyfx注册回调只管理大气，不写共享阴影/Bloom/SkyCapture，避免重置菜单独立覆盖。
- Web/mobile所有档位和volumetric override均禁止真实雾；shadowOn=false也关闭；DayNight关闭雾时不分配散射颜色或写雾强度。
- 所有新输出与DayNight初始化日志都是DebugLog.enabled外层门控；关日志时600帧+质量切换中print/format/probe调用断言为0。
- Stop注销quality/probe并释放实例；重复Stop安全，后续settings Apply不复活旧场景。
- 缺GameSettings/DebugLog：pcall失败回落高档，Web依然不启真实雾。
- 运行时模型与GC/GPU驱动显存并未验证。共享ResourceCache和renderer池不是本模块独占，不能宣称禁用后驱动显存即时归零。

check-settings.log、lsp-settings.log、diff-settings-check.log为最终追加证据。

## 最终集成复核（2026-11-14）

- 最新并行接线将 SetQuality/SetFeature 转交 GameSettings；复核并更新测试契约，不回退这些改动。clouds 是总开关，lowClouds/cloudShadow 为子开关，单项覆盖经 Resolve 持久保留。
- SetQuality("off") 在有设置模块时为全局 low 别名，明确开启的覆盖仍有效；无设置时关闭全部独立大气。测试分别覆盖二者，不把 low 加明确覆盖误称全关。
- 真实 RegisterQuality 包装记录注册/Apply 顺序，skyfx 均早于全部 SceneQuality 回调；阴影/postfx 的独立覆盖未被天空开关重置。
- Probe 包含预算与实际开关状态；Stop 清除 scene/ground 直接引用，已销毁实例不随后续设置重建。
- Lua5.4/mock 最终通过；maker-lua-lsp 检查7个Lua Error=0（仍有非错误级静态告警）。Web视觉、shader编译、真实显存与帧率未验证。
- 最终证据：check-integration.log、lsp-integration.log、diff-integration-check.log；之前日志仅为历史检查。
