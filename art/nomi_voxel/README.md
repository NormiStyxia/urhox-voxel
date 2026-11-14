# 诺米修长版：局部撤回与验证

2026-11-10。衣服简化丢失设计细节，本轮选择性撤回，不重写 Git 历史。

## 当前保留与恢复范围

- 只使用修长版，保留 7c4cd05 的统一 BlockCharacter.SLENDER 配置；Q 版与 M 切换入口继续移除。
- 非头发部分的几何和顶点 RGB 精确恢复到 4860c3b，包括领口、袖口、裙褶、靴子、外套破边与配色。
- 保留 3db8f6f 的头部及独立前后发束；面部保护区的几何和 RGB 不变。
- 骨骼恢复原来的 16 根。BlockCharacter 与 DragonRide 恢复 7c4cd05 版本，不再包含被撤回的膝关节与骑乘调整。
- 此模型的衣服花纹使用顶点色；上轮细节损失来自几何替换和重新着色，并非贴图漏加载。

## 可重复生成与精确比对

依赖 Python 3、numpy、scipy、Pillow。在项目根运行：

    python3 art/nomi_voxel/voxelize.py
    python3 art/nomi_voxel/check_mesh.py

voxelize.py 负责原三视图采样；refine.py 只精修头部和发束，其余部分原样透传。
approved_head.json 是原头部保护基准，勿用新结果覆盖。
rollback_baseline.json 保存原衣服/四肢、认可的头发以及原骨骼的比对基准。
检查包括完整头部几何、544 个面部保护区三角形 RGB、非头发几何/RGB、认可的头发和原骨骼表。

preview_3d.png / compare.png 为当前修长模型离线预览；早期采样图片不代表当前游戏画面。
.tmp/nomi-review/ 为本地证据，不提交。离线预览不模拟游戏 PBR、投影和后处理。

## 无头运行检查

将 rig_validate.lua 临时复制到 scripts/_nomi_rig_validate.lua，通过 Maker 验证：

    entry: dragon_main.lua
    test: _nomi_rig_validate.lua
    mode: validate
    frames: 120
    timeout_seconds: 45

验证后删除临时脚本，不启动窗口。脚本在独立 Scene 中实例化生产角色，
检查原 16 骨骼、修长配置、无 Q 切换和待机/行走/跑步/跳跃/下蹲调用。
它是回退后的加载与运行检查，不是腿部接缝、骑乘对齐或衣物碰撞的视觉验收。

## 后续约束

旧衣服的杂色、阶梯形结构和原动画问题随局部撤回保留，尚待针对性修复。
后续清理要保留领口、装饰、裙褶、破边与靴子设计，只清除误采样噪点和不合理粘连，
不得再次以大块纯色网格替换整件衣服。
参考仍是 art/nomi_ysm/ref/ref_ysm_navy.png；用户提到的外套/内衬拆件图尚未定位。

## 2026-11-10：恢复发色细节与局部白点清理

在 5a9ea6e 基础上，完整恢复 approved_head.json 的头部 RGB（包括发缕、编发和发饰配色）。
前后独立发束的几何和颜色保持不变；所有衣服和身体几何、骨骼、比例、动画均未修改。
仅清理圈定外套胸侧、内侧袖面及破边尾片上的误采样浅色，不改领口、袖口、内裙、袜口和靴子。
detail_cleanup.json 记录逐面颜色改动；check_mesh.py 将这些改动反向还原后与原服装摘要核对，
确保未圈定细节不被一并删掉，并核对完整头部原始 RGB 和已认可的独立发束。

## 2026-11-10：精修（polish.py，只改颜色）

起因：游戏截图里脸部发脏、头发有意义不明的暗点、黄色领结中间有暗点。原因是采样时参考图自身的明暗被写进了顶点色，
游戏里实时光照和刘海投影又叠加一次；另有外套藏青色串进头发和领结。

`refine.finish` 最后调用 `polish.polish`：把面拆成单格改色后重新合并，几何、骨骼不动。规则：

1. 头部的棕灰阴影色和串进来的藏青色 → 取周围干净邻居的多数色（靠近皮肤则取肤色）；眼睛本身（睫毛、瞳孔、高光）受保护。
   额头刘海缝里的"阴影肤色"换成正常肤色。
2. 头发里不超过 3 格的孤立暗点 → 周围发色；更长的发丝线保留。
3. 领结区域里的藏青 / 肤色 / 棕灰 → 金色（需要至少两格金色邻居）；结头处残留的肤色 → 白色水手领。
   领结上的藏青环带、领带尾之间的白色分叉是设计，保留。
4. 头部较暗的发色只保留 60% 的变暗幅度（发丝纹理还在，暗部交给实时光照）。

每一格改动记录在 `polish_edits.json`。`check_mesh.py` 改为：撤销这些改动后，按单格与 `polish_baseline.json`
（145d608 的模型，当时已通过原有的头部 / 面部保护区 / 服装 / 发束 / 骨骼校验）逐格比对，必须完全一致。
原有校验依赖合并后的矩形面顺序，精修重新合并后不再适用，由这份单格基线代替。

    python3 art/nomi_voxel/voxelize.py
    cd art/nomi_voxel && python3 check_mesh.py

## 2026-11-14：可选双肘绑定（默认关闭）

新增生成链：原采样 → refine.finish → **按已批准 polish_edits.json 重放颜色** →
`elbow.split` 重分上/下臂并封口 → `scripts/game/NomiVoxelDataElbow.lua`。
旧 NomiVoxelData.lua、approved_head / rollback_baseline / detail_cleanup / polish_baseline / polish_edits
均不由这条分支写入，旧的无参数生成命令行为不变。不要手改两份 Lua 数据。

临时环境与完整重生成命令（项目根执行，不安装到系统 Python）：

~~~sh
python3 -m venv /tmp/nomi-elbow-venv
/tmp/nomi-elbow-venv/bin/pip install numpy scipy Pillow lupa shapely
/tmp/nomi-elbow-venv/bin/python art/nomi_voxel/voxelize.py --elbows
/tmp/nomi-elbow-venv/bin/python tests/nomi/elbow_geometry.py
/tmp/nomi-elbow-venv/bin/python tests/nomi/run_offline.py
~~~

numpy/scipy/Pillow 用于生成；shapely 只用于独立面覆盖验算；lupa.lua54 用于纯 Lua 测试。
最后一条也跑已有 combat / ruins 独立测试，故会如实报告与本次修改无关的既有失败。
只运行生成命令会更新数据和 measurements.json；检查命令更新全部预览与 checks.json。
这些都是离线工具，不启动引擎、不构建、不提交。

**为什么重放颜色记录：**本机重新计算 polish 的 KD-tree 邻居投票时，SciPy 版本间
等距邻居顺序不同，曾使部分头发面选择不同颜色。双肘分支改为按已批准逐面日志重放，
逐条核对 before RGB，几何或输入色不匹配便失败；不把新投票结果写回认可基准。
不读取生成后的 Lua 作为生成源；旧 Lua 仅供独立检查脚本比对。

**轴心测量：**两侧肤色手部的最高点均为 y=35，袖子几何最高点为 y=49；
以袖段几何中心 y=42 为候选，将切面移到靠手侧半格 y=41.5，避免与原共面面片争归属。
切面闭环包围盒：右 x=[9,16.5]，左 x=[-16.5,-9]，z=[-6,3]。
由此肘轴为 `(12.75,41.5,-1.5)` / `(-12.75,41.5,-1.5)`，单位是原始体素坐标，
乘 0.022 得米，再应用 SLENDER 的 X/Z 收窄。它是根据现有宽袖几何选择的绑定轴，
不是解剖扫描结果；没有取骨表肩轴与手掌的中点。完整轮廓、肤色边界和封口清单见
`elbow_preview/measurements.json`。

保留 arm_right/arm_left 作上臂，新增 forearm_right/forearm_left 作其子骨。
四边形跨 y=41.5 时裁成两片，三角形用平面裁剪并重新三角化；交线闭环耳切封口，
颜色取现有袖色，不增调色板、不覆盖旧衣服面。原斜面有零面积悬挂边，封口建环时剔除
不围成面积的枝杈，但保留原外表面。出现多闭环/孔洞会报错，不能默默填成实心。

**验收定义：**新增内部封口本来就不在旧网格中，所以“逐面一致”指外表面位置、
覆盖、朝向、颜色一致；不能要求包含内部封口后的面列表字节数相同。
`tests/nomi/elbow_geometry.py` 独立读取两份导出数据，按半格检查四边形的逐体素面覆盖，
按带朝向/颜色的平面集合和面积检查裁剪三角形，并核对非手臂逐行相同、palette 相同。
`elbow_rig.lua` 在 Lua 5.4 mock 中对比旧版 BlockCharacter 的所有默认顶点/颜色/姿态，
检验挂点复用、层级、归零、45°/90°/120°前弯与等半径手掌轨迹。

**仍需验收：**封口面积各 67.5 平方体素、缺面为 0，不等于弯曲后轮廓无凹口。
SLENDER 下两段对应边缘顶点的最大间距，45°/90°/120°分别约 6.97/12.88/15.78 cm；
这是旋转后的对应点间距，**不是最短裂缝宽度**。肘轴保持接触；半径 2.5 体素邻域的
552 个原实体采样点中，分别有 54/138/178 点在弯折后位于两段实体之外，说明刚体
外弯侧凹口存在。预览已显示封口，但没有证明所有视角不透背景；不能据此开启正式开关。
所有图片为软件投影，不模拟 UrhoX 剔除、阴影、材质或 Web 性能。

预览：`elbow_preview/contact_sheet.png`（0/45/90/120°，每行正/斜/侧/背四视图），
分图 `bend_000.png`、`bend_045.png`、`bend_090.png`、`bend_120.png`；检查结果 `checks.json`。
调用方迁移与开关步骤见 `docs/人物肘部绑定迁移-2026-11-14.md`。
