# urhox-voxel — 时之遗迹与体素巨龙

TapTap Maker / **UrhoX** 引擎（Lua 5.4）的体素游戏项目。主场景是**时之遗迹**：诺米（Nomi）用时间系法术（碎时 / 冻结 / 回溯）解开遗迹机关，唤醒沉睡在龙庭中央的遗迹看守者——蓝白体素巨龙，并可以骑乘它。巨龙的动画与骑乘系统保留独立测试场景。

- 引擎：UrhoX（`stable` tag），坐标 **Y 向上 / Z 向前**，长度单位 **米**
- 玩法模式：单机（`@runtime.multiplayer.enabled = false`）
- 入口：`scripts/ruins_main.lua`（`project.json` 的 `entry`）；巨龙测试场景入口 `scripts/dragon_main.lua`

> 引擎知识目录 `engine-docs/`、`examples/`、`templates/`、`urhox-libs/`、`AGENTS.md` 由 TapTap Maker 的 ai-dev-kit 注入，**不入库**（见 `.gitignore`）。这些内容随 Maker 版本变化，本仓库只保存用户源码与资产。

---

## 运行

需要 TapTap Maker CLI（`taptap-maker`）：

```bash
# 本地窗口预览（不提交、不远端构建）
taptap-maker preview --target-dir .

# 只做运行时校验（跑若干帧，检查报错）
taptap-maker preview validate --target-dir . --mode validate \
  --entry ruins_main.lua --validate-frames 600 --nosound --json
```

也可以直接用 Runtime 启动：

```bash
UrhoXRuntime ruins_main.lua -tapcode_dir=<项目根>
```

### 两个场景

| 入口 | 场景 | 说明 |
| --- | --- | --- |
| `ruins_main.lua`（默认） | 时之遗迹 | `scripts/ruins/`：地形、建筑、谜题、时间法术、骑龙 |
| `dragon_main.lua` | 巨龙测试场景 | `scripts/dragon/`：动画调试面板、三种型号 |

---

## 操作

### 时之遗迹

| 按键 | 作用 |
| --- | --- |
| `WASD` / `Space` / `Shift` | 移动 / 跳 / 奔跑 |
| 鼠标 | 视角（点击画面锁定鼠标，`Esc` 释放） |
| 左键 | **碎时**：打碎带「时之印记」的物件或碎石；按住蓄力（0.5s 碎得更细，1s 碎成最小单元） |
| `E` | **冻结**：准星附近正在运动的时之碎块定格（可以踩） |
| `Q` | **回溯**：时之物件沿轨迹倒流、重组 |
| `F` | 龙苏醒后靠近骑乘 / 下龙（骑乘操作同下） |
| `Tab` | 远景相机 |
| `T`（按住） | 时间快进（昼夜循环） |
| `H` | 隐藏操作说明 |
| `F10` | 打开调试面板（默认隐藏）：时间滑条、黎明 / 正午 / 黄昏 / 夜晚跳转、「固定白天」「暂停时间」，以及巨龙动画测试 |

**谜题流程**（目标面板会逐步提示）：

1. **封门碎石**：南门被碎石堵住，用碎时打碎（古石硬度 4 打不动，碎石硬度 1）。
2. **断桥**：峡谷上的古桥碎落在谷底，对准任一碎块回溯，桥重组。
3. **悬石塔**：西侧塔顶放着「时之钥」，塔壁光滑爬不上。打碎梁端吊着的悬石，三块大碎块会飘到台阶位悬停约 2.5s，在这时冻结，踩着冻住的石块跳上塔顶拿钥匙。错过了就回溯悬石重来。
4. **四座时之碑**：内环四角的石碑碎倒在地，拿到钥匙后才能回溯。四碑复原后龙庭法阵点亮，巨龙苏醒，之后可以骑乘。

龙庭入口两侧的两只石瓮是练习用的时之物件，可以随便碎 / 冻 / 回溯。

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

---

## 目录结构

```
scripts/
  ruins_main.lua           时之遗迹入口
  dragon_main.lua          巨龙测试场景入口
  ruins/
    RuinsScene.lua         场景装配：灯光、诺米、法术、巨龙（沉睡 / 苏醒 / 骑乘）、关卡阶段、输入
    RuinsTerrain.lua       地形：中央龙庭盆地、内环、峡谷、外环、梯田山脊。显示层是平滑 Terrain 网格 + GrassField 草地，
                           碰撞层是隐藏的 0.5m 体素（角色 / 法术 / 碎块只和体素碰撞）
    DayNight.lua           昼夜循环：ProceduralSky + SkyLightCapture，驱动太阳 / 月光 / 天空 / 雾色
    GrassTufts.lua         GrassField 不可用（如 WebGL）时的兜底草簇
    RuinsBuild.lua         建筑：龙庭法阵地砖、祭坛、柱廊、穹顶残肋、外城墙与塔、北殿巨像、水渠、植被、浮岛
    RuinsPuzzles.lua       四个谜题 + 练习石瓮 + 时之钥；事件 gate / bridge / key / stele / awake
    TimeObject.lua         时之物件：完整 / 碎裂 / 冻结 / 回溯状态机，轨迹录制与倒放、重组
    TimeSpells.lua         数据驱动的法术表（碎时 / 冻结 / 回溯）+ 施法特效；魔法构筑的扩展点
    NomiController.lua     诺米角色控制（VoxelCharacterController + 第三人称相机 + 体素防穿墙）
    RuinsHUD.lua           目标面板、准星、法术栏、提示
    RuinsPalette.lua       遗迹调色板（槽位 100–149）
    VoxelBrush.lua         体素笔刷：盒 / 柱 / 球 / 椭球 / 自定义形状
    Noise.lua              整数哈希、值噪声、FBM、可复现随机数
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
assets/
  Shaders/BLGL/           自定义着色器：TimeVoxel（时之印记 / 冰冻 / 回溯）、RuinsVoxel（建筑风化细节）、
                          RuinsGround（程序化地面：草 / 土 / 石板 / 倾斜岩层 / 积雪）、HiddenVoxel（隐藏碰撞层）、
                          RuinsGrassTuft（兜底草簇）、DragonMembrane 等
  LightGroup/RuinsDay.xml  遗迹的灯光与雾
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
- **时间法术**：时之物件保存原始体素快照。碎时用加权 Voronoi 分块再拆成连通块，每块是一个动态 `VoxelVolume`；碎裂后每 1/20s 记录碎块位姿（最多 12s）。冻结把碎块换成静态体并切到冰材质；回溯按录下的轨迹倒放（没有轨迹的开局散落碎块走弧线依次飞回），最后合成回完整体。只有标了「时之印记」的物件能回溯，`TimeVoxel.shader` 用金色纹路 + 蓝色脉冲标出它们。
- **场景画面**：地面不再是体素色块。高度图 Terrain（0.5m 顶点）+ `RuinsGround.shader` 在世界空间程序化混色，崖面岩层倾斜并带噪声扭曲；草地用 GPU 草叶 `GrassField`（随风摆、诺米和龙走过会压倒），野花另一层。建筑统一 0.25m 体素，石块按错缝砌块取色，`RuinsVoxel.shader` 叠加跨体素连续的风化明暗。光照：4 级 CSM 太阳阴影 + 天空实时捕获的环境光 + 体积雾；昼夜循环（按住 T 快进）。
- **扩展点**：新法术往 `TimeSpells.SPELLS` 加条目；物件行为用 `TimeObject` 的字段与钩子（`canShatter` / `canRewind` / `fixedSeeds` / `shatterAim` / 事件监听）。
- 未实现：战斗、真实空气动力学（飞行是重力 + 升力指令 + 振翅相位波动的简化模型）。

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

## 远端

- `origin` → TapTap Maker 自动同步仓库（构建/提交时写入 `[timestamp] sync at ...` 提交）
- `github` → 本仓库，只读镜像用途

```bash
git pull                 # 从 Maker 取最新同步
git push github main     # 推到 GitHub
```
