# 指定参考研究：BV1Bz4y1L7Te / URP_ASE_Tutorial

日期：2026-11-14。结论只适用于读到的公开复刻，不代表原神官方渲染栈。

**最新决定：用户随后明确说“别管体积云了”。源码/视频证据不变，但下文最初的三维体积映射已成为历史。当前实现为原创多通道烘焙图+相机中心曲面云片，见云文档“当前候选”与review-skycards.md；不再运行raymarch、深度反投影或预乘累积。**

## 实际看过的画面

通过 Cindy browser 操作同机 Chrome，在指定 B 站页面暂停/seek，核对 URL 与 video.duration=27.066s。看过 3s、7s、11s、11.8s、13.5s、21s 静帧；没有声称逐帧完整播放或听过讲解。第一次打开曾自动连播到另一视频，已返回目标并暂停，未把连播画面当参考。

- `xuetao-video-07.webp` / `xuetao-video-21.webp`：白天，蓝色天空，宽底积云和高塔组合；不是几个等大的球，轮廓有密集小凸起。亮面近白，侧下方浅蓝，远处云底与亮地平线相接。
- `xuetao-video-11_8.webp`：Unity 内时刻约 18:09，暖橙红天空，云主体橙红、背光面暗紫，细亮边明显，轮廓没有被大片雾完全洗掉。
- `xuetao-video-13_5.webp`：内时刻约 21:33，深蓝天空与暗蓝云，顶部和侧面略亮。
- 画面右上 Scene View 有天空球与环状云布局；这只是视觉观察，几何结论另外由源码确认。截图含网页与弹幕，不是项目验收截图。

## GitHub 源码与许可证证据

仓库：https://github.com/xuetaolu/URP_ASE_Tutorial
commit：`0df750e2722a5d43781f980c751ff98288b31a3b`，`xuetao-ref.json` 保留回执。以下路径均相对 `Assets/Scenes/shaderDevelop_2023_08_10/原神云渲染/`。读取经过 cindy-github 插件，未整库下载。

| 已读文件 | 确认内容 |
|---|---|
| 仓库 README.md / LICENSE | README 仅说明 ASE/URP 教程与群号；LICENSE 为 GPL-3.0，非 MIT |
| `genship_cloud.shader` | Transparent / Cull Off / SrcAlpha-OneMinusSrcAlpha / ZWrite Off，引用下述 vert/frag |
| `genship_cloud_common.hlsl` | 顶点色、UV/UV2/UV3，8组 varying，没有体数据或真实法线输入 |
| `genship_cloud_vert.hlsl` | 2×4图集，顶点色G选格、B/A羽化，UV2动画进度、UV3淡入淡出；clip 深度强制远面；视线与日月方向驱动颜色/透射；天空角度LUT |
| `genship_cloud_frag.hlsl` | 两次2D采样：Noise RG扰动UV/B控制幅度，Mask R亮暗插值、G透射边、B溶解分子、A整体覆盖；透明度低时discard；没有密度步进 |
| `genship_genship_cloud.mat` + `.meta` | 实际材质队列2551，三张纹理GUID与纹理meta逐一匹配；日/月透射、亮暗近太阳/远太阳配色参数 |
| `genship_skybox_v2.shader` | 顶点按仰角查Irradiance R/G，四端天空配色/太阳方向聚集；fragment太阳/月亮/星星噪声，不是物理大气多重散射积分 |
| `script/GenshinDynamicCloud.cs` | 单云4顶点2三角，基础2000×1000平面；半径5000m环布、Quaternion.LookRotation；两个高度层，合并动态Mesh上传；源码时间2024，不能断言就是2023视频的原始提交 |
| `script/GenshipSkyParams.cs` | MaterialPropertyBlock同步天空与云参数；方向由sun/moon Transform给出，颜色可由Timeline驱动 |
| `原神云渲染_v3_with_fog.unity` | cloud/baseCloudCount20无顶部；cloud1/baseCloudCount6且追加顶部，均高度500/距离5000，另有独立fog cube；颜色控制器引用云renderer。该场景共32云片≈64三角、两个renderer，并非32体积 |
| `mesh/cloud.csv` / `cloud.fbx.meta` | CSV含捕获的顶点、索引、颜色/多UV数据，与shader输入吻合；没有下载/导入FBX；场景当前动态Mesh fileID0由脚本生成 |
| `texture/MaskMapRGBA.png`及三张纹理meta | 实际看过四通道拆分图`xuetao-mask-channels.png`：R为细节明暗，G主要细轮廓线，B宽渐变，A轮廓。Mask/Irradiance为Clamp，Noise为Repeat；这些是Unity设置，不能盲搬到UrhoX |

资料 JSON 保存原始 blob SHA 和内容。`xuetao-source-*.txt` 为研究用解码副本，`xuetao-mask-channels.png` 为研究用通道可视化；不属于自有运行资产，不应当作可商用原创纹理。作者注释多处称“原神/截帧”，素材具体权利链未查明；GPL 仓库许可也不能证明第三方美术素材授权。**没有把参考代码、纹理、网格复制进 assets 或 scripts**。实现为独立距离场/积分公式，只借鉴亮暗分离、薄边透射、方向性暖色、云团层级这些一般方法。

## 方法结论与最初项目映射（历史，已被天空曲面方案取代）

该参考属于环状网格云片 + 多通道美术遮罩 + 天空LUT/方向性染色。它没有可穿越的三维密度、自阴影射线或Beer-Lambert云积分；因此原样移植会与用户“不能只贴图、要3D”冲突。它的细节主要已经画在R通道，并不是运行时几何光照自动长出的细节。

本项目继续有限三维距离场重建密度，沿视线Beer-Lambert积分；保留体积内外、上下、近裁面和场景深度遮挡。迁移外观思路：自主球团层级形成轮廓，距离场动态方向厚度代理形成亮暗色分区，薄密度边缘增加方向性透光，黄昏向太阳方向暖色更强，天空uniform提供雾色融合。并不照搬Unity远平面云片的深度策略。当前一次偏移采样只是动态局部厚度代理，**不是完整次级光线自阴影**。

UrhoX核对：`surface-shader.md`的透明/预乘、窗口深度0..1、skip_vertex_transform返回view-space、Z_CLIP_SCALE近面、textureLod规则；Lua指南/材质指南；示例25 SurfaceCustomLightScene、29 ProceduralSky、27 BayWater的配色/深度约定。使用现有SurfaceShader API，不改引擎，不套Unity宏。scatter已预乘，factor=1；无重复乘Alpha，无写DEPTH。

## 未确认

没有该复刻的GPU耗时或移动端证据，没有原神官方技术资料；不能把教程标题当官方实现说明。当前项目没有包含本次修改的已验证Web构建，CPU图不是游戏验收。黑屏根因、真实shader编译、透明排序/天空捕获影响、转头时条纹和实际帧率均待同版Web验证。
