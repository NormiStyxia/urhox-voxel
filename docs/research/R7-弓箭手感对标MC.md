# R7：弓箭手感对标 Minecraft 与开源实现调研

日期：2026-11-15。范围：只读代码、公开资料与文档规格；没有修改游戏代码/资源、提交、构建或启动 Runtime。当前画面、音频延迟和触屏手感均未实测。

## 1. 结论与适用顺序

建议把弓的核心改为“连续拉力、释放即发射、明显抛物线”，而不是再加强震屏。首批五件事：

1. 由三档箭速改为连续 `f=(u²+2u)/3`；标准弓 1.00s 满蓄，满蓄判据统一为 `u=1`。注意公式里是 **2u**，不是 u。
2. 最短输入不足阈值直接弃箭，不再把短点按排队到 120ms 后发射；释放快照与箭、弦、声音共用唯一 fire 事件。
3. 采用 MC 基准 60m/s、20m/s²、空气每 50ms 保留 0.99 速度；现有 44m/s、6m/s² 无阻力更像低重力飞镖。
4. 镜头由 200ms 内无条件 55→43°，改为随拉力时间平方收窄，标准弓满蓄 46.75°；重做真实准星附近减速，保持准星位置稳定。
5. 右手目标约束到实际弦扣；上弦箭与飞行箭使用同一杆/羽/簇造型，补弦回弹及命中短抖，不先增加粒子数量。

**本文是待 Lead 纳入主方案的变更规格，不会自行覆盖现有契约。** 已读主方案 §5、§13–§20，并发现后续 §21/§22 已覆盖旧镜头：当前 55→43°/200ms 是最新方案与实现一致的设计，不应误判成“没遵守 §20 的 −5°”。本建议明确提出替换这一设计。后续开发前，先把本节采用项写入主方案新修订，避免不同 worker 各读一个版本。

证据分类：**[MC]** 为锁定版本源码/原版资源；**[开源]** 为仓库实际实现；**[现状]** 为本地静态代码；**[建议]** 为适配本游戏的首轮参数，不能冒充 MC 原值或已验收结果。

## 2. Minecraft 基准、版本与来源

### 2.1 版本锁定与来源等级

精确算法基准锁定 **Java 1.20.3-pre1**，源码镜像 commit `6ac5fe18be48a7395be84148be051908111d6772`；仓库 `version.json` 明确写此版本。模型资源另核对 Java **1.20.3**。本报告不声称这些常量涵盖 2026 年所有 Java/Bedrock 版本。

- Minecraft 是专有游戏；下面的反编译源码镜像只作为机制核对证据，**不列入开源项目，不复制其代码或素材**。可用 Mojang 命名配合 [Mappings 1.20.3 BowItem](https://mappings.dev/1.20.3/net/minecraft/world/item/BowItem.html) 定位同类 API；映射页面用于名称，不当成算法源码。
- [Minecraft Wiki / Bow](https://minecraft.wiki/w/Bow)、[Arrow](https://minecraft.wiki/w/Arrow) 是社区权威资料，访问日 2026-11-15；浏览器读取成功，普通静态抓取 403。当前 Wiki 已有新版本条目，不能用其未分版本的汇总表反推锁定源码。
- Java 与 Bedrock 的音效 ID、耐久和部分弹道/伤害表有差异，本规格采用 Java 基准。

下列链接均已通过 GitHub 插件读取相应文件；其中源码镜像固定到上述 commit：

| 标记 | 对应文件 / 核对内容 |
|---|---|
| MC1 | [BowItem.java](https://github.com/mahtomedi/minecraft/blob/6ac5fe18be48a7395be84148be051908111d6772/src/main/java/net/minecraft/world/item/BowItem.java)：`getPowerForTime`、`releaseUsing`、箭速、暴击、放箭声 |
| MC2 | [Projectile.java](https://github.com/mahtomedi/minecraft/blob/6ac5fe18be48a7395be84148be051908111d6772/src/main/java/net/minecraft/world/entity/projectile/Projectile.java)：`shoot`、`shootFromRotation`、散布与继承射手速度 |
| MC3 | [AbstractArrow.java](https://github.com/mahtomedi/minecraft/blob/6ac5fe18be48a7395be84148be051908111d6772/src/main/java/net/minecraft/world/entity/projectile/AbstractArrow.java)：`tick`、`onHitEntity`、`onHitBlock`、`getWaterInertia` |
| MC4 | [AbstractClientPlayer.java](https://github.com/mahtomedi/minecraft/blob/6ac5fe18be48a7395be84148be051908111d6772/src/main/java/net/minecraft/client/player/AbstractClientPlayer.java)：`getFieldOfViewModifier` |
| MC5 | [LocalPlayer.java](https://github.com/mahtomedi/minecraft/blob/6ac5fe18be48a7395be84148be051908111d6772/src/main/java/net/minecraft/client/player/LocalPlayer.java)：`aiStep` 的使用物品减速、禁止起跑 |
| MC6 | [ItemInHandRenderer.java](https://github.com/mahtomedi/minecraft/blob/6ac5fe18be48a7395be84148be051908111d6772/src/main/java/net/minecraft/client/renderer/ItemInHandRenderer.java)：`BOW` 第一人称分支 |
| MC7 | [HumanoidModel.java](https://github.com/mahtomedi/minecraft/blob/6ac5fe18be48a7395be84148be051908111d6772/src/main/java/net/minecraft/client/model/HumanoidModel.java)：`BOW_AND_ARROW` 双臂姿态 |
| MC8 | [ItemProperties.java](https://github.com/mahtomedi/minecraft/blob/6ac5fe18be48a7395be84148be051908111d6772/src/main/java/net/minecraft/client/renderer/item/ItemProperties.java) + [原版 bow.json / 1.20.3](https://github.com/InventivetalentDev/minecraft-assets/blob/1.20.3/assets/minecraft/models/item/bow.json)：`pull`/`pulling` 与模型切换 |
| MC9 | [ArrowRenderer.java](https://github.com/mahtomedi/minecraft/blob/6ac5fe18be48a7395be84148be051908111d6772/src/main/java/net/minecraft/client/renderer/entity/ArrowRenderer.java) + [StuckInBodyLayer.java](https://github.com/mahtomedi/minecraft/blob/6ac5fe18be48a7395be84148be051908111d6772/src/main/java/net/minecraft/client/renderer/entity/layers/StuckInBodyLayer.java)：插入抖动、目标身上显示的箭 |
| MC10 | [LivingEntity.java](https://github.com/mahtomedi/minecraft/blob/6ac5fe18be48a7395be84148be051908111d6772/src/main/java/net/minecraft/world/entity/LivingEntity.java)：一般受伤击退，区别于 Punch 附加速度 |

### 2.2 拉弓、阈值与速度：精确核对

[MC1] 在正常 20 TPS 下：`u=ticks/20`，`f=min(1,(u*u+2*u)/3)`。20 tick = **1.00s** 满蓄；继续持有不继续加伤/加速。`f<0.1` 时不产生箭、不消耗弹药、不播放放箭声。

这里的 **0.1 是无量纲拉力阈值，不是 0.1 秒**。连续时间解为 `u>=sqrt(1.3)-1≈0.140175`；整数 tick 下 2 tick 的 f=0.07 不发射，3 tick 的 f=0.1075 可发射，即通常最少 **150ms**。输入落在 tick 边界的观察时间会有量化差异。

初始标称速度 `3*f block/tick`；按 1 block=1m、20 tick/s 换算是 **60f m/s**。不能把 3 当作 3m/s，也不能把 Wiki 中约 53m/s 的飞行观测值替代发射常量。

| 持有时间 | u | f | 标称初速 m/s | 说明 |
|---:|---:|---:|---:|---|
| 100ms / 2 tick | .10 | .0700 | 4.20 | 不发射 |
| 150ms / 3 tick | .15 | .1075 | 6.45 | 刚超过阈值 |
| 250ms / 5 tick | .25 | .1875 | 11.25 | 可落在脚前的短射 |
| 500ms / 10 tick | .50 | .416667 | 25.00 | 半时间不等于半拉力 |
| 650ms / 13 tick | .65 | .574167 | 34.45 | 第二张拉弓模型开始 |
| 900ms / 18 tick | .90 | .8700 | 52.20 | 最终拉弓模型已显示，但还不是暴击 |
| 1000ms / 20 tick | 1 | 1 | 60.00 | `f==1` 标记 critical |

[MC2] `shootFromRotation` 还继承射手水平速度；射手离地时加竖直速度，站地时不加竖直速度。因此实际初速不总是恰好 60，移动射击也不应据标称值断言异常。原版没有为玩家自动提前量、重力补偿或吸附弱点。

### 2.3 弹道、散布与判定

[MC2/MC3] 无碰撞、无特殊状态时，**先用当前速度移位，再衰减，再加重力**。设 p 单位 m、v 单位 m/tick：

```text
p[n+1] = p[n] + v[n]
v[n+1] = r * v[n] + (0,-0.05,0)
r = 0.99（空气）；r = 0.60（水，普通箭）
```

- `0.05 block/tick²` 对应 **20m/s²**，不是 1m/s²；速度单位和时间单位都必须换算。空气连续等效阻尼 `λ=-20ln(.99)=0.2010067 s⁻¹`，水中 `λ=-20ln(.6)=10.216512 s⁻¹`。
- 水中会生成气泡。水的 .60 来自普通箭 `getWaterInertia`；不能借用其他投射物或 Cuberite 的 .80。
- 飞行按线段查询方块与实体；实体路径会考虑碰撞范围，不能把渲染箭杆的体积当成判定模型。墙/目标的实际接触顺序很重要。
- 满蓄不会让原版普通弓穿透两个敌人；Piercing 是另一机制。本项目原“满档穿一个小怪”是自定义。

[MC2] 该锁定版本的 inaccuracy=**1.0**：对单位射向三个分量各加一个 `triangle(0,0.0172275*inaccuracy)` 随机值，再乘标称速度，**没有再次归一化**。三角分布支持区间是 ±0.0172275；每个横向分量标准差约 .007033，对应小角度约 **0.403°**。这不是“固定 1° 锥角”，也不是每帧重抽随机。较早版本常见 Gaussian×.0075 的实现，不应与本版本混写。

说明：源码镜像未随本报告再追到 `RandomSource.triangle` 定义；三角分布的标准差换算按 Minecraft 的 `(rand-rand)*deviation` 定义，后续若换版本或分布必须重核。

### 2.4 伤害、暴击、击退

[MC1/MC3] 普通箭 baseDamage=2.0；**在命中时**取瞬时速度长度 s（m/tick），`D=ceil(s*baseDamage)`。满蓄标记 critical 后加整数随机量：`randomInt(0..floor(D/2)+1)`，上界包含，原调用为 `nextInt(D/2+2)`。并非固定 ×1.5。Power 等级 L>0 时 baseDamage 额外加 `(L+1)/2`。

无散布、静止射手、标称 s=3 的示例：D=6，暴击总伤 6..10；真实散布未归一化、继承速度与 ceil 能使基础项到 7，出现 11 等结果。不能用“近距离满蓄必定固定 9 点”作为原版规则。飞远减速可能减伤，向下运动也可能提高总速。Minecraft 普通弓没有本项目的“头/核心 ×1.6”。

[MC3/MC10] 普通伤害处理在允许击退的情况下用一般 `knockback(0.4,...)`，受抗性、现有速度、地面状态影响。Punch L 另外沿水平射向加 `0.6*L*(1-抗性)` m/tick 的速度，并加竖直 .1m/tick。**这些是速度/处理参数，不是固定击退 .4m 或 .6m**；不能不经角色运动求解直接移植。Boss/免疫标签还可改变结果。

### 2.5 移速、FOV 与动画

- [MC5] 使用弓时，非乘客玩家的左右/前后输入分量各 **×0.2**，并清起跑计时；不能起跑。这是输入缩放，受地面摩擦和已有速度影响，不承诺瞬间速度恰为走速 20%。不要误用潜行 .3 替代使用物品 .2。
- [MC4] 弓的 FOV modifier 为 `1-.15*min(ticks/20,1)^2`。只考虑弓、FOV Effects=100%、普通移动基准时满蓄为 **0.85**；以 55° 基准举例目标 46.75°。这不是射击力度 f 的平方，也不是固定 −15°。最终 FOV 还有飞行/移速倍率、客户端平滑和用户设置。原版并没有与该公式绑定的本项目“灵敏度 ×.60”。
- [MC8] 共有 **4 个外观**：静置 bow，以及 bow_pulling_0/1/2。拉弓立即用 pulling_0，`pull>=.65` 切 pulling_1，`pull>=.9` 切 pulling_2；pull=ticks/20。视觉最终档 900ms，暴击就绪 1000ms，二者不同。不是 4 级伤害。
- [MC6] 第一人称以持物矩阵变换、同一 f 曲线、轻微抖动表现拉弓；局部 Z 位移 .04f、Z 向缩放 1+.2f，f>.1 有小幅 Y 抖。模型显示单位不是本项目世界空间米，**不要把这些矩阵数直接抄为 4cm 手掌位移**。
- [MC7] 第三人称是无肘的双臂 BOW_AND_ARROW 姿态：双臂 xRot≈−π/2+头俯仰，两个臂的 yaw 有 .1/.4 弧度偏置并随头朝向。它不是完整“右手真实抓住动态弦”的两骨 IK。左右持手会镜像；本项目固定左手持弓、右手拉弦，不照搬 MC 默认右手配置的符号。
- 因此可以学 MC 的“块状身体＋清晰平举双臂”，但本项目 3D 立体弦/箭与 MC 平面道具不同，需要自己的几何接触约束。

### 2.6 声音、插箭、尾迹与弹跳

[MC1/MC3/MC9 + Wiki] 普通弓发射声 `entity.arrow.shoot`；音高 `1/(R*.4+1.2)+.5f`（R∈[0,1)），音量 1.0。普通撞击 `entity.arrow.hit`；命中玩家可向射手发送“击中玩家”提示事件，对应命中提示音。**该原版 Bow 使用路径没有 bow_draw 循环或 bow_full 提示音**，本项目保留这两者属于可读性增强。

- 撞实心方块进入 inGround，shakeTime=7 tick，约 **350ms** 的衰减摆动；不是持续弹跳。插入后不再 critical、清穿透。
- 通常实体受伤成功后真实箭实体被销毁，目标 arrowCount 增加；StuckInBodyLayer 按目标 ID 固定随机身体部位/位置生成显示箭，**不等于真实接触位置的骨骼挂接**。本项目已有按实际部位挂接，保留它更好。
- 受伤被拒绝时存在反向 ×−0.1 的回弹路径；部分专门反射箭的实体还有 deflect 路径。普通墙命中不应套用“全部反弹”。
- critical 飞行有 CRIT 粒子，源码每 tick 四个采样点；水中有气泡。普通箭没有必须复制的“恒定发光箭羽长尾”或高频旋转尾迹。箭羽属于箭本体，方向跟随速度，插入抖动另算。
- 箭可回收与原版长时间存留是生存经济内容，本项目无限箭、12 槽池，继续用短插箭生命周期，不扩展拾取/耐久。

## 3. 开源实现：四个实际读取的样本

这里只提炼算法和取舍，未拷贝代码、贴图、声音。VoxeLibre 由 MineClone2 改名，其 mcl_bows 继承 Arcelmi 的 bow；二者**不是两份独立验证 Minecraft 的证据**。四个仓库覆盖 MC 复刻、旧式分档、组件化箭和 C++ 兼容服务器。未核验到的 Godot/Unity/BotW/Valheim 示例不凑数。

### 3.1 VoxeLibre（原 MineClone2）

仓库：[VoxeLibre/VoxeLibre](https://github.com/VoxeLibre/VoxeLibre)，查阅 commit `4492ce6ff8d856daa4567abe2ea689f4e7a39842`。

- 关键文件：[bow.lua](https://github.com/VoxeLibre/VoxeLibre/blob/4492ce6ff8d856daa4567abe2ea689f4e7a39842/mods/ITEMS/mcl_bows/bow.lua)、[arrow.lua](https://github.com/VoxeLibre/VoxeLibre/blob/4492ce6ff8d856daa4567abe2ea689f4e7a39842/mods/ITEMS/mcl_bows/arrow.lua)、[README.txt](https://github.com/VoxeLibre/VoxeLibre/blob/4492ce6ff8d856daa4567abe2ea689f4e7a39842/mods/ITEMS/mcl_bows/README.txt)。mcl_bows 源码 **LGPL-3.0**；README 明确声音另有 CC0/CC-BY-3.0，纹理另查项目清单，不能按根仓库协议一概概括素材。
- 拉满 **500ms**，中间外观 **200ms**；最高 **40m/s**，源码注明为了已加载地图范围主动降速。部分蓄力线性 `max(4,40*ratio)`，伤害 `max(1,floor(9*ratio))`。满蓄通常 9，默认 20% 为 10 的暴击，并受 luck 影响。**明显不等同 MC 的 1s、非线性 f、命中瞬时速度伤害与满蓄必带 critical 标记。**
- 拉弓移速取 crouch/walk 配置比，FOV modifier .8，进入 1s、退出 .3s。
- arrow 通过 vl_projectile 的 sticks、has_tracer、owner_grace_distance、实体射线/实心碰撞行为组合；声明 liquid_drag 与最大时间60s。**底层 vl_projectile 重力/液体阻尼未在本次继续追到实现，不引用它为“20m/s²”或“.6”的证据。**
- 已读 bow/arrow 中未见玩家预测落点、提前量或磁性辅助。值得借鉴：参数集中、用微秒时钟、外观与逻辑分开、取消时移除 FOV/移速 modifier、箭行为组件化。不能照搬其 500ms 线性曲线来实现“原版 MC”。

### 3.2 Arcelmi/minetest-bows

仓库：[Arcelmi/minetest-bows](https://github.com/Arcelmi/minetest-bows)。[init.lua](https://github.com/Arcelmi/minetest-bows/blob/master/init.lua) 内容 blob SHA `716430416b1730b6bd7c0c4d92e9ed9806bb5764`；[LICENSE](https://github.com/Arcelmi/minetest-bows/blob/master/LICENSE) 为 **LGPL-3.0**。查询 latest commit 超时，未假造 commit；以文件哈希与查阅日期定位。

- 三个拉弓物品状态 bow_1/2/3，速度表达式分别是 **18/36/54m/s**；伤害 `charge*2`，即 2/4/6；重力默认9.81，可读取 movement_gravity。拉弓移速 ×.25，箭停留默认60s。
- `os.time()` 整秒计时，默认 charge_speed=1，比较是 >1、>2 秒，**不是稳定精确 1/2 秒升档**。代码表达式还混有 `,055566667` 多余表项，不能把它误读成小数 18.055...。
- 发射点向前偏2m，以起飞100ms后半径2m取邻近对象判断命中；没有精准扫掠，很容易隔近障碍或空中吸附。未见连续散布/预测/辅助瞄准。
- 用途：这是“分档快照”的反例。现有项目已用线段扫掠，**不退回**此 mod 的端点半径命中/向前跳起点；也不学它用整秒计时。

### 3.3 ronoaldo/x_bows

仓库：[ronoaldo/x_bows](https://github.com/ronoaldo/x_bows)，commit `65591329909bae68a914d16ca87832bea2bda59c`；[LICENSE.txt](https://github.com/ronoaldo/x_bows/blob/65591329909bae68a914d16ca87832bea2bda59c/LICENSE.txt) 为 **LGPL-2.1**。

- [init.lua](https://github.com/ronoaldo/x_bows/blob/65591329909bae68a914d16ca87832bea2bda59c/init.lua) 是先装箭、再点击发射的 charged-item 结构；并非 MC 的按住松手一体操作。`strength=30*strength_multiplier`，multiplier 初值是持有秒数、超过该箭 full_punch_interval 后硬设1。这个钳位**不是按时长归一化**，若某箭满蓄时间不是1s，边界可能跳速，不能复制。
- 初始加速度 `(−3dir.x,−10,−3dir.z)`；这是恒定水平减速，不是速度乘.99；入液体按粘度一次缩速、重力降到1，出液体回9.81。[arrow.lua](https://github.com/ronoaldo/x_bows/blob/65591329909bae68a914d16ca87832bea2bda59c/arrow.lua) 用 old_pos→pos 射线，飞行 pitch 随速度 atan2，支持节点/实体挂箭与60s寿命。
- 满蓄才抽指定概率暴击，暴击伤害 ×2；[items.lua](https://github.com/ronoaldo/x_bows/blob/65591329909bae68a914d16ca87832bea2bda59c/items.lua) 提供木/石/金属/毒等箭定义。原版 MC critical 不是这个概率×2方案。
- charged 木弓移速×.25、FOV×.9（.4s过渡），globalstep 每.5s检查，响应比较迟。未见预测提前量、吸附瞄准。
- 借鉴：真实接触点挂箭、按箭类型数据化、普通/critical 发射音区分；避免半秒轮询决定手感状态。

### 3.4 Cuberite

仓库：[cuberite/cuberite](https://github.com/cuberite/cuberite)，commit `7fd3fa5c9345a3f1b949c0988c4849db00a68486`；[LICENSE](https://github.com/cuberite/cuberite/blob/7fd3fa5c9345a3f1b949c0988c4849db00a68486/LICENSE) 为 **Apache-2.0**。

- [ItemBow.h](https://github.com/cuberite/cuberite/blob/7fd3fa5c9345a3f1b949c0988c4849db00a68486/src/Items/ItemBow.h)：ticks/20、`(u²+2u)/3`、Force<.1不发射、Force≤1。文件注释称公式来自1.6.2客户端。
- [ArrowEntity.cpp](https://github.com/cuberite/cuberite/blob/7fd3fa5c9345a3f1b949c0988c4849db00a68486/src/Entities/ArrowEntity.cpp)：Force×2 传入构造，再×1.5×20，得到最高 **60m/s**；重力−20；基础伤害按命中速度/20×2取近似四舍五入，再加暴击随机量。**构造里 `a_Force>=1` 标 critical，结合上游 Force×2，等效 f≥.5 即可能标记，不能说它完整复刻 MC。**
- [ProjectileEntity.cpp](https://github.com/cuberite/cuberite/blob/7fd3fa5c9345a3f1b949c0988c4849db00a68486/src/Entities/ProjectileEntity.cpp)：线段 tracer 处理接触顺序；速度先加重力，再按 `m_AirDrag*20*dt` 线性阻尼，m_AirDrag=.01，即20Hz时保留.99。与原版“阻尼后加重力”次序不同。
- tracer 还记录空气.99/水.8 slowdown 系数，但已读 HandlePhysics 并未消费这个系数；**不能声称 Cuberite 的水中.8实际生效**。该实现提醒：常量存在不等于接线有效。
- 未见玩家预测或磁性辅助；这是服务器，FOV/持物动画主要由 MC 客户端负责，不拿它比较本项目相机。借鉴：秒/每 tick 单位显式换算、射程/墙体排序、拒绝弱拉；不用其暴击判据或伤害 rounding 替代 MC。

## 4. 本项目现状审计

以下是查阅时快照，工作区有其他 worker 改动；行号只作导航，后续按函数名核对。没有凭静态代码断言“弓现在仍朝反”。

| 链路 | 实际实现与证据 |
|---|---|
| 输入/蓄力 | CombatMoves:Action/Update/Release/Events：draw 默认.7s，线性累加 charge；bow_draw 在120ms事件转 bow_hold，开始和保持都计蓄力；在 bow_draw 释放只置 pendingReleased，之后仍发射；未检查最小 f |
| 取手 | 背挂输入先 bow_equip .30s，clip_finished 后才 Action 启动 bow_draw；因此从背挂的同样手势比已持手多约.30s（Rig另有取手表现，不能再简单相加所有视觉时长） |
| 满蓄 | AnimClips bow_hold 的 draw_full 在 p=.8；默认约.56s提示。autoFire 却等 charge=1，即约.7s，提示后仍等140ms；HUD p≥.8写满 |
| 箭速/伤害 | Projectile:Fire：p<.3为18m/s、攻击×.5；.3≤p<.8为30m/s、攻击×1；p≥.8为44m/s、攻击×1.8；乘 projectileSpeed。伤害在发射初始化后恒定，不依命中速度 |
| 弹道 | Projectile:Step：重力6、无空气/液体阻尼；每步线段、最大1/30s，Update最多消费.5s；飞行累计路程默认36m上限，满档穿透一个非Boss |
| 散布 | WeaponParts有 spread 与稳定握把×.75，Projectile:Fire完全未读取；现在是零随机散布，握把的该收益不生效 |
| 准星/起点 | RuinsScene 初始化 fire回调：相机中心射线先查墙与敌人，取最近点，然后从Rig实际launch指向该点；没有重力补偿、预测标记或目标提前量，符合“看中不等于弹道命中”，但HUD目前仍按直线认目标 |
| 命中/插入 | Projectile:Step使用Hit.Query排序，与cast墙t比较；墙赢平手。实际敌体命中骨骼localPos/localDir挂接，破部位/目标消失回收；墙/敌插箭均.8s，已有对象池12槽 |
| 命中反馈 | CombatMoves:Feedback普通箭只顿目标30ms；满蓄弱点120ms并影响射手动作、轻震.008m/50ms；已有材质arrow_hit/破甲声与统一事件，不能再写“没有声音/没有反馈” |
| 相机 | CombatCamera:Update：只看drawing状态，200ms smoothstep拉满bow，不读charge；FOV−12，look从1到.6；释放100ms回零。满蓄一次.006m/80ms竖直小抖 |
| 辅助减速 | RuinsScene:UpdateCombatHUD先取camera.look，再候选半径.6m、无遮挡时取min(scale,.65)。镜头已到.60后，min(.60,.65)=.60，目标附近没有额外减速；且辅助受cameraFov设置门控 |
| 角色姿态 | AnimClips后置覆盖给弓设置handPath bow_aim/bow_string和bow_upright，不再用旧35°侧身；CombatAnim.handTarget左臂平举，右手目标z=.32−.17p，偏向下颌；release前80ms短向后拉.03，非旧片段表面上“前甩” |
| 弦与箭 | Rig:SetBowDraw用p<.25、p<.75、否则三档，弦扣及上弦箭切三套预建几何；p>.05才显示箭。右手目标并未由实际弦扣位置求解，存在几何分离风险，需四视角证据确认 |
| 飞行外观 | RuinsScene预建飞行箭为.03×.03×.42m的Box，无箭簇/羽；固定四段.09m尾块挂在箭后，不记录历史位置；箭转向随vel，嵌入后关尾巴。上弦箭则是完整体素杆/羽/簇，造型跳变可由代码确定 |
| 音频 | CombatAudio已有bow_draw循环（截.65s）、bow_full、两条bow_fire、按石/身体/甲选择arrow_hit；fire由Projectile成功取槽后播放。实际Web起音延迟、素材是否听感合适未验证 |
| 触屏 | TouchControls:MoveTouch已支持攻击指拖出按钮继续Input.AddLook，独立视角指可共存；取消走Moves清蓄力，不应重写一套并行触控状态 |

### 4.1 最可能的十个“诡异”原因，按修复收益排序

这是依据代码的**优先排查假设**，不是十项都经录像确认。

| 顺序 | 原因与证据强度 | 具体改法及初值 |
|---:|---|---|
| 1 | 连续按住却只有18/30/44三级速度，跨.3/.8瞬间质变；代码确定 | 连续f，v=60f；HUD/模型仍可分档，但不驱动速度台阶 |
| 2 | 最短释放排队到120ms，背挂还先等取手；手指与放箭不同步；代码确定 | 小于140.175ms×drawRatio取消；达阈值后Release同帧fire。取手与拉力并行，标准总满蓄1s，不先加.30s；早于手就位释放安全弃箭 |
| 3 | 镜头200ms即拉满而弦/能量还未就绪，释放100ms大幅回弹；代码确定 | FOV=55×(1−.15u²)，最高−8.25°，释放120ms回正；准星只收拢不漂移 |
| 4 | p=.8叫满，p=1才自动放，提示与实际成本不同；代码确定 | 满蓄事件、critical、自动射、HUD共用u>=1；900ms仅“接近满”外观，不播满音 |
| 5 | 箭比MC慢却更平，近处难看清、远处靠直线准星仍落空；参数确定，感受未测 | 60m/s、g20、空气.99/50ms；用真实弹道小落点标记解释下坠，绝不偷偷补偿为直线命中 |
| 6 | 右手追自定义下颌点、弦扣跳三档，二者未共用接点；接线确定，穿插未实测 | 弦扣随u连续沿−Z拉0→.18→.35m；三档只切弓臂形状。右手追实际弦扣world point，接触误差≤.03m；必要时加肘或缩小拉距 |
| 7 | 立体完整上弦箭射出后变.42m盒杆，尾段像硬杆；代码确定 | 共用NockedArrow几何/颜色，固定12份；尾迹记录历史点，总长.3–.6m、寿命60–100ms，普通箭弱、满蓄更清楚 |
| 8 | 准星减速在.60后被min(.65)覆盖，半径.6m候选也不随屏幕角度；代码确定 | 改2.5°内、LOS、8–32m候选，目标附近额外×.8平滑80ms；退出140ms，辅助开关独立于FOV开关 |
| 9 | 释放时Rig直接SetBowDraw(0)，没有实际弦回弹；现有右手短回拉不等于弦振动；代码确定 | fire时nock回正，弦±.03m以0/16.7/33.3/50ms衰减；左手后坐≤.015m、2°，右手后随.03m/80ms |
| 10 | spread属性无效、满蓄自带穿透/弱点/120ms射手顿帧混在一起，使“射准”和“暴击”概念不清；代码确定 | 稳定握把兑现小散布，critical与weak分离；默认普通弓不穿透；箭命中只顿目标30ms、弱点60ms，射手0ms；保持已有材质声音并同步实测 |

不建议把“没有满蓄音/没有插箭/方向一定反了/完全没有命中反馈”列为当前诊断；这些与已读代码或最新造型文档不符。

## 5. 可执行规格：建议首轮统一值

本节为**项目适配规格**。只在标为MC基准的地方追求原值；伤害、移速、插箭预算和触屏是有意适配。后续 worker 不应自行混用现有三档速度。

### 5.1 拉弓与输入状态

定义 `u=clamp(drawElapsed/Tdraw,0,1)` 为时间进度，`f=(u²+2u)/3` 为拉力；**现有 charge/p 统一继续表示 u**，另新增 power/f，避免拿f套900ms模型阈值或FOV。

| 参数 | 目标值/规则 | 来源 |
|---|---|---|
| 标准满蓄Tdraw | 1.000s | MC基准 |
| 部件 | 目标`Tdraw=1.0*(oldFinalDraw/.7)`；迁移完成后直接读取stats.draw，不重复乘1/.7 | 建议，转换见下文 |
| 最小可射 | f≥.1；标准连续时间140.175ms；不必强行量化150ms | MC阈值的连续时间适配 |
| 满蓄/critical | u≥1（浮点用elapsed≥Tdraw判定），跨越只发一次draw_full；持有不抖动重复提示 | MC + 建议 |
| 主攻击 | 按住蓄力，松手发射一箭；不自动连射 | MC |
| 强力箭 | 沿用点按自动蓄满再发一发晶箭；满蓄成本改同一个Tdraw，任何取消弃箭 | 保留项目规则 |
| 背挂取手 | 从首次接受输入开始计时；bow_equip与draw可视过渡并行，120ms内手就位；没有完成取手而又已释放则取消，不延迟补射；取手事件不能重置elapsed | 建议，需协调W1/W4事件 |
| 释放收招 | .18s保留；输入接受后200ms内可显示回正，禁止收招末尾第二次fire | 保留项目节奏 |
| 取消 | 菜单、失焦、页面隐藏、touchcancel、lostcapture、滑步、换武器、死亡、脱战、骑乘：pendingFire清空，charge=0，停止draw音，不发射 | 保留既有安全链 |

同一帧既有取消又有Release，取消优先。fire没有空闲箭槽时，不播bow_fire、不伤害；给一个100ms准星“未发出”状态，不能视觉射了但实际无箭。取消软尾只可保存姿态p/pitch，不保存可射击权。

**部件迁移必须包含加法项和夹紧范围**：基础draw改1.0，同时短弓draw从−.15改−.2142857、长弓从+.16改+.2285714；drawMultiplier保持原值。基础range改64，短弓range从−8改−14.222222、长弓从+10改+17.777778，rangeMultiplier保持原值；WeaponBuilder当前range上限60必须提高到96，否则基础64会被静默夹回60。这样默认反曲1s，短弓约.786s，长弓约1.229s，稳定握把再乘1/.92；文案显示可四舍五入，但计算不提前取整。存档只存部件ID，沿现有版本读取，不另写两套倍率。

### 5.2 速度、重力、阻力和碰撞

| 参数 | 首轮值 | 备注 |
|---|---:|---|
| fullSpeed | 60m/s×stats.projectileSpeed | speed=f×fullSpeed，无18/30/44下限 |
| 重力 | (0,−20,0)m/s² | Y-up左手；+Z目标、−Z射手 |
| 空气λ | .2010067s⁻¹ | 每50ms速度保留.99；所有速度分量均衰减 |
| 水中λ | 10.216512s⁻¹ | 每50ms保留.60；世界没有水体查询时明确暂不支持，不以雨/云判断入水 |
| 标准路程上限 | 64m（部件range相对倍率沿用oldRange/36） | 明确是游戏预算，不是MC自然极限；TTL≤8s兜底 |
| 步进 | 固定1/120s，accumulator保留余数 | 每子步扫掠；渲染插值，不按每帧乘.99；掉帧不凭空跳过墙 |
| 碰撞 | 保留Hit.Query、cast排序及墙赢平手 | 敌人与墙都使用相同射线段参数t；玩家自身/武器视觉排除 |
| 穿透 | 标准箭0 | 如保留特殊穿透只能来自明确部件/技能，不能把“MC满蓄”当依据 |
| 继承射手速度 | 首轮0 | 第三人称准星可预期性优先；与MC不同，后续单独A/B，不暗加横移误差 |

为了跨帧率一致，本项目建议按**连续线性阻尼**解析积分（独立设计公式，不复制外部代码）：设 h=1/120s、a=exp(−λh)、G=(0,−20,0)，`vNext=a*v+G*(1−a)/λ`；`pNext=p+v*(1−a)/λ+G*(h/λ−(1−a)/λ²)`。λ=0退回匀加速公式。每条子段先扫碰撞再提交；入水/出水时分段切换。

这与MC 20Hz的“先走旧速度，再乘.99，再−1m/s”离散递推**不是逐tick完全相同**，是明确的平滑适配。想做严格MC测试时另用§2.3参考递推，不用本积分器反证MC数据。首轮无需同时实现两套玩法模式。

物理 sanity（无散布、同水平发射、无起点视差；不是游戏实测）：

| 水平距离 | 现44m/s、g6：时间/下坠 | MC严格20Hz参考：时间/下坠 |
|---:|---:|---:|
| 10m | .227s / .155m | .169s / .205m |
| 20m | .455s / .620m | .343s / .993m |
| 36m | .818s / 2.008m | .636s / 3.602m |

参考表按MC线段内插采样；本项目连续适配的下坠会略多，不能作为逐点误差≤2cm的MC对齐门槛。

### 5.3 散布、命中伤害与击退

**建议不照搬 MC 的较大随机误差/随机伤害**，因为本游戏以小核心/破部位为目标。保持其“拉满最稳定”的学习关系：

- 发射时一次抽样，yaw/pitch各用三角分布；每轴支持范围 `±(1.0−.7u)° * stats.spread`，满蓄每轴±.30°、标准差.122°。不是每帧漂移，移动不追加暗罚；稳定握把现有spread×.75生效。下坠预测显示中心轨迹，标记半径可表示散布，不承诺必命中。
- 撞击前瞬时速度 `sImpact`，存下该发的 `fullSpeed` 与attack快照：`Dbase=attack*1.5*clamp(sImpact/fullSpeed,.1,1.05)`；该箭critical时再×1.2。标准静止近距离满蓄约attack×1.8，维持旧满箭伤害量级；远处随减速轻降。**这是确定性适配，不是MC原伤害式。**
- 默认attack=8例：满蓄标称约14.4；半时间u=.5，f=.4167，近距离约5；不是旧中档8。不要把“保留满伤”误写成“所有档位DPS不变”。弱点仍由Enemy最终入口×1.6，只结算一次；critical与weak必须两个布尔值，普通身体满蓄也critical。
- `poise` 仍由部件控制；建议 `poise*(.4+.6f)` 连续变化，破甲倍率单独armorBreak；晶簇爆炸仍使用**已结算箭伤**×.25、半径.8m，避免弱点重复乘。
- 普通箭击退给非Boss .08m，满箭 .16m，在.10s内由敌人运动模块分配，不teleport；Boss保持根节点0m，只局部骨节回弹。数值是本项目位移预算，不能称为MC的0.4击退换算。
- 普通命中只顿目标30ms，critical+weak目标60ms，射手0ms；破甲/失衡取既有100ms上限合并。修改原满蓄弱点冻结射手120ms是为远射避免“命中远端后手感忽然卡住”，需主方案明示。

### 5.4 相机、准星、预测与辅助瞄准

1. 固定基础垂直FOV55°；拉弓目标 `55*(1−.15u²)`，满46.75°。按真实elapsed计算，不额外套200ms“先到终点”的包络；松手/取消从当时FOV平滑120ms回正。用户cameraFov关闭则保持55°，其他弓玩法照常。
2. 灵敏度基线建议 `Lzoom=tan(FOV/2)/tan(55°/2)`，使每像素附近的视角变化更一致，满蓄约.83；这是本项目适配，不是MC原值。独立设置aimSensitivity倍率默认1。禁止FOV关闭时连带关闭aimAssist。
3. 弱辅助只减速：中心2.5°内、8–32m、活敌、相机到候选及弓口到候选都无遮挡，额外倍率.8，80ms进入/140ms离开；绝不改变箭方向、不自动追弱点。候选角离开3.5°再释放以防边界抖。总灵敏度`Lzoom*Lassist`，不是min(.60,.65)。近于8m可保留自由转向，避免贴怪甩不动镜头。
4. 默认无提前量、无重力补偿。射向仍由相机中心射线的最近合法目标点确定，然后从launch收敛；近墙从launch先查，不能绕过掩体。不要再额外用NomiController:AimRay的解谜SphereCast吸附来修正战斗箭。
5. 增加**可关闭、默认开的小弹道落点/交会提示**：按当前u、发射口与真实积分器预演，中心轨迹走相同碰撞；12–24个预分配点，15Hz更新，点间再细分到≤.25m的碰撞段，64m/8s预算终止。屏幕只显示最终接触的小空心2–4dp标记，可选稀疏弧线；穿墙/出屏/虚空无有效交点则不画虚假命中。低画质5Hz、12点。
6. HUD直线红准星只表达“瞄到敌人”，不能当实际命中承诺；另以弹道标记表达实际落点。预测不读取未来敌人路径，命中移动目标仍需玩家提前瞄。不给敌人头/核心画自动锁框。

这套预测成本需Web测量；现有F7/训练木桩会把target强行指向木桩，是合成瞄准，**不能用于证明准星/实际弹道对齐**。必须再测自然输入。

### 5.5 音画 cue 与逐帧时序

帧号以60FPS仅作展示：一帧16.667ms，实际按秒驱动，30FPS不得拉长/漏事件。t=0为输入接受；标准弓Tdraw=1000ms。声音与视觉调用同一个事件，Web可听峰值偏差目标≤30ms，未实测前不称已同步。

| 时刻 | 动作/画面 | 声音/输入与相机 |
|---|---|---|
| 0ms / F0 | 接受按住，取手与抬弓并行；不等满蓄进入肩侧瞄准 | bow_draw起音，−12dB；预加载；FOV曲线从u0启动 |
| 0–120ms / F0–7 | 左臂伸向目标；右手到弦扣；p>.05可见上弦箭；目标120ms内握稳 | 拖动立即更新视角；若此时松手且低阈值，直接取消 |
| 140.175ms起 | f≥.1可射；不自动发射，不播提示音 | 松手当帧fire，不排队等“拉弓片段结束” |
| 650ms / F39 | 预建弓中档外观（u=.65）；逻辑速度仍连续 | 不播full，准星继续收拢 |
| 900ms / F54 | 最后外观（u=.9），表示接近拉满 | 不提前播full |
| 1000ms / F60 | draw_full一次：弦/箭扣80ms短亮，准星满态保持 | bow_full−4dB，≤120ms；可选轻触觉10ms，浏览器不支持则跳过；不震相机也能识别 |
| R+0ms / 同帧 | Release保存u、f、pitch、facing、stats；同帧AfterPose从最终Rig姿态读取launch后fire，成功才隐藏上弦箭、显示飞行箭，弦回静止 | 停draw循环（20ms淡出），bow_fire−5dB，已有两变体；准星不跳，FOV开始120ms恢复 |
| R+0/16.7/33.3/50ms | 弦横向残振±.03/.018/.009/0m，可复用预建偏移，不重建体素 | 禁止再加一声完整whoosh；小尾风可作为fire素材本身 |
| R+0–80ms | 右手沿射手侧后随最大.03m；左手后坐.015m/2°，80ms回弹；不向目标方向挥拳 | 相机无枪械式大后坐，cameraShake关闭不影响动作 |
| R+80–180ms | 松肩回待机；180ms恢复下一次按下；接新输入可平滑衔接 | 不额外自动装箭音/连射 |
| H+0ms | 真实接触命中标记、材质粒子；墙/身体/甲分别处理；伤害只结算一次 | 复用arrow_hit −2dB；破甲声替代普通撞击的主体；普通箭不顿射手 |
| H+0–60ms | 小闪/准星确认，目标30ms顿帧；弱点确认60ms | critical只小亮，weak单独确认；不以full声替代hit声 |
| H+0–350ms | 墙/敌体插箭衰减摆动，建议峰值4°、7Hz，100ms半衰，350ms归零 | 不循环播放撞击声，不给普通墙加弹跳声 |
| H+700–800ms | 插箭最后100ms两步淡出，800ms回池；目标死/部位破坏立即回收 | 无额外声 |
| C+0ms（任意取消） | 清pendingFire、arrow preview与蓄力；软取消姿态180ms，硬取消立即交给新动作 | bow_draw 20ms淡出，禁止bow_fire/命中；FOV120ms回正 |

full cue取代旧p=.8事件；建议保留现有素材先修触发。只有试听确认某素材不适合时再制作新声音。MC没有的draw/full音是本项目增强，不必为“对标”删掉。

### 5.6 箭的飞行、朝向与插入

- 弓臂仍三套预建外观，在u=.65/.90切换；**弦与弦扣从整块弓几何中拆出为独立预建片段**，用节点端点/朝向变换表现连续拉距，不把手/箭也按三档跳动。nock相对握点局部Z按(0,0)、(.5,−.18)、(1,−.35)m连续插值，右侧箭台的X/Y位置保持原定义；上弦箭的尾扣跟nock，方向沿+Z。弓弦两段连弓梢与nock，可用预建3cm级小段重排，禁止逐帧重建体素。
- 姿态求解顺序必须是“左臂及持弓姿态 → 同帧bow/nock目标 → 右手解算 → 发布Rig渲染”，不能在CombatAnim先读上一帧Rig节点的GetBowNock再追赶，否则会引入一帧延迟或循环依赖。接口返回当帧求值的目标，也记录实际接点用于调试。
- 一份箭几何定义导出上弦与飞行版本，12套预建，保持3cm体素精度；簇/羽/颜色随装备部件；射出前后总长差≤3cm，消除盒杆跳变。不能每射创建Volume/材质。
- 飞行箭+Z沿瞬时速度；可加很轻的轴向自转≤180°/s作为建议首值，不做乱翻滚。低速小于.1m/s保留最后方向，避免归一化异常。该自转是自定义，非MC必需。
- 物理p统一定义为**箭尖接触点**；渲染根向后偏箭长/实际tip offset，不能把.42m盒子中心直接放到撞点导致半支穿墙。launch到箭尖的首段也检查遮挡，不向前平移起点跳墙。
- 命中沿来向插入视觉.04–.08m，最多箭长15%，按接触法线/表面实际允许深度截断；游戏命中点仍为碰撞点。敌体保存骨骼localPos/localDir及入射姿态，局部抖动只动渲染，不反复碰撞。
- 尾迹默认3–4段历史轨迹点、总长.3–.6m，寿命60–100ms；快速移动按距离补样，转弯保留弯线，不把四段刚体一直贴在当前箭方向上。普通箭透明更低，critical增强但不增加碰撞/灯/阴影；嵌入即关尾。
- 除非敌人明确具有盾反/反射能力，首轮不加弹跳机制。若未来加：用真实normal反射、速度保留.1、只一次，走单独deflect cue，不伪造伤害成功音。

### 5.7 触屏按住拖动

保留现有TouchControls触点所有权：攻击指按下后即便离开按钮也持续拉弓、拖动视角；松手只由该pointerId触发。摇杆指和独立第三视角指保持可用。

- 首轮拖动灵敏度沿现有Input.AddLook的逻辑像素/DPR路径，最终乘§5.4倍率；不按物理像素重复乘DPR。可加2dp累计启动门槛抑制按下抖动，超过后消费真实位移，不吞掉大半段手势。
- 另一根手指可以点击闪避/切武器取消；不要强制攻击指拖到一个屏幕角落才能取消。菜单/系统失焦/pointercancel/lostcapture只取消，永不当pointerup放箭。
- 不给主攻击添加自动松手、超时必射或满蓄自动连发；强力箭继续独立的一次自动蓄满模式，UI清楚显示“自动蓄力中”。
- UI仍按2×/NEAREST、12/24字号和≥56dp触点约束；满蓄/取消/弹道标记不得被手指和右下按钮遮住。
- 真机验收覆盖两指与三指、横竖切换、通知栏、页面后台、指针丢失；缺这些证据仍写未验证。

## 6. 代码对接与改动次序

只列建议，不已实施。文件owner以Lead重新分工为准；路径按本地真实位置，CombatHUD/TouchControls在scripts/ui，不在combat。

| 文件 / 函数 | 需要改什么 | 必须保留什么 |
|---|---|---|
| WeaponParts.lua / BaseStats.bow、WeaponBuilder统计夹紧 | 基础draw由.7→1、range36→64；按§5.1同步转换加法项；range上限60→96；spread成为真正参数 | 19部件ID、存档、正负取舍、3cm几何不变 |
| CombatMoves.lua / Action、Update、Release | 新增drawElapsed、power；取消短按补射；取手并行；主释放快照，自动射同一full阈值 | 输入边缘、缓冲、取消优先、pendingFire防补箭 |
| CombatMoves.lua / Events、BowParameters、AfterPose | draw_full改u=1事件唯一来源；fire只一次；AfterPose取最终launch，统一event快照，不从下一帧姿态重算 | release/cancel的p/pitch保存，软取消不加busy锁 |
| AnimClips.lua / bow_draw、bow_hold、bow_release | 不让draw_min=120ms强制射击；full事件p1；release由事件保持，右手后随、弦回弹参数 | .18s收招、滑步独立时序、无肘兼容 |
| CombatAnim.lua / handTarget、bow_upright路径 | 先求左臂/弓姿态，再求当帧nock目标供右手解算；调试显示target/actual误差；不能读旧帧节点追赶 | 不猜Euler符号、不把旧35°侧身重新覆盖回来 |
| WeaponRig.lua / SetBowDraw、UpdateBowVisual、BuildVisualPools | 弓臂阈值.65/.90；独立预建弦段、nock连续变换，提供当帧GetBowNock；预建回弦表现；导出飞行箭共用几何 | GetHit/SetPose/SetSwing语义和零战斗重建 |
| Projectile.lua / Fire | 连续速度、发射时一次散布、snapshot fullSpeed/attack/critical；不默认pierce | 12槽、无槽不假发射、serial防重复 |
| Projectile.lua / Step、Update、Embed | 20重力/阻尼积分、命中速度伤害、碰撞排序、64m/8s；嵌入尖端与姿态 | 敌/墙扫掠、骨骼挂接、去重、晶爆只乘一次 |
| RuinsScene.lua / fire回调 | 相机→目标→launch收敛保留，接统一snapshot；launch遮挡检查；预演与实箭共用数学 | 不用训练木桩的强制target当自然验收 |
| RuinsScene.lua / arrowNodes初始化、draw回调 | 盒杆换预建真实箭；历史尾迹；箭尖offset，插入摆动 | 12套、池化材质和节点 |
| CombatCamera.lua / Update、Full | 读取u²；满FOV46.75；退出120ms；满震默认关/可选 | 单处弓FOV源、设置开关、偏移不反馈跟随累积器 |
| RuinsScene.lua / UpdateCombatHUD | 把min(.6,.65)改独立乘性目标减速；角度/LOS判断；预测标记数据 | 不吸附/不追踪弱点，cameraFov关闭仍可辅助 |
| NomiController.lua / Move、SetCombatCamera | 首轮draw移速仍.5（5m/s→2.5），稳定握把.6；可选未来硬核档.2；肩距保留先测 | 不把两个慢速倍率再叠乘；不改解谜AimRay |
| CombatMoves.lua / Feedback | 箭反馈只顿目标30/60ms，critical/weak分开；破甲合并最大值 | 统一命中事件和材质音、无全局timescale |
| CombatAudio.lua / 事件定义、Play/Stop | 先复用现有素材；draw退出20ms淡出、full一次、fire以成功生成箭为准 | 变体、材质选择、预加载和声部预算 |
| scripts/ui/CombatHUD.lua / Hint、CrossGap、Render | p1才显示满；准星收拢用u；直线目标与实际弹道标记区分 | 2×像素风、数字默认关、缓存布局 |
| scripts/ui/TouchControls.lua / MoveTouch、EndTouch、Cancel | 继续已有按住拖动；更新满蓄门槛.8→1；新增丢失捕获核对（若尚未接） | 指针所有权、第三指兼容、取消无射击 |
| CombatTest.lua / 弓预期值及现有tests | 更新旧18/30/44断言；增加公式/阈值/取消/墙排序/帧率/反馈一次性验证 | 合成测试与自然输入/Web视觉分开标记 |

次序：**先统一状态时钟和连续弹道 → 再接弦扣/飞行箭与相机 → 再接预测/辅助 → 最后按Web证据调音画强度。** 不把新FOV、移速、散布、伤害和所有特效同时盲调到无法追因。

## 7. 后续验收矩阵与不确定项

本次只做调研，以下是后续开发验收要求：

1. 公式：u=0/.1/.15/.5/.9/1对应§2.2；f<.1零箭；u=1后只一次full。部件改变Tdraw后所有提示与阈值同步。
2. 输入：同样100/150/500/1000ms手势从back/hand各做；取消发生在Release同帧、fire前后边界分别测；菜单恢复不补箭，强力箭只一次。
3. 弹道：10/20/36m，水平与±35°，静止/横移，30/60FPS；本项目积分器同输入轨迹接触差≤.02m。与MC参考的误差另记录，不要求连续适配逐点重合。
4. 遮挡：近墙、箭台贴墙、敌人在墙前/后、墙与敌t相等；高速箭不能越墙；弱拉落脚边不伤自己；range/TTL回收不泄漏。
5. 四视角：弓凸面+Z、弦−Z，nock与右手在0/.65/.9/1同框；误差≤3cm，否则先缩拉距或改肘，而不是继续旋转整把弓掩盖。释放前后箭簇/羽和长度连续。
6. 音画：用Web自然输入录屏/录音，测Release→首支箭、fire→声音峰、impact→命中确认；目标同帧生成、声音偏差≤30ms。首次加载与连续十箭分别测。
7. 触屏：两指/三指按住拖动、划出键、系统手势/切后台取消；FOV关、辅助开及相反组合都测；不把PC鼠标通过当真机通过。
8. 预算：12箭+现共享64粒不增加；预测CPU预算首轮≤.3ms、战斗整体沿用R5预算，低档5Hz；最终看Web真实P95和提交数，不把离线Python结果当GPU性能。

**明确未确认：**

- 当前Web弓朝向、手指/弦穿插、MP3起音与触觉兼容，没有新视觉/音频证据；本报告对其只列静态风险。
- 单根刚体右臂能否同时满足“左手握弓、右手贴nock、嘴角拉距”，需要角色实际肩/臂长的四视角测量；若不可达需Lead裁定肘关节或拉距，不能强行造假。
- 1.20.3-pre1不是截至2026最新MC；后续若指定其他Java版或Bedrock，应重核随机分布、伤害和渲染数据。
- MC RandomSource.triangle本体定义未继续读；模型原版资源已读，未引用/复制其图片。
- VoxeLibre底层vl_projectile重力/阻尼未追全；Arcelmi最新commit查询失败；已经在样本节以文件哈希/未确认项标明，不能据此阻塞本项目参数方案。
- 本项目水中参数只有在真实水体判定存在后才能接入；当前查阅链路未见水体状态，首轮可只落空气弹道。
- 取消/指针事件的浏览器底层是否全部覆盖，需要在现有输入层核验；本文确认的是MoveTouch已有拖动，不等于所有系统取消都已验收。
- 推荐满蓄1s、60m/s、无默认穿透、更低弱点顿帧会改变DPS/敌人交战节奏，需用现有HP30/24与Boss600做Web战斗回合测试；不以MC声望代替项目平衡。

## 8. 自审记录

已按“MC原值 / 开源差异 / 本地证据 / 项目建议”复核引用和单位：修正公式一次项2u、阈值.1非秒、.05/tick²→20m/s²；查明当前§21/§22覆盖关系；把已有满蓄音/插箭从“缺失项”中排除；标明Cuberite临界与水系数接线差异；未复制第三方实现或素材。本文不构成Runtime/Web验收通过。
