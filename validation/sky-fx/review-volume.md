# 三维融合云自审（2026-11-14）

本轮按 procedural-geometry、sky-and-environment-lighting、surface-shader、volumetric-fog、deferred-rendering 与现有shader核对实现；没有更改渲染管线、开启LocalFogVolume或启动Runtime。天空卡片/图集/billboard均移除，地面遮罩按允许范围保留。

## 实现与已修问题

- 六种共享源形状是包含共同原点的球并集，解析径向求交+smooth-max、平底裁切，固定球面拓扑保证闭合；不是多个穿插球网格。冠部增加纬线以避免烘焙形状像扁平圆饼；已读取volume-shapes.png。
- 每形状高LOD182顶点/360三角，中LOD114/224，远LOD26/48。全部六高+六远源形状通过双向边共享、Euler=2、正体积、外向法线、无退化与颜色范围测试，六形状不重复。
- 实例以固定随机式旋转/拉伸合并三批，法线使用逆转置。选择合批而非六种Model分别实例化，保证不依赖平台的颜色批次≤3。高6144、中1984、低0三角。
- 生成全程隐藏，每帧一次resume，最多240上传顶点/一次Commit；高档176个slice。烘焙颜色按源顶点缓存复用，避免每次复制18k顶点时重复Color分配；法线/颜色阶段也分帧。正常状态5Hz只写uniform与transform。
- 切档取消悬挂协程、Dispose隐藏节点/克隆材质。测试覆盖真实设置在第8帧取消高档并建立中档，600帧关闭无生成，600帧就绪无Commit。
- 烘焙失败先Dispose半成品，最多重试一次6个简单球/288三角；二次失败安全隐藏并释放材质。自审修复终止失败后重复Dispose已失效Node的风险：终止时清root引用。缺shader走文档PBRNoTexture+粗糙球体，设置初始颜色避免默认白材质；没有卡片兜底。
- 顶点颜色是烘焙后填入，类型改为可空并在上传断言完整，修复LSP assign-type-mismatch。颜色与法线计算仅在初始化协程执行。
- 昼夜289时刻验证day/dusk、天空颜色有限且合法；天空sRGB在shader显式转线性；真实主光方向、法线和厚度控制soft-step/透光，继承Zone雾。

## 验证范围

check-volume.log、settings-sky-volume.log、settings-quality-volume.log、settings-check-volume.log、lsp-volume.log（Error=0）、assets-volume.log、diff-volume.log。全部离线；具体命令和结果以日志为准。

volume-shapes.png是实际源网格的CPU几何预览，逐面简单光照没有模拟插值法线/SSS/fog/曝光/排序，不是游戏截图。旧flat/shadow日志与配色图只是历史记录。

## 尚待Web验证

SurfaceShader真实编译与深度约定；三批内部透明排序、与岛屿交界、fresnel边缘、月光/夕阳透光；云形是否仍像石头/馒头；远云能否融入天空且不形成硬带、岛下不成底板；首次材质编译/每slice/Commit/GC的峰值，显示等待及长期CPU/GPU性能。

这是具有闭合三维几何与近似厚度光照的烘焙云，不是可进入后仍有密度积分的真实参与介质光线步进，也不把天空云纳入SkyLightCapture（该组件只捕获Skybox）。不将这些限制冒充已通过Web验收。
