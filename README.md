# urhox-voxel — 体素小镇与体素巨龙

TapTap Maker / **UrhoX** 引擎（Lua 5.4）的体素游戏项目。当前主线是**蓝白体素巨龙的动画与骑乘**：诺米（Nomi）角色、原生体素 SDF 龙、程序化骨架/IK/步态、连续翼膜；底座是从 VoxelTown 体素物理脚手架继承来的可破坏小镇沙盒。

- 引擎：UrhoX（`stable` tag），坐标 **Y 向上 / Z 向前**，长度单位 **米**
- 玩法模式：单机（`@runtime.multiplayer.enabled = false`）
- 入口：`scripts/dragon_main.lua`（`project.json` 的 `entry`）

> 引擎知识目录 `engine-docs/`、`examples/`、`templates/`、`urhox-libs/`、`AGENTS.md` 由 TapTap Maker 的 ai-dev-kit 注入，**不入库**（见 `.gitignore`）。这些内容随 Maker 版本变化，本仓库只保存用户源码与资产。

---

## 运行

需要 TapTap Maker CLI（`taptap-maker`）：

```bash
# 本地窗口预览（不提交、不远端构建）
taptap-maker preview --target-dir .

# 只做运行时校验（跑若干帧，检查报错）
taptap-maker preview validate --target-dir . --mode validate \
  --entry dragon_main.lua --validate-frames 600 --nosound --json
```

也可以直接用 Runtime 启动：

```bash
UrhoXRuntime dragon_main.lua -tapcode_dir=<项目根>
```

### 两个场景

`scripts/config.lua` 里的 `START_SCENE` 决定 `main.lua` 的去向：

| 值 | 场景 | 说明 |
| --- | --- | --- |
| `"dragon"`（当前） | 巨龙测试场景 | `scripts/dragon/`，独立入口 `scripts/dragon_main.lua` |
| `"town"` | VoxelTown 沙盒 | 可破坏建筑、可解体载具、四种破坏工具、昼夜与水坑 |

---

## 操作

### 巨龙场景 · 玩法模式（诺米骑龙）

| 按键 | 作用 |
| --- | --- |
| `WASD` | 移动诺米 |
| `Space` | 跳 |
| `Shift` | 奔跑 |
| `F` | 靠近龙时骑乘 / 骑乘时下龙 |
| 骑乘后 `W` / `A` `D` / `S` | 前进 / 转向 / 刹车 |
| 骑乘后 `Shift` | 空中冲刺 |
| 骑乘后 `Space` / `C` | 起飞、上升 / 下降 |
| 骑乘后 `G` / `L` | 滑翔 / 降落 |

### 巨龙场景 · 调试模式

`W` `S` 加减速，`A` `D` 转向，`Q` `E` 原地转身，`Space` 起飞/爬升，`C` 下降，`G` 滑翔，`L` 降落，`R` 咆哮，`B` 龙息，`T` 展翼/收翼，`P` 暂停，`N` 单步。

相机：右键/左键拖动旋转，滚轮缩放，中键或 `Shift`+左键平移，`1` `2` `3` `4` 正/侧/背/斜视角，`F` 跟随。
左侧调试面板可切**三种型号**（小号幼龙 / 中号巨龙 / 大号古龙）、开关骨架、命中区、翼膜控制网、落足点，并做单关节 FK 测试。

### VoxelTown 沙盒

`WASD` 移动，`Space` 跳，`Shift` 跑，`Q` 切工具并用 `1`–`4` 选炸药/散弹枪/喷漆/喷枪，右键拖拽抓取，`F` 进入载具，`N` 昼夜切换，`P` 街道水坑开关，`B` 演示载具解体。

---

## 目录结构

```
scripts/
  dragon_main.lua          巨龙测试场景入口
  main.lua                 VoxelTown 入口（昼夜、天空、后处理、水坑）
  config.lua               全局常量：调色板槽位、硬度、手感、工具参数
  player.lua               诺米角色控制（走跑跳、游泳、上下载具）
  tools.lua                四种破坏工具与引擎级抓取约束
  town.lua                 小镇场景组装
  vehicles.lua             可解体载具（Assembly）
  dragon/
    DragonTest.lua         场景装配、相机、调试面板接线
    DragonSpec.lua         龙的 SDF 体块描述（带骨骼标签）+ 命中区 + 挂点
    DragonSculpt.lua       SDF → 体素化，按最近体块分配骨骼
    DragonRig.lua          Node 骨骼层级，每骨一个 VoxelVolume
    DragonVariants.lua     小号/大号由中号派生（按骨骼形变 + 标签操作）
    DragonAnimationController.lua  九状态混合层
    DragonPoses.lua        语义姿态函数表
    DragonGait.lua         四拍横向步态
    DragonIK.lua           四肢解析 IK + soft IK + 肩胛滑动
    DragonMembrane.lua     连续翼膜网格（14 控制三角形）
    DragonRide.lua         骑乘状态、坐骑控制、下龙
    DragonBreath.lua       龙息
    DragonDebugUI.lua      urhox-libs/UI 调试面板
    DragonPose.lua / DragonFlight.lua   姿态辅助与飞行模型
  game/
    NomiVoxelData.lua      诺米体素数据（离线雕刻导出，~400KB）
    NomiModelData.lua      诺米模型数据
    BlockCharacter.lua     体素人物运行时（每骨一个 CustomGeometry）
    StateMachine.lua       人物状态机
assets/
  models/                  .vox 模型（含 teardown 系列、房屋、载具）
  Shaders/BLGL/           含 DragonMembrane.shader、DragonRune.shader 等自定义着色器
  Materials/ Textures/ LightGroup/
art/                       参考图与离线生成脚本产物（诺米三视图、龙参考）
docs/                      制作记录与交接文档（见下）
tests/                     自动检查脚本
.project/                  Maker 项目配置（project.json / settings.json / resources.json）
```

---

## 技术路线（简述）

- **龙的身体**：`DragonSpec` 用带骨骼标签的 SDF 体块（椭球 / 锥形胶囊 / 圆角盒 / 鳍片）描述静止姿态，`DragonSculpt` 体素化后每根骨骼生成一个 `VoxelVolume`（不 `Finalize`、无物理体），挂到 Node 骨骼层级上，由层级驱动。体素边长约 0.08m（头 0.055m，翼 0.1m）。
- **翼膜**：不是体素，是一整张连续网格。翼根/肘/腕/指关节/指尖跟随翼骨、贴体点跟随腰，组成 14 个控制三角形，每帧把仿射矩阵传给 GPU 变形顶点，任何折叠角度下膜都连续。
- **动画**：三层互不覆盖 —— 全局移动（root）/ 身体姿态（body）/ 关节 FK（各状态姿态表按权重交叉淡化）→ 四肢 IK → 翼膜更新。状态：`IDLE WALK TURN SPREAD_WINGS TAKEOFF FLY GLIDE LAND ROAR`。
- **人物**：离线体素雕刻（Python / NumPy）导出顶点色网格 → `NomiVoxelData.lua` → `BlockCharacter` 每骨骼 `CustomGeometry` → 顶点色 PBR SurfaceShader。只保留修长版。
- 未实现：完整战斗、体素碎裂重组、真实空气动力学（飞行是重力 + 升力指令 + 振翅相位波动的简化模型）。

---

## 文档

| 文档 | 内容 |
| --- | --- |
| [`docs/体素人物与龙制作流程与WebMaker交接.md`](docs/体素人物与龙制作流程与WebMaker交接.md) | **接手先读**。跨会话制作经过、当前实现、文件索引、验证方式、已知问题 |
| [`docs/dragon/README.md`](docs/dragon/README.md) | 龙的结构、关节层级、动画与三种型号的派生规则 |
| [`docs/nomi/诺米像素小人制作记录.md`](docs/nomi/诺米像素小人制作记录.md) | 诺米早期体素制作记录（历史） |
| [`art/nomi_voxel/README.md`](art/nomi_voxel/README.md) | 诺米生成器与局部回退说明 |

## 自动检查

`tests/dragon/run_anim_check.sh` 以固定 1/60s 步长跑完整演示序列（约 62 秒动画），检查 IK 足底误差、支撑相滑步、骨长、反关节、关节单步跳变、穿地、左右翼对称、状态覆盖。需要 Maker CLI，`MAKER` 环境变量指向 `taptap-maker`：

```bash
tests/dragon/run_anim_check.sh
```

`tests/dragon_controls.py`、`dragon_sprint.py`、`dragon_charge.py`、`dragon_wind.py` 是早期的动作/手感数值推演脚本。

## 资产归属

`assets/models/*.vox` 中的 mmmm 系列来自 Mini Mike's Metro Minis（作者 Mike Judge），**CC BY 4.0**，未修改。完整声明见 [`ATTRIBUTION-voxeltown.md`](ATTRIBUTION-voxeltown.md)。

## 远端

- `origin` → TapTap Maker 自动同步仓库（构建/提交时写入 `[timestamp] sync at ...` 提交）
- `github` → 本仓库，只读镜像用途

```bash
git pull                 # 从 Maker 取最新同步
git push github main     # 推到 GitHub
```
