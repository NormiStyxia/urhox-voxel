# 2026-11-14 云密度积分自查

范围：SkyClouds / SkyAtmosphere云接线、RuinsCloud shader/material、新密度PNG及官方meta、相关云文档与离线验证。未改DayNight/Scene/战斗/UI/引擎，未提交、构建、启动Runtime。

已处理的审查项：

- 取消旧504帧云壳生成与三批透明排序；单次三维射线积分，创建立即ready。
- 深度显式highp；0..1清屏far不做无意义齐次除法；保留w符号，平行slab不除零，invalid值discard。
- 三维体插值使用明确LOD0、像素中心、独立Z片，数据不做sRGB解码。错误尺寸/资源缺失/绑定失败走解析密度，shader绑定失败停止云pass。
- 空的玩家高度层先排除；前景早于上/下云层可直接退出，跨层空隙不读纹理，避免在草地覆盖像素上白跑96次纹理采样。
- 停止后释放缓存借用引用，Dispose独占节点/克隆材质；无每帧顶点/纹理重建，日志门控保留。
- 漂移时钟以共同周期回绕，长期有界且相位连续。day/dusk/dt防NaN/Inf。
- 校准预览后提高离线密度分辨率与近景体量；最终图已读，仍偏柔，未当作Web完成验收。

未解决/需新Web实测：

- 黑屏根因未复现；只有旧预览一帧正常的证据，业务版本号不能证明源码版本。当前游戏标签已关闭，未擅自重开/构建。
- SurfaceShader在当前Web上的实际编译、Z_CLIP_SCALE近面覆盖、深度采样/MSAA、透明水/粒子先后顺序和天空捕获反馈未验证。
- 高档96主步×2光步最多576次数据读取/命中像素，未经GPU实测。高覆盖率可能昂贵；不能用1三角称作性能已优化。
- 同一RGB体数据让低档仍占共享约18MiB RGB / 24MiB RGBA，mip分配可能额外增加；首次解码/上传峰值未测。
- 仍是单次散射+艺术环境项，地形对云投影/多次散射/原神官方栈不在已实现项。远云偏淡、近边偏柔，需要明确视觉评审。

研究限制：natural-disasters的README/LICENSE/核心GLSL已读；Unity核心shader/README已读，MIT只核对到仓库元数据，LICENSE抓取超时；Bevy和Storm源码抓取超时。没有复制未核实授权的实现。

离线检查通过不代表上述Web风险已关闭。旧volume_contract.lua、volume_shape_preview.py等为旧壳体版本历史脚本，当前入口为check.py、density_contract.lua、raymarch_check.py；不要把旧形状图/日志与本版混用。
