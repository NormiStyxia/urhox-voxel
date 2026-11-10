# 体素人物与龙：制作流程与 Web Maker 交接

整理日期：2026-11-10。代码基线：`70035d1`（整理前的本地 HEAD）。后续开发由 Web 端 Maker 承接。

本文依据同项目其他 Cindy 会话的用户要求、完成报告，以及当前代码、资源与 Git 历史整理。历史完成报告只证明当时的检查结果；本次整理没有重新运行游戏，也不把自动检查通过等同于视觉与手感验收。

## 1. 接手时的当前状态

- 项目是 TapTap Maker / UrhoX 的 Lua 游戏，长度单位为米，Y 向上、Z 向前。
- `scripts/main.lua` 通过 `scripts/config.lua` 的 `START_SCENE` 选择入口；当前值为 `"dragon"`。`scripts/dragon_main.lua` 可直接启动龙测试场景。`"town"` 返回体素小镇。
- 玩家是诺米（Nomi，聊天里也写作“糯米”），只保留修长版。Q 版和 M 键切换已经弃用。
- 龙具有独立头颈、下颚、四肢、双翼与尾链，支持九种动画状态、骑乘、飞行、滑翔、降落和空中冲刺。
- 人物与龙采用不同的几何生产路径。人物是离线体素雕刻后导出的顶点色网格；龙身体是启动时创建的原生体素部件，翼膜则是 GPU 变形的连续网格。
- 已预留龙的部件、命中区、嘴/喉/胸口/鞍座挂点。完整战斗、体素碎裂重组和真实空气动力学尚未实现。

## 2. 技术栈与数据流

| 环节 | 人物 | 龙 |
| --- | --- | --- |
| 参考 | Mivo 角色方案与正侧背三视图 | 蓝白西方龙三视图 |
| 制作语言 | Python 3，NumPy、SciPy、Pillow | Lua 5.4 |
| 建形 | 分部件轮廓雕刻、按面采色、局部斜面、同色面合并 | SDF 体块平滑融合、按骨骼标签体素化 |
| 运行几何 | 每骨骼一个 `CustomGeometry`，四边形转三角形，另有斜面三角形 | 身体/翼骨为 `VoxelVolume`；翼膜为连续 `CustomGeometry` |
| 驱动 | Node 骨骼层级、程序化摆动、骑乘姿态覆盖 | Node 层级、姿态混合、FK、解析 IK、步态规划 |
| 渲染 | 顶点色 PBR SurfaceShader | 引擎体素调色板材质与 AO；翼膜专用 SurfaceShader |
| 工具 | 历史 Blockbench 工程与 Python 离线预览 | `urhox-libs/UI` 调试面板、Maker Runtime 检查 |

人物：`三视图 → voxelize.py → refine.finish → NomiVoxelData.lua → BlockCharacter.CreateVoxel → 玩家/骑乘动画`。

龙：`参考图 → DragonSpec → DragonSculpt → DragonRig → 状态机姿态混合 → FK → 四肢 IK → 翼膜矩阵更新`。

## 3. 体素人物的制作流程

### 3.1 设计与参考确定

早期目标是 YSM 风格的可操控角色，后来明确无需兼容 YSM，最终用于 UrhoX 体素地图。会话中先尝试冒险战斗服装，再调整为现代蓝白配色、水手服、中长裙与藏青色连帽破碎斗篷，避免盔甲和大量皮质装饰。

实际落地参考为 [`ref_ysm_navy.png`](../art/nomi_ysm/ref/ref_ysm_navy.png)。后续建模始终以这张图核对身份、脸、服装层次与比例。

### 3.2 方块模型起手

[`build_nomi.py`](../art/nomi_ysm/build_nomi.py) 程序化拼装脸、刘海、头发、衣服和斗篷，输出 `nomi.bbmodel`、`nomi.geo.json`、`nomi.png` 与 `preview.png`。这是可继续在 Blockbench 中编辑的早期方案。

对应游戏数据为 `scripts/game/NomiModelData.lua`，运行路径是 `BlockCharacter.Create`，采用盒子 UV 和贴图材质。它仍保留在项目中，但当前玩家走的是体素网格路径，修改这份历史数据不会自动修改当前人物。

### 3.3 三视图雕刻成体素

[`voxelize.py`](../art/nomi_voxel/voxelize.py) 是当前生产入口：

1. 去背景、去脚边阴影，填补浅色头发和白衣轮廓里的空洞。
2. 对齐并采样正、侧、背视图。当前采样为每格约 10 个参考图像素，导出单位 `0.022m`。
3. 按头、手臂、双腿、身体、裙摆、外套、斗篷碎条与头发划分形体，分别限制深度。直接把三视图轮廓求交会把手腿撑成厚板，因此不能只做统一 visual hull。
4. 建立脸与刘海的前后层次，处理圆角头、头顶斜面、后发、帽兜、翻领、外套开口和手部，清除薄片与尖刺。
5. 按表面朝向从相应视图取色，脸部单独量化，避免眼睛和肤色被衣服色板污染；修正半侧面“四只眼”。
6. 合并同色共面面片，局部以楔形/三角形替代细碎台阶，减少几何量并保留体素轮廓。
7. 调用 `refine.finish` 精修认可的头部与独立发束，保留服装细节，仅定点清理误采样颜色，最后导出 `scripts/game/NomiVoxelData.lua`。

`carve.py` 是早期轮廓/采样实验，保留了 `mask.png`、`views.npz` 等中间产物；当前 `voxelize.py` 自行读取三视图，不要求先执行 `carve.py`。

### 3.4 生成器、基准与可重复制作

在项目根、具备 Python 依赖的环境中运行：

```sh
python3 art/nomi_voxel/voxelize.py
python3 art/nomi_voxel/check_mesh.py
```

第一条会重写生产 Lua 数据、离线预览，并在 `.tmp/nomi-review/` 生成评审数据；第二条对导出后的评审数据做回归比对。运行前保存现有修改，运行后检查 diff，不能靠重新生成来覆盖未理解的手工改动。

生成器当前依赖以下已入库基准，Web 环境必须一并保留：

- `approved_head.json`：认可头部几何与颜色，包含面部保护基准。
- `rollback_baseline.json`：恢复后的服装/四肢、原骨骼与认可发束的比对基准。
- `detail_cleanup.json`：圈定服装区域的逐面颜色改动记录。

`preview_3d.png` 和 `compare.png` 是当前离线模型预览，不模拟实际游戏的 PBR、投影和后处理；早期 `preview.png`、`grids.png` 不能代替当前版本验收。

### 3.5 绑定、比例与程序化动画

[`BlockCharacter.CreateVoxel`](../scripts/game/BlockCharacter.lua) 读取 Lua 数据中的 `bones / quads / tris / palette / unit / origin`。每根骨骼创建一个 Node 和对应 `CustomGeometry`，颜色写到顶点。当前使用 `Materials/NomiVoxel.xml` 与 `Shaders/BLGL/VoxelCharacter.shader`，脸和衣服花纹主要来自顶点色。

当前骨骼表为原 16 根：root、左右腿、body、skirt、coat_upper/lower、三根 cloak_strip、左右臂、head、hair_locks、hair_back、hood。头发、帽兜、外套分属节点，但并非完整布料碰撞或连续蒙皮系统。

统一体型来自 `BlockCharacter.SLENDER`：头缩放 0.82，前后发束 0.85，腿 Y 拉长 1.35，身体 X/Z 收窄 0.85/0.92。收窄通过几何及轴心位置处理，避免父级非等比缩放后子节点旋转产生剪切。主场景和骑龙场景使用同一份配置。

`BlockCharacter:Update` 负责行走、跑动、跳跃、下蹲及头发/外套/裙摆等次级动作；骑乘时由 `DragonRide:SeatPose` 覆盖坐姿，并附着 `saddle` 挂点。

### 3.6 已经踩过的坑与当前边界

- 用户多次确认面部满意，要求保留脸部几何与颜色；头发与衣服必须有独立结构，不能把头发颜色画在帽兜上。
- 用户要求只用修长版，不再恢复 Q 版或体型切换。
- `82f4a59` 尝试增加膝关节与骑乘调整，`3db8f6f` 尝试服装重建与大范围统一颜色；后者导致领口、袖口、裙褶、靴子和破边等设计细节丢失。
- `5a9ea6e` 选择性恢复服装、四肢与原骨骼，并保留认可的分层发束；没有重写 Git 历史。当前不能宣称那次新增膝关节已保留。
- `d00018b` 恢复头发原配色，局部清掉衣服误采样白点；当前细节丢失问题不能归因于漏载贴图。
- 旧衣服的碎杂颜色、袖子/外套的横向阶梯感和原腿部动画问题仍需针对性处理。保留领口、饰件、裙褶、破边与靴子，不能再次用大块纯色几何替换整件衣服。

### 3.7 另一会话的服装拆解图

会话「糯米像素小人三视图与流程整理文档」于 2026-11-10 01:28 左右完成一张 Mivo 服装拆解设定图（时间为北京时间）。已读取其生成成功记录：任务 `6af20290dd34536f96ce7a72`，图片文件 ID `6af202a1dd34536f96ce7a74`，能力 `image.gpt`。

该图当时交付在 Cindy 媒体库，记录中的内容指纹为 `770653a09768f3bca27d0d7346d400fcea9bcd5bf4904fc5471d597127bc6509`。本次未将图片二进制迁入仓库，Web Maker 不能直接用 Cindy 媒体地址读取它。需要按图继续拆衣服时，应先将实际原图导入项目；这张图是否与当前模型逐部件一致尚未验收，不能将生成成功视为已完成建模。

## 4. 体素龙的制作流程

### 4.1 从参考图建立解剖规格

参考图为 [`dragon_ref.webp`](../art/dragon/ref/dragon_ref.webp)。目标是尽量还原蓝白四足双翼西方龙，并保持可动、可测试、可扩展破坏接口，而不是导出一张静态模型图。

[`DragonSpec.lua`](../scripts/dragon/DragonSpec.lua) 定义比例、骨骼枢轴、SDF 体块、调色板、翼结构、命中区与挂点。左右对称部分以右侧为源，通过 `Expand()` 镜像生成。

造型采用椭球、变半径胶囊、圆角盒、鳍片与菱形片，分别描述胸腹、长颈、吻颚、角、背刺、承重腿、翼骨、长尾与菱形尾饰。翼前缘通过同一骨骼下的曲线体块表达弧度，不需要为每段造型新增活动骨骼。

### 4.2 体素化与节点装配

[`DragonSculpt.lua`](../scripts/dragon/DragonSculpt.lua) 对 SDF 平滑并集采样，按最近体块的骨骼标签分配体素和颜色。当前身体体素边长 0.08m、头/下颚 0.055m、翼 0.10m。

[`DragonRig.lua`](../scripts/dragon/DragonRig.lua) 为骨骼建立 Node，通过 `world:CreateVolume` 创建体积、填入 grid、`RebuildGeometry`，再将体素部件挂到对应骨骼。动画阶段只更新节点，不逐帧重建整条龙。

龙身体体积目前不调用 `Finalize`、不建立物理刚体。`destructible = true` 和部件访问接口只是扩展入口，不能当作完整破坏玩法已接通。

早期为补关节缝隙复制深层体素，出现腰/骨盆/髋部近共面闪烁。当前构建明确使用 `overlap = false`，关节缝改由挂在父骨骼上的内收关节球遮挡；不要按旧说明重新复制外壳。

### 4.3 材质与视觉调整

身体克隆引擎体素调色板材质，移除 `VOXELJITTER`、保留 AO，避免逐体素随机明暗让生物表面显脏。龙占用调色板槽 40–54。

用户明确要求取消“双眼冒光”，眼睛使用浅色区域与蓝色瞳点；当前 `DragonSpec.EMISSIVE` 不包含眼睛，只给翼膜和白甲少量自发光以抬亮背光面。这是风格化透光感，不是实际次表面散射仿真。

### 4.4 骨架与动画顺序

```text
root（全局位移/朝向）
└─ body（重心、俯仰、侧倾）
   └─ pelvis → waist → chest → neck1..4 → head → jaw
      ├─ pelvis → tail1..8
      ├─ pelvis → legU → legL → legM → foot（左右）
      ├─ chest → armU → armL → hand（左右）
      └─ chest → wing → wfore → whand → 四根翼指及各自远端节（左右）
```

动作定义在 `DragonAnimationController` 的 `STATES`，包含 `IDLE / WALK / TURN / SPREAD_WINGS / TAKEOFF / FLY / GLIDE / LAND / ROAR`。状态切换保留旧层自己的时间轴并淡出，避免关节归零或新旧动作时间串用。

每帧先计算全局运动，再混合身体与关节姿态、写入 FK，随后由四肢 IK 接管需要贴地的腿，最后更新翼膜。新增动作要遵守这个覆盖顺序。

- `DragonPose.lua`：姿态表、权重混合、写入骨架。
- `DragonPoses.lua`：翼、颈、尾的语义参数与预设，尾巴具有逐节延迟和飞行下垂/高速后展过渡。
- `DragonGait.lua`：左后→左前→右后→右前的四拍步态，支撑占空比 0.66；支撑足钉在世界坐标，摆动足预测落点，步频关联速度和转向。
- `DragonIK.lua`：解析 IK、伸直附近的 Soft IK 和前肢肩胛滑动，减少滑步、反折与突跳。

### 4.5 翼膜从分片升级为连续网格

最初采用独立薄片跟随相邻翼骨插值，用户反馈收翼/运动时仍会散开。当前生产实现已经替换为：

1. `DragonMembrane.lua` 将体素阶梯轮廓构造成连续网格，视觉厚度 0.04m，明显薄于翼骨。
2. 每侧用翼根、肘、腕、指关节、指尖与贴腰点组成 14 个控制三角形；每侧预留最多 16 个槽位。
3. 顶点以 UV 保存所属控制三角形索引，Lua 每帧依据骨骼计算仿射矩阵。
4. `assets/Shaders/BLGL/DragonMembrane.shader` 接收矩阵在 GPU 上变形顶点，用逆转置对应的余子式方法处理法线；共边映射一致，避免刚性薄片之间张开缝隙。

这是针对翼膜的专用形变，不是整条龙的通用权重蒙皮或布料模拟。大角度折叠时是否穿模仍应看实际画面，不能只凭连续性推断全部正确。

### 4.6 起飞、飞行、降落与骑乘迭代

起飞按降低重心、蹬离、展翼、首轮下拍、收腿推进；飞行加入颈胸和四肢的次级动作；降落加入制动、探足、前后足分阶段 IK 接管、身体缓冲、颈链错峰回弹与收翼，避免只有翼在动。

早期骑乘只允许地面移动，Space 曾与下龙冲突。当前 `DragonRide.lua` 已把骑乘控制分离：F 下龙，Space 起飞/上升；人物徒步时 Space 仍跳跃。无人骑乘时龙在地面自主闲逛、偶尔咆哮，玩家靠近时等待；空中不由地面 AI 抢状态。

`DragonFlight.lua` 管理后续加入的空中手感：

- `yaw` 为身体朝向，`travelYaw` 为实际运动方向，先侧倾再让航迹追上，产生转弯惯性。
- 默认基础飞行参数下，W 前进约 11.6m/s，Shift 冲刺至 18m/s；松键留余速，S 优先主动减速。速度可由调试参数改变，不应把这些值写死到别的模块。
- 玩家飞行按制动距离提前减速；不再用演示模式的自动盘旋抢玩家方向，也不靠截断空中位置制造边界停车。
- 迎风张力区分持续风压和加速牵拉，头发、外套、衣摆、尾链与镜头采用不同响应速度。
- 起冲时龙胸背压低、头颈前探，持续冲刺时翼后掠收窄、振翅加快且幅度收小；受风方向跟实际航迹，而非刚转过来的龙头。

这些是服务于体验的简化运动与姿态模型，不是真实空气动力学。最新一轮“迎风钻进气流”的视觉强度仍待玩家试飞确认。

## 5. 当前操作

| 情境 | 操作 |
| --- | --- |
| 徒步 | WASD 相对镜头移动，Space 跳跃，Shift 奔跑 |
| 上龙 | 靠近约 3.6m 内，按 F |
| 骑乘地面 | W 前进，A/D 转向，S 停止，Space 起飞，F 下龙 |
| 骑乘空中 | W 加速前进，A/D 转向，Space 上升，C 下降，G 滑翔，L 降落，F 下龙 |
| 空中冲刺 | 按住 Shift；滑翔时会恢复振翅飞行；S 刹车优先于 Shift |
| 观察 | 鼠标拖动旋转，滚轮缩放；镜头跟随人物或龙 |
| 动画调试 | 关闭面板里的“玩法模式”，再测试状态、参数、单步和关节 |

## 6. 关键文件与 Web Maker 续接

| 要改的内容 | 先看这些文件 |
| --- | --- |
| 人物参考、离线生成 | `art/nomi_ysm/ref/ref_ysm_navy.png`、`art/nomi_voxel/voxelize.py`、`refine.py` 及三个 JSON 基准 |
| 人物当前运行几何 | `scripts/game/NomiVoxelData.lua`、`scripts/game/BlockCharacter.lua` |
| 人物材质 | `assets/Materials/NomiVoxel.xml`、`assets/Shaders/BLGL/VoxelCharacter.shader` |
| 小镇玩家接入 | `scripts/player.lua` |
| 龙静态造型与关节枢轴 | `scripts/dragon/DragonSpec.lua`、`DragonSculpt.lua`、`DragonRig.lua` |
| 龙状态和身体动作 | `DragonAnimationController.lua`、`DragonPose.lua`、`DragonPoses.lua` |
| 龙落足 | `DragonGait.lua`、`DragonIK.lua` |
| 翼膜 | `DragonMembrane.lua`、`assets/Shaders/BLGL/DragonMembrane.shader` |
| 骑乘与飞行 | `DragonRide.lua`、`DragonFlight.lua` |
| 场景与调试界面 | `DragonTest.lua`、`DragonDebugUI.lua`、`scripts/dragon_main.lua` |

Web Maker 接手先打开 `docs/README.md`，以代码基线和本次文档提交为依据继续，避免覆盖 Web 端更新。人物运行直接读取已生成 Lua 数据；运行游戏不需要先执行 Python。只有更改离线造型时才需要 Python 和完整基准文件，Web 执行环境是否具备这些依赖应实际检查。

新增效果先分清修改源：人物生成数据要回到生成器，龙形体要回到 Spec/Sculpt，动画要回到控制器与姿态模块，不能仅手改产物而丢失可重复制作能力。使用项目内 UrhoX 文档和示例核对接口，资源路径相对 `assets/` 或 `scripts/`，不要将本机绝对路径、`.tmp` 证据路径或 Cindy 专用媒体 URL 写入运行逻辑。

## 7. 验证方式与尚未完成的验收

| 检查入口 | 能证明什么 | 不能证明什么 |
| --- | --- | --- |
| `art/nomi_voxel/check_mesh.py` | 头部/面部 RGB、保留的服装几何与颜色、发束和骨骼表符合基准 | 动画自然、服装碰撞正确 |
| `art/nomi_voxel/rig_validate.lua` | 在 Runtime 加载人物并调用待机/走跑/跳跃/下蹲 | 腿缝与骑乘逐帧视觉正确 |
| `tests/dragon/anim_check.lua` | 固定 1/60s 演示序列，检查 IK、滑步、骨长、反关节、突跳、穿地、对称和状态覆盖 | 所有可玩输入组合和视觉观感 |
| `tests/dragon_controls.py` | 生产 Lua 的按键优先级与尾姿态数值 | 真实引擎渲染和碰撞；它使用测试替身 |
| `tests/dragon_sprint.py` | 冲刺加减速、航向滞后、边界制动、不同帧率稳定性 | 玩家主观手感 |
| `tests/dragon_wind.py`、`tests/dragon_charge.py` | 迎风延迟与冲刺姿态的数值约束 | 成片视觉效果 |

Python 控制测试依赖 `numpy` 与 `lupa` 的 Lua 5.4 支持；人物生成/检查还依赖 SciPy、Pillow。`tests/dragon/run_anim_check.sh` 是依赖本地 Maker CLI 的包装器，不能假设 Web 端能直接执行；Web 环境应复用同一测试 Lua，通过它实际提供的 Runtime 验证入口运行。

历史检查：原型会话曾报告动画 26 项通过；人物局部恢复时报告无头检查 25 项、0 运行报错。更早的 77 项检查针对后来被部分撤回的版本，不是当前膝关节已修复的证据。最近冲刺会话报告离线回归通过，但仍明确需要试飞确认。

待接手确认的问题：

- 人物原腿部动画、腿缝和骑乘贴合尚未完成当前版本逐帧视觉验收；恢复原结构时也恢复了这些旧问题。
- 头发旧配色仍有碎杂，衣袖/外套仍有横向阶梯感；后续清理须保留设计细节。
- 最新冲刺的压风与张力强弱需真人操作确认；不要用数值通过替代体验验收。
- 最近本地预览记录中仍有 `Cube/Day/DaySpecularHDR_QualityLow.dds` 缺失报错。那是当时日志证据，Web 端是否同样缺失需重新检查。
- 连续翼膜解决结构断缝，不代表所有折叠角度的穿模和阴影都已验证。
- 参考图、离线预览与 Runtime 画面应分别核对；缺少当前运行画面时不要宣称外观已达成 1:1。

## 8. 关键提交与会话来源

| 提交 | 制作节点 |
| --- | --- |
| `9de3301` | 体素小镇与方块诺米玩家 |
| `d03a2ef` | 三视图体素雕刻、外套分层、侧面眼睛修复 |
| `be1aba4` | 角色结构、体型切换和可见性迭代（历史阶段） |
| `045d369` | 原生体素龙、关节系统、程序化动画测试场景 |
| `256fc18` / `4860c3b` | 连续翼膜、降落调整、后腿收窄与地面骑龙合入 main |
| `7c4cd05` | 统一修长体型，弃用 Q 版 |
| `82f4a59` / `3db8f6f` | 膝/骑乘和结构/颜色试改，后续被部分撤回 |
| `5a9ea6e` / `d00018b` | 恢复服装细节与原骨骼、保留分层发束、恢复发色并局部清白点 |
| `ce2f348` | 飞行垂尾、骑乘按键分离 |
| `a10aa2b` | 空中惯性冲刺、转向与刹车 |
| `b42674a` / `70035d1` | 骑乘迎风延迟、起冲整体姿态与气流方向 |

本次实际读取了以下会话的相关用户消息、完成报告或研究输出；未将整段聊天、工具调试信息和凭据复制进仓库。Cindy 链接用于追溯，Web 端无需能打开它们即可依本文接手：

- [初始化 UrhoX 项目并了解体素支持](cindy://session/a30fd658-c42f-46df-a3d5-a13d846424f6)：人物从设计、三视图建模到局部恢复，以及最新飞行/冲刺迭代。
- [蓝白体素龙建模与关节运动原型](cindy://session/182645ac-5e91-4c51-881d-fe23ddc97cab)：原始目标、翼膜散开、厚度/弧度、后腿、降落与骑乘反馈。
- [糯米像素小人三视图与流程整理文档](cindy://session/712690d4-0486-4ebc-9fe5-d80e60efe4ee)：早期制作记录与 Mivo 服装拆解产物。
- 研究会话 `6738ceb5-140e-44e5-8a63-759cd323ca73`、`168b70df-1736-4cf5-8f24-3bcce8cf18a2`：关节、翼骨、闪烁与降落的参考分析。其角度、时长等建议属于当时的适配推断；最终参数以生产代码为准，不能将调研建议直接当成已落地功能。

本次文档整理只修改文档，不变更人物、龙的模型、玩法、动画或配置。
