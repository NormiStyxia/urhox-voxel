# 蓝白体素巨龙：结构与动画说明

入口：`scripts/dragon_main.lua`，或 `scripts/config.lua` 里 `START_SCENE = "dragon"`（改成 `"town"` 回到 VoxelTown）。
参考图：`art/dragon/ref/dragon_ref.webp`（比例按 1m = 100px 量取）。

## 技术路线

- **原生体素**：每根骨骼一个 `VoxelVolume`（`world:CreateVolume` 手建 grid，不 `Finalize`、无物理体，与 VoxelTown 视觉轮 / 旋翼同一做法），`SetParent` 到骨骼节点，由节点层级驱动。运行时不重建体素。
- **造型**：`DragonSpec` 用带骨骼标签的 SDF 体块（椭球 / 锥形胶囊 / 圆角盒 / 鳍片 / 菱形片）描述静止姿态，`DragonSculpt` 体素化：平滑并集求形体，按最近体块分配骨骼；关节附近复制一层「深层内部」体素（静止时被外表包住不可见，弯曲时填缝）。体素 0.08m（头 0.055m，翼 0.1m），约 2 万体素、95 个部件，启动构建约 0.6s。
- **材质**：克隆调色板材质并去掉 `VOXELJITTER`（逐体素随机明暗在生物表面像噪点），保留 AO。调色板槽 40–54，眼睛与翼膜带少量自发光（翼膜透光感）。
- **翅膀**：翼根 → 前臂 → 腕 → 四指（各两节）+ 挂在前臂上的虚拟后缘指。翼膜拆成 1 体素厚的扇形薄片，每片旋转 = 两侧翼骨旋转的球面插值（`DragonRig:UpdateMembranes`），收拢时叠压、不撕开；展开度 `fan ≤ 1` 保证不出洞。

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

## 自动检查

`tests/dragon/run_anim_check.sh`（需要 Maker CLI，`MAKER` 环境变量指向 `taptap-maker` 命令）：以固定 1/60s 步长跑完整演示序列，检查 IK 足底误差、支撑相滑步、骨长、反关节、关节单步跳变、穿地、左右翼对称、状态覆盖。
