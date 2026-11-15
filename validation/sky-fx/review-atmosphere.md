# 2026-11-15 动态云 / 雾光 / 柱顶夜火自审

本轮是未构建候选。不是原神官方技术，不是体积云，不声称解决历史黑屏或 GPU 性能问题。

## 基线与研究证据

开工 HEAD 34913982687401b46d884a86c35b08a9249d5236；baseline 文件、SHA 与当时的并行 Forge 差异已保存在 atmosphere-baseline。没有修改 Git 历史或同步仓库。DayNight 字节不变；Scene 只有 Build.Build 后一行 SetPillarLayout，见 atmosphere-review.log。本轮 Chrome status/tabs 只读返回正常外置 Chrome、唯一页 about:blank/t1064；没有开新页、刷新、抢键鼠或假称看过新游戏画面。

实际阅读并复看 xuetao-research.md 以及 7s、11.8s、13.5s 已保存视频帧：该参考的宽底/高塔、浅蓝暗面和细金边优于当前图集的球团感。本轮保留已认可的调色和自有图集，主要解决静止感；不声称重新雕塑后已达到参考精细度。

| 来源 / 实际读到的文件 | 许可 / 证据 | 可迁移的一般方法 / 本轮取舍 |
|---|---|---|
| [xuetaolu/URP_ASE_Tutorial](https://github.com/xuetaolu/URP_ASE_Tutorial)，精确目录与 vert/frag/common、材质、GenshinDynamicCloud.cs、场景、mask 通道见 xuetao-research.md | GPL-3.0；commit 0df750e2722a5d43781f980c751ff98288b31a3b；第三方游戏纹理权利链不明 | 多通道云形、方向透射、低幅 UV 扰动、分层运动。独立实现，未复制代码、mesh 或图片；不照搬 Unity 强制远面 |
| [krzmig/godot-simple-sky-project](https://github.com/krzmig/godot-simple-sky-project)，README、LICENSE、完整 sky.gdshader | MIT，shader blob 7a74a8454fc96b505b53b8c8ba7a256892cc1883；原始回执 atmosphere-krzmig-*.json | 三层不同速度/方向制造形变、近地平线融合。没有搬 5-octave cubic noise 或 Godot quarter-res pass；改为有界正弦风和单次图集采样 |
| [AlexStrook/UnlitClouds](https://github.com/AlexStrook/UnlitClouds)，README、LICENSE、Assets/__CLOUDS/Cloud_unlit_vertex_color.shader 的 vertexDataFunc/surf/tessFunction | CC0-1.0，shader blob a39968770cf577c432016db1337ee95d200d350e | 顶点色保留人工主明暗、世界坐标慢速多尺度扰动。其 Unity target4.6 距离细分、三平面采样不适合当前 Web 预算，不移植；只借鉴分离宏观运动和表面细节的原则 |

上述 JSON/TXT 是研究证据，不是运行依赖。自有 shader 无复制的第三方函数。

引擎核对：lua-scripting-guide；surface-shader 顶点空间/矩阵/透明/导数/Unlit/材质失败契约；rendering 的 LightGroup/Zone/点光；sky-and-environment-lighting；lights-and-shadows；volumetric-fog；post-processing；deferred-scene-weather-lighting。读示例 25 自定义光场景、29 程序天空、30 pelican-bike atmosphere。现有 FloatingMotes 已使用 ParticleEmitter；项目没有可复用的火焰视觉资源，只有名称含 fire 的弓箭音效，因此独立程序化火焰，不新增纹理/粒子池。未更改引擎、管线配置或库。

## A：世界方向的动态云

保留 world_vertex_coords → 固定球面方向 + 相机位置 → 引擎一次 view/projection；不使用 VIEW/INV_VIEW、scene_depth 或全屏代理。world yaw 风由两个低频项叠加，三层 COLOR.r 的 .25/.45/.65（实际顶点 UNORM8）控制速度；缓慢改变方向，最大角速度约 .00030rad/s，约 .017度/s。时钟周期 10000π 秒，各频率整周期，无 wrap 跳跃。初始角/UV 都是 0 偏移。

单图集的一次采样前增加相干 billow：cell 内最大 .006/.003 偏移（高图约3.1/1.5像素），不是透明度 erosion。gutter 抑制格间串色；fwidth 把小于约40像素的云细节退到0，约125像素以上为全强度。高/中系数1/.5，低0，低的 uniform 分支跳过扰动。仍无噪声图、无额外纹理指令、无 CPU 顶点更新。云运动开关冻结 elapsed，开回继续；不把时间归零造成跳位。

自审另修了热切换相位：宿主在Dispose前保存云elapsed，新档/重新开启继承它，避免增强漂移后切档把云突然转回初始角度；原档位自身的数量/布局差异仍保留。数值测试覆盖高→中→低与关闭→开启。

CPU 同机正式数据对照 atmosphere-cloud-motion.png：四个时段/方向，每行旧t300、新t120、新t300，含高空俯视。初始帧逐像素相同；t300云可见水平位移，内部明暗保持。没有新增脏点/厚白边，但仍能辨认重复的八格轮廓，且远处形变被刻意弱化；不伪称解决全部美术问题。CPU 图不含实际后处理、压缩纹理或 GPU 导数。

四个384×216 CPU视角的纹理调用计数：平均 .540–.793/pixel，p95 1–2，最大2；之前平均 .563–.795。只是这些视角的覆盖/采样代理，不是 GPU 时间或所有角度上界。高档保守上界24张重叠覆盖，不能拿本次最大2当全局保证。新增每顶点约2个sin，每有细节片元4个sin、5个smoothstep和fwidth/少量算术；低档uniform分支是否被后端展开仍待GPU确认。

## B：复用雾与辉光，光柱增加缓慢光带

距离雾保留 DayNight 的地平线色和80..100至240..300m范围；新增 atmosphereFog 同时控制深度/高度雾。高度雾高度-12m、falloff .12不改，高/中密度 .009/.006、晨昏最多乘1.18，低关闭高度雾、仍可保留距离雾。5Hz设置，不新建雾材质或全屏pass。单独只开雾时静态状态仍有效，动态密度需宿主active更新；未把新大气接口强行变成总是更新。

Bloom 已存在：保持固定曝光、ACES、阈值1.2、高强度 .35/weight .12；中/低默认0，但原独立 postFx 覆盖继续有效，不关闭承担tonemap的合成pass。它本身是全屏多尺度后效，其真实采样/目标数量由引擎决定，本轮未增加pass，不能宣称零全屏成本。

现有世界空间交叉光柱8/3/0、32/12/0tri、1/1/0draw，加一个宽周期世界光带（每片元1sin，无纹理），透明度仍<=.035、近处2..9m淡入、两端淡出，太阳低于.16时隐藏。不是有遮挡自阴影的云隙体积光，穿岛/交叉仍需Web查看。保持Web/手机禁用froxel；桌面compute沿用LOW16px×64、60/90m预算，不加档。

atmosphere-shaft-swatches.png 是正式光柱片元公式的局部 swatch；黄昏列只是颜色包络代理（真实太阳很低时光柱已隐藏），不含 Zone 雾/Bloom，不冒充完整场景。高度雾及岛上/岛下融合没有可靠离线全引擎画面，明确待Web。

## C：夜间柱顶火盆

NightBraziers 独立模块；真实 Build.ColAngle / colBroken / COLONNADE_R 生成1-based anchor列表，只选完整柱，优先南北阶梯侧。柱头y=6+7.9m，火盆半径.21m，沿径向外移1m，离横梁半宽.75m留.04m余量且落在柱头1.25m方形范围内。小青铜盆为自建PBR网格，侧壁及炉床绕序/法线已数值校验。

每处两张固定世界交叉火焰面+一张局部朝向相机的微弱光晕；片元为三个不等高、随时间上行弯动的火舌和亮核，不是仅改变灯颜色。火焰1.65m高、.9m宽，HDR最高3.2，alpha<=.82；光晕alpha<=.065。0.2..0.8m近处淡出、85..110m远处淡出。光晕用于艺术表现，不声称Web真实雾中散射。

一个共享火焰材质+一个盆材质，无纹理。高/中/低火焰6/4/2、无阴影普通LIGHT_POINT 3/2/1，range12m，brightness最高7，暖RGB(1,.5,.18)，低频±6%轻微闪动；不使用手机可能丢弃的面积光。夜间系数从已有nightK再smooth，太阳elev -.04至-.22平滑开启，白天root隐藏且灯归0；不会把全场天空/环境光抬亮。nightBraziers=false完全Dispose。

异步获取火焰Material，成功前没有节点或灯；失败无重试白块，Dispose后迟到回调无效。材质默认night_strength=0。点光无阴影会穿透遮挡，照亮哪些地面/墙面以及与战斗已有灯竞争的实际情况尚未实测；不把对象draw等同引擎实际总draw。

CPU自审第一版像单根蜡烛，唯一一轮造型修订缩窄主舌并给左右舌独立高度，最终已读 atmosphere-flame-frames.png：轮廓有三峰及可见摇动、亮核和克制光晕。仍是风格化低成本火，不是写实粒子火；swatch没包含交叉面重叠/ACES/Bloom/局部照明。模型外壳绕序检查发现并修复炉床向下绕序，复跑通过。

## 预算、开关、回滚

| 项目 | 高 | 中 | 低 |
|---|---:|---:|---:|
| 云片 / tri(含2退化bounds) /对象draw |24 /194 /1|12 /98 /1|4 /34 /1|
| 云图基础RGBA8 /含全mip估算 |8 /10.67MiB|2 /2.67MiB|2 /2.67MiB|
| 光柱 /tri /draw |8 /32 /1|3 /12 /1|0|
| 火焰处数 /点光 |6 /3|4 /2|2 /1|
| 火+盆tri(含每处2退化bounds) |264|176|88|
| 火+盆对象draw /材质 |7 /2|5 /2|3 /2|
| 高度雾密度 |.009–.01062|.006–.00708|0|
| Bloom新增pass |0(复用开启)|0(原默认关)|0(原默认关)|

图集纹理/元数据完全不变，无新增图内存。资源缓存可能保留曾加载的高+低图，最坏总原始含mip约13.34MiB，不保证热降档立即回收共享GPU纹理。新增盆/火网格每处132顶点，共792/528/264顶点，采用位置/法线/UV/color时不含引擎开销约28KiB高档；actualvertexlayout/上传内存待GPU。

SkyAtmosphere原5Hz循环复用；每帧只有已有云bounds平移/累计时间。火焰GPU TIME连续动画，点光最多3盏5Hz更新，没有逐帧重建或大数组上传。关闭所有模块600帧时host clock不动；日志关闭不调用日志/Probe、不构造诊断表。开关 GameSettings.Set('cloudMotion'/'atmosphereFog'/'nightBraziers',false)，nil恢复档位默认；不改UI业务。云的clouds/lowClouds/cloudShadow及既有lightShafts/postFx/volumetric开关继续有效。

模块回滚：A仅云shader/SkyClouds motion接线与相应settings字段；B光柱band及SkyAtmosphere ApplyFog/settings字段；C NightBraziers+两资源+Scene唯一hook+宿主生命周期/settings字段。不要整文件恢复Scene或GameSettings，不触碰并行改动。旧raymarch依然不在运行分支。

## 验证和未验

atmosphere_gate.py 汇总 Lua5.4、实际settings生命周期、冷DWP回归、真实顶点表达式旋转、mip/gutter/四周太阳、全关600帧、三档火焰/灯/289时刻、资源失败及迟到回调、开关冻结恢复、wrap连续、LSP。

云/大气/设置/火焰4模块 maker-lua-lsp Error=0。扩展检查整个RuinsScene报告22条Error，均在未改动代码行（音频/战斗/向量类型等），不在新增hook；见 atmosphere-lsp-first.log、atmosphere-review.log。不能报告全项目Error=0；没有越界修复这些问题。

收工读取HEAD为d3de7c4bce165b387a28e6876ecc4248bd32d188，与开工不同；本worker没有执行提交/同步，按共享工作区现状保留。当前status仅本轮云/大气候选与验证资料，开工的Forge并行差异已不再列于工作区；没有替对方还原或清理文件。

必须新Web验：冷缓存云/火材质编译加载；固定相机5分钟云运动、极端高度yaw/pitch/roll；云低档远边稳定；岛上/岛下高度雾与光柱交叉；三档夜间实际pillar落点/火盆支撑/交叉面可见性；点光实际照亮地面而不穿墙过曝；高档Bloom亮核是否泛白；帧率/真实draw/灯数/纹理常驻；历史云上黑屏回归。本轮没有新Web构建，没有实际GPU验收。
