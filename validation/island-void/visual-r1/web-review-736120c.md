# 空岛视觉第1轮 Web 复核 — 736120c

2026-11-14 01:17–01:26 +08:00。仅操作 Cindy external 专用浏览器既有 island-void-review 页，targetId=82A6CFAFF4DF3C2BCD316957A406C437。
入口：https://maker.taptap.cn/app/f323832c-195d-4276-a841-0ceafd1f1cf1?localDev=1&hide_chat=1

## 版本与运行证据

- 本地 HEAD=736120c4d7cfca19f8882217192d01fdaf06b9aa。tracked clean，原 art/ui_mobile/、validation/island-void/、validation/touch-ui/ 未跟踪保留。
- Lead 官方构建回执在 ../maker-build-736120c.json。本次重新 navigate 既定入口，未启动本地 Runtime、未改代码/提交/构建、未修日志 watcher、未切浏览器模式。
- 新导航后浏览器控制台：01:17:19 79碰撞块/2519040分配格/1174742实体格；01:17:24 98692三角/128壳块、GrassField ready；01:17:51 RuinsScene ready volumes439，场景构造日志35.15s。对应新版本结构特征，HUD也显示新“裂隙中/站在岸边”文案。页面未直接给git SHA，未独立校验资源包hash；版本归属由官方构建回执+重新导航+结构特征共同支持。
- 浏览器原控制台跨导航保留旧记录；证据文件仅取本次导航时间之后的Script/错误/警告，未读取旧runtime.log。
- 无新增Lua error/stack traceback的可见记录。存在SurfaceShader POSITION无deferred pass、SetMode零尺寸等警告，原样记录，未据此判断为本轮故障。日志达到输出限额后出现重复记录限流警告，不能声称每帧状态均有日志。

## 实际行为结果

| 场景 | 结论 | 实测证据/限制 |
|---|---|---|
| 新场景加载与草显示 | PASS | 启动日志和spawn截图；正午起始。 |
| 南门打通 | PASS | 先数字1长按打掉前层，再调整pitch至约-6.5°清剩余，01:19:37 stage→bridge。 |
| 外岸选桥片→回溯22片 | PASS | 外岸player≈(.054,6.496,-50.822)，yaw29.16/pitch-31.20；01:20:34 rewinding22，01:20:36 restored且stage→key。 |
| 修桥贯通及桥头承托 | PASS | 实际W过桥到(.054,6,-32.245)内岛阶梯；坠落测试后又从内岸走回外环出生路。未用瞬移。 |
| 南侧裂隙返回安全点/进度 | PASS（已测点） | x≈9.63、z≈-36.54向南离岸；下落后回(6.532,6,-36.765)附近安全点，古桥仍修好、任务仍取钥匙。随后再次走通桥。 |
| 保持移动键的复位保护 | PASS（已测键鼠路径） | W一直保持到回安全点并额外等约1秒，连续图片角色静止；松开重按可再次移动离岸。 |
| 蓄力中坠落清理 | PASS（可见行为） | W前进650ms后按1，350ms截图有蓄力弧；继续保持W+1，返回后弧消失、不继续移动/蓄力；最后松开两键。没有内部施法计数出口，不扩展到所有事件路径。 |
| 四碑完整承托/北殿/西塔路线 | UNDETERMINED | 俯瞰只看到南侧部分碑基与周边草地，未实际走完四碑/北侧/西塔，不引用离线采样代替Web。 |
| 骑龙飞行/虚空禁降落 | UNDETERMINED | 未解锁龙，本轮未测试。 |
| 外环最外缘坠落、fallback、碎片安全点排除 | UNDETERMINED | 补外缘视角，未实际从外环坠落或清空safePos。 |

## 已实际查看的视觉结果

- **灰蓝下半球：PASS（配色/渐变的可见范围）**。南半岛俯瞰原均匀褐色已变灰蓝，有从上方浅到下方深的渐变；比旧图更少土沟底感。仍是没有云/空间参照的平滑背景，不能据局部图保证每角度都不会被看成平面。
- **消除连续浅灰岩带：FAIL（该视觉目标尚未完成）**。外环正面和斜侧面仍有连续明亮岩唇，厚度变化能看出，但整体仍像上亮下暗腰带；斜侧远缘还有重复竖向切面。未修改代码，交Lead决定下一步。新旧光照时刻不同，不能仅凭亮度差推断材质回退。
- **大轮廓：局部变化可见，整体审美UNDETERMINED**。南缘俯瞰宽凸肩/凹口比旧图明显，桥头保持平稳；仍保留环形整体布局。局部0.5m格边台阶可见。请Lead判断大轮廓是否够自然，未宣称全岛艺术通过。
- 草、薄土、岩面均可辨；低裂隙图岩壳为暗蓝灰，未见发亮的蓝色岛底。外环斜侧可见向内收的体积，仍未完整拍到主岛/外环底面，**全底面封闭和全部垂岩未验证**。更低俯仰受现有镜头避障拉回草面（outerunderside图），未继续绕过或改镜头。
- 旧低裂隙蓝色四边形在本轮相近机位未再出现，但相机位置和昼夜时刻不完全相同，**其来源与是否修复仍UNDETERMINED**，不能因一次未见就认定洞已封。
- 外环朝外画面仍无最外围山体/方形高度图边界；已有遗迹墙、角楼与远处浮岛保留。

## 推荐Lead直接看的5张

均在本目录，已逐张实际查看：

1. web-r1-southaerial.webp — Tab远景、pitch50.64，南半岛宽轮廓与灰蓝渐变；对照 ../web-aerialbridgehead2-1.webp。
2. web-r1-lowrift-clean.webp — 同为南侧离岸下落时取图，局部岩壳/桥底/灰蓝背景；对照 ../web-lowrift-1.webp。
3. web-r1-outeredge.webp — 外环向外，无山，草地/出生路承托；对照 ../web-outeredge-1.webp。
4. web-r1-outerlowside2.webp — Tab远景、yaw0/pitch-25.08，外环仍有亮腰带；对照 ../web-outerlowside-1.webp。
5. web-r1-outeroblique.webp — 外环斜侧，亮带/重复竖面、下部斜收最明显。

行为图：web-r1-bridgerewind.webp、web-r1-crossbridge.webp、web-r1-innerbridgehead.webp、web-r1-return-held.webp、web-r1-return-still.webp、web-r1-lowrift-charge.webp、web-r1-return-chargeclear.webp、web-r1-return-chargeheld.webp。

## 输入/操作记录与结束状态

- 全部键鼠通过Cindy browser白名单CDP；无DOM合成事件、Lua注入、瞬移或调试解锁。Tab是项目现有远景模式，不是自由相机。鼠标拖动CSS坐标被浏览器缩放约1.1倍；实际yaw/pitch以RuinsAim日志为准。
- 等待毫秒只是请求等待值，截图/工具间隔也计入按键持续时间。回执保存在web-r1-operations.json，脱敏浏览器日志web-r1-runtime.json（含337+条记录），HEAD证据web-baseline.log。
- 结束时角色≈(.948,6.001,-66.400)，外环出生路安全处；gate/bridge完成，key未取，Tab远景yaw22.44/pitch-14.52，最终截图web-r1-final.webp。所有使用过的键、左右鼠标均已释放，最后释放批次回执成功。
- 一次结束批次因commands数量/参数被整体预检拒绝，未执行；拆为8条命令后成功，无按键残留。脚本工具两次辅助保存函数拼写错误未发起浏览器操作，均修正后成功。
- 当前观察视角约19–33fps、峰值约70ms上下，视角和场景复杂度不同；没有严格同机位基线，不判定性能达标/回退。手机/触屏不属于此次验收。
