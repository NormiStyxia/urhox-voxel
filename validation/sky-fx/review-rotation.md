# 云随镜头转动：坐标链自审

2026-11-14，工作区HEAD bea178877d2dbe65bb25cfc0337ebe7fb7721e8a。保留所有既有WIP；不操作stash、不做Git同步、不构建、不运行本地Runtime。

## 本次实际修改

运行代码仅RuinsCloud.shader：skip_vertex_transform→world_vertex_coords；新增model_origin/world_offset；末行由手动VIEW_MATRIX乘法改为世界位置直接输出。片元阶段完全不动；SkyClouds、SkyAtmosphere、所有图集/材质、DayNight/Scene/战斗/UI未改。

补充rotation_check.py、rotation-engine-evidence.txt、rotation-counts.json、RuinsCloud-before-rotation.shader.txt与检查日志；flat_assets_check.py仅更新坐标模式契约。云文档同步新路径。

## 已读依据与完整链

- SurfaceShader文档完整“顶点动画”“vertex到fragment传值”“常用输入变量/矩阵”章节：默认object space、world_vertex_coords输入输出world、skip输出view、矩阵列向量M*v。Lua指南既有知识复用；复核25 SurfaceCustomLightScene、27 BayWater、29 ProceduralSky相关坐标/主光示例。
- read-only本机缓存engine-res 1.34.10，manifest-1b387dcc.json：SurfaceUnlit.glsl hash c11e5972、SurfaceGodotMatrices.sh abb0ac58、uniforms.sh e1f495f8、transform.sh 618948b7。关键原文行号摘录在rotation-engine-evidence.txt；没有修改缓存/引擎，也不能当作当前Web实际版本。
- Lua Scene→SkyClouds→CelestialCloudPatches；均非Camera子节点。Follow只给父节点.position=玩家位置，没有父子旋转赋值。游戏相机另由Nomi控制，当前远裁面600m，相机与玩家位置会有偏移；不将这两者当同一个位置。
- 旧路径：object顶点→固定云方向/漂移→作者VIEW*(camera+offset)→模板skip用INV_VIEW恢复world→引擎GetClipPos。矩阵一致时最终是P*V*(camera+offset)，正确，不随相机旋转保持屏幕位置。
- 新路径：引擎先MODEL*object→world输入；减MODEL原点去掉Follow平移→固定世界方向/漂移→camera+offset world输出→引擎GetClipPos。作者代码完全不读VIEW/INV_VIEW，标准投影只执行一次。world NORMAL/cloud_right与世界太阳方向一致。
- 包围盒仍以玩家为中心±2048；可见半径522..548m，加目前相机最大约26m臂长有充分余量。zero-area bounds triangles原样保留，实际GPU剔除尚未测。

## 可确认与不可确认

15360组CPU实际顶点表达式数值验证通过：三档真实网格；yaw0/90/180/360；pitch上下；roll及组合；位置0/80/30000m；相机与模型中心不同；固定时刻世界方向/主光点积不变；屏幕投影改变；360回原位；纯平移不移动天球投影；仅时间变化产生漂移；点落在CPU包围盒内。

测试也运行旧shader，正确矩阵下旧版同样通过。故本次不能诚实给出“根因是漏乘/抵消相机旋转”的结论；这是缩短并替换可疑手动空间往返的最小兼容修订候选。故障注入把作者侧VIEW设为identity能重现旧版锁屏、不会影响新路径，但不是实测引擎错误，JSON明确root_cause_confirmed=false。

之前CPU预览直接用理想相机射线/世界网格，不执行shader矩阵往返；它不能证明旧Web正确，也不能用本次CPU通过冒充实机修复。新测试读取并执行真正vertex表达式，但Python解释器不包含SurfaceShader AST生成器、GPU uniform绑定/精度和光栅器，仍非GPU编译。

Cindy browser status确认同机外置Google Chrome；tabs只有指定B站参考页及子iframe，没有当前游戏标签。不重开不明版本旧Web，不擅自构建。下一步需明确构建后核对本轮shader md5，在固定时间/位置观察同一云的yaw/pitch/roll、360、纯平移，并确认太阳边缘/深度/剔除。黑屏、真实Web视觉与GPU性能仍未验。
