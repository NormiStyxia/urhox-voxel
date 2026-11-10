# 蓝白体素巨龙：结构与动画说明

2026-11-10 更新。完整制作经过、人物流程和 Web Maker 续接见[交接文档](../体素人物与龙制作流程与WebMaker交接.md)。

入口：`scripts/dragon_main.lua`，或 `scripts/config.lua` 里 `START_SCENE = "dragon"`（改成 `"town"` 回到 VoxelTown）。
参考图：`art/dragon/ref/dragon_ref.webp`（比例按 1m = 100px 量取）。

## 技术路线

- **原生体素**：每根骨骼一个 `VoxelVolume`（`world:CreateVolume` 手建 grid，不 `Finalize`、无物理体，与 VoxelTown 视觉轮 / 旋翼同一做法），`SetParent` 到骨骼节点，由节点层级驱动。运行时不重建体素。
- **造型**：`DragonSpec` 用带骨骼标签的 SDF 体块（椭球 / 锥形胶囊 / 圆角盒 / 鳍片 / 菱形片）描述静止姿态，`DragonSculpt` 体素化：平滑并集求形体，按最近体块分配骨骼。当前 `overlap = false`，不再复制深层体素外壳，关节由挂父骨骼的内收关节球遮缝，避免共面闪烁。体素边长 0.08m（头 0.055m，翼 0.1m）；部件数、体素数与启动耗时以当前运行日志为准。
- **材质**：克隆调色板材质并去掉 `VOXELJITTER`（逐体素随机明暗在生物表面像噪点），保留 AO。调色板槽 40–54，翼膜与白甲带少量自发光；眼睛不发光。
- **翅膀**：翼根 → 前臂 → 腕 → 四指（各两节）+ 挂在前臂上的虚拟后缘指。翼膜是一整张体素阶梯外形的连续网格（`DragonMembrane.lua` + `Shaders/BLGL/DragonMembrane.shader`）：翼根 / 肘 / 腕 / 指关节 / 指尖跟随翼骨、贴体点跟随腰，组成 14 个控制三角形，每帧把三角形的仿射矩阵传给 GPU 变形顶点；相邻三角形共边，任何折叠角度下膜都连续、不会散开。

## 关节层级

```
root(全局位移/偏航) → body(COM 姿态层) → pelvis → waist → chest → neck1..4 → head → jaw
pelvis → tail1..8（tail8 = 菱形尾饰）        pelvis → legU → legL → legM → foot（髋/膝/跗/踝）
chest → armU → armL → hand（肩/肘/腕）       chest → wing → wfore → whand → wf1..4 → wf1m..4m
```

## 动画（`DragonAnimationController`）

三层互不覆盖：全局移动（root）/ 身体姿态（body）/ 关节 FK（各状态生成姿态表，按权重交叉淡化）→ 四肢 IK → 翼膜更新。

- 状态：IDLE WALK TURN SPREAD_WINGS TAKEOFF FLY GLIDE LAND ROAR；数据驱动表 `STATES`，每次切换新建混合层，旧层带自己的时间轴淡出。
- 步态（`DragonGait`）：四拍横向序列（左后→左前→右后→右前），占空比 0.66，支撑相足底钉在世界坐标；步频随速度 / 转身角速度变化。
- IK（`DragonIK`）：链平面对齐解析解（不反折、骨长恒定）+ soft IK（避开伸直奇异点）+ 前肢肩胛滑动（≤0.22m）。
- 翅膀展开分级：翼根 → 近端 → 远端 / 翼膜，收拢时顺序自然反转。
- 飞行：重力 + 升力指令 + 振翅相位升力波动的简化竖直模型，坡度转弯近似。**不是空气动力学仿真。**

## 扩展接口

- 部件：`rig.parts[bone] = { volume, node, voxels }`，`rig:GetPartVolume(name)`（体积 `destructible = true`）。
- 命中区：`DragonSpec.HIT_ZONES`（与视觉几何分离的简化球体），`rig:HitZoneAt(worldPoint)`。
- 挂点：`rig.sockets.mouth / throat / chestCore`（吐息 / 声音）。
- 新动作：在 `STATES` 里加一项（`blendIn / ground / enter / logic / pose`），姿态用 `DragonPoses` 的语义函数拼。

## 三种型号（`DragonVariants.lua`）

调试面板「型号」一栏切换（切换时整条龙重建，大号约 9 秒）。中号就是 `DragonSpec` 原样，不做任何变换；小号 / 大号由 `DragonVariants.Build(DEFS[id])` 从中号派生，不修改 `DragonSpec` 的数据。

| 型号 | 尺寸 | 可骑 | 特点 |
|------|------|------|------|
| 小号 · 幼龙 | 0.42 倍 | 否（宠物，跟随诺米） | 大头、短吻、圆身、短腿；竖长的 Q 版大眼（深色瞳孔 + 蓝 / 亮青渐变虹膜 + 前上大高光、后下小高光，高光微发光），眼睛后下方腮红；角 / 背刺 / 尾刃缩成小凸起；步频快、振翅快 |
| 中号 · 巨龙 | 1.0 倍 | 是 | 原龙 |
| 大号 · 古龙 | 1.5 倍 | 是 | 怪猎风格：低垂前伸的粗颈、压低的长头、后掠大角、粗壮前肢 + 肘刺 + 肩甲；后眼角上挑的杏仁眼（深色眼线 + 微发光琥珀金虹膜 + 竖瞳 + 一点高光），上方压一道深色眉骨；前后脚每趾两节可动骨骼（趾节 + 爪），走路会抓地 / 蹬地、落地前张爪、飞行时抓握 |

派生做法：

- **按骨骼形变**：每根骨骼沿主轴（指向子骨骼）给 `len`、垂直方向给 `thick` 缩放，可选 `rot` 改静止角度；子骨骼 pivot 随父骨骼映射，体块按所属骨骼映射，颜色函数逆映射回中号坐标。形变后把后脚、前肢子树对齐回地面。
- **标签操作**：`DragonSpec` 体块的 `tag`（eye / horn / spike / claw …）可在派生前删除或绕锚点缩放 / 旋转。
- **额外体块**：`extra` 用中号坐标添加，`_R` 骨骼自动镜像；`paint = true` 的体块只给已有体素换色 / 换骨骼，不增加形体（用于两种眼睛和腮红），可选 `mask(x, y, z)` 再裁出任意轮廓（杏仁眼）。型号可用 `palette` / `emissive` 覆盖调色板槽位，型号专用槽：55 腮红、56 虹膜、57 眼线 / 高光。
- **可动爪**：`digits` 配置把 `DragonSpec.DIGITS` 里的趾体块换成 `fdN_R/L → fdNc_R/L`（后脚 `hd*`）两级骨骼，控制器的 `ClawPose` 负责趾 / 爪姿态（一阶平滑）。
- **尺寸相关参数**：控制器按尺寸 S、√S（速度）、腿长比 H（身体起伏、抬脚高度）缩放；步频乘 `腿长^-0.4`；IK 肩胛滑动、骑乘 / 上龙距离、碰撞半径都随尺寸缩放。

## 自动检查

`tests/dragon/run_anim_check.sh`（需要 Maker CLI，`MAKER` 环境变量指向 `taptap-maker` 命令）：以固定 1/60s 步长跑完整演示序列，检查 IK 足底误差、支撑相滑步、骨长、反关节、关节单步跳变、穿地、左右翼对称、状态覆盖。


## 玩法模式：诺米骑龙（`DragonRide.lua`）

预览默认进入玩法模式（调试面板「显示 → 玩法模式」可关，关掉回到纯动画调试）：

- 诺米：`WASD` 移动（相对镜头方向），`Space` 跳跃，`Shift` 奔跑；运动学控制器，与龙身体做 2D 圆形推开。
- 靠近龙（约 3.6m 内）画面底部提示，按 `F` 骑上龙背（挂在 `saddle` 挂点，坐姿覆盖腿 / 臂骨骼）。
- 骑乘地面：`W` 前进、`A/D` 转向、`S` 停下；`Space` 起飞，`F` 下龙。
- 骑乘空中：`Space` 上升、`C` 下降、`G` 滑翔、`L` 降落、`F` 下龙。按住 `Shift` 惯性冲刺、松开留余速，`S` 主动刹车且优先于冲刺。`DragonFlight.lua` 分开身体朝向与实际航迹，并管理边界制动、迎风延迟；冲刺时联动龙身、翅膀、尾巴、骑手与镜头。
- 无人骑乘：龙自己溜达（待机 ↔ 走向随机目标点，偶尔咆哮），玩家靠近 7m 内会停下等待。
- 镜头：鼠标拖动旋转、滚轮缩放，自动跟随诺米 / 龙。


## 龙息（`DragonBreath.lua`）

中号「霜焰吐息」、大号「星陨龙息」，小号没有。按 `B`（玩法 / 骑乘 / 调试模式都可用）或调试面板「龙息」按钮触发；无人骑乘的中 / 大号溜达时偶尔也会自己吐息。

- 动作：`DragonBreath.Register(Controller)` 给控制器加一个外挂状态 `BREATH`（不改控制器源码，不进 `STATE_ORDER` 和演示序列）。姿态按型号关键帧生成，喷射阶段用头部俯仰反馈（`ctrl.breathAim`）让口部对准前方地面落点。
- 中号：后仰吸气 → 脚下六芒霜阵 + 口前雪花法阵 → 冰蓝霜焰粒子流 + 冰晶碎屑，落点霜雾、冰刺、霜环扩散。
- 大号：低伏蓄力 + 汇聚星屑 → 脚下七芒星阵、口前三层法阵依次亮起 → 紫金双层光束贯穿法阵，落点连续冲击环、火花、紫烟，镜头震动（`breath.shake`）。
- 法阵 / 冲击环：`Shaders/BLGL/DragonRune.shader`（程序化绘制，`style` 0 霜焰 / 1 星陨 / 2 冲击环）；光束：`Shaders/BLGL/DragonBeam.shader`。粒子贴图在 Lua 里生成，不依赖图片资源。
- 参数集中在 `DragonBreath.CFG`（时长、射程、配色、关键帧）。换型号时 `DragonTest.SetVariant` 会销毁并重建特效。
