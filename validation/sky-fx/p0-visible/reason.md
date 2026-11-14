# P0：d604b71 后云不可见，最小安全片元候选

基线HEAD：58862665929918fe6769d920528d61c5b4de1f6e。开工已有validation差异/未跟踪资料，见start-status.log，全部保留。仅改一个运行资源 RuinsCloud.shader，不改Lua、夜火、雾、战斗、图集或meta。未提交、推送、构建、启动Runtime。

## 已证实

- 当前相对1a78a3d增加了顶点慢风，以及片元motion_detail分支、fwidth和billow扰动，见parent.diff。
- 当前SkyClouds已使用GetResourceAsync；异步完成后检查尺寸，设置cloud_enabled=1，迟到回调受disposed/loading保护。本轮不回退这些修复，受protected-hashes.json保护。
- 本地runtime.log仅找到另一个UUID的POSITION/deferred警告：HQ-5qfZwSR37r_zXuUDQ01dw对应HiddenVoxel.shader；RuinsCloud的UUID为B7kCUdFGjP2SetnaTjmh7PX4，不能把该警告归因为云。runtime state另记日志查询连续失败6次，lastSuccessAt=2026-11-14T20:32:56.828Z，不能把缺少云错误日志视为编译成功。
- SurfaceShader文档明确支持fragment中的fwidth(float/vec2/vec3/vec4)，要求避免非一致控制流；原motion_detail来自uniform，cloud_enabled提前discard也由uniform控制，后面的alpha discard在求导之后。因此**没有源码证据证明这段必然违反文档或引擎不支持fwidth**。具体WebGPU生成器/变体编译失败仍是候选。
- 原有varying与world_vertex_coords契约未改变；world顶点减MODEL_MATRIX原点得到方向、加CAMERA_POSITION_WORLD后交给引擎view/projection。sampler默认black并非透明（文档说明黑且不透明），实际缺贴图由Lua安全隐藏；本轮不修改此契约。

## 最小调整

把整个fragment恢复到1a78a3d的逐字内容：一次texture(cloud_atlas,UV)路径、原alpha/discard、原明暗透射/天空融合，移除全部fwidth、billow及motion_detail控制分支。保留当前vertex世界空间分层慢风。保留一个不再参与运算的motion_detail uniform声明兼容现有Lua绑定，避免扩大Lua修改或引入未声明参数写入的不确定性；它不影响任何顶点/片元结果。

before.shader.txt/after.shader.txt保全两版；check.py证明fragment与参考完全相同、vertex与本次基线完全相同，并核对相关运行资源hash无变化。1a78a3d的片元只作为回退对照，不把该提交本身视为本轮GPU可见成功的证据。

## 根因仍未证实

没有当前WebGPU云shader的实际编译/绑定日志，没有新包。此改动只排除新增片元导数/控制流作为变量，不能承诺已经找出根因或云已恢复。Lead新Maker构建后应先核对cloud shader UUID/hash及资源回执，再检查冷/热缓存和高/中/低档实际可见；若仍不可见，继续查cloud_enabled重载、材质绑定/alpha、云节点/包围盒/画质状态，不能不断猜测叠加补丁。

历史atmosphere-preview图含billow，已不代表该安全片元；本轮不复用它们冒充修复验收。测试/LSP均只作离线回归，不替代GPU编译。
