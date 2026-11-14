# 空岛视觉第2轮 Web 复核 — 884c795

2026-11-14 01:41–01:49 +08:00。仅使用 Cindy external 既有 island-void-review 页。
入口：https://maker.taptap.cn/app/f323832c-195d-4276-a841-0ceafd1f1cf1?localDev=1&hide_chat=1
targetId=82A6CFAFF4DF3C2BCD316957A406C437。没有启动本地游戏 Runtime，没有改代码、提交、构建或换浏览器模式。

## 版本证据与运行

- HEAD=884c795c090755f781a97c5703eb3736f7e8248f，tracked clean；原有 art/ui_mobile/、validation/island-void/、validation/touch-ui/ 未跟踪目录保留。官方回执 ../maker-build-884c795.json。
- 本轮重新 navigate，01:41:40开始新运行，01:42:17 RuinsScene ready，构造35.66s；GrassField ready，草、岛壳、墙与路面可见。
- 已发生请求给出 RuinsGround 的实际资源URL（UUID DJMX4WhGoyLwMC1SByKMroU_，文件后缀 edc80a1e.shader）。通过同一 Cindy 页面 fetch 读取该确知URL，HTTP200，源码SHA256=bd2ec6ccb95255e9fae3075f8c9a7aed6f52e8d8d23d0292c8506a84a684c3c7，与本地884c795源码逐字相同，含本轮 deepHeight/deepMix 改动。记录 web-r2-shader-resource.json、web-version.log。
- 请求清单时间17:40:33Z早于本轮导航，不能当本次导航独立下载时间；上述读取证明当前站点提供本轮shader，配合新导航、真实渲染及构建回执支持版本归属。页面没有直接报告git SHA，不声称独立验证整个发布包。
- Terrain 实际URL返回HTTP200、30236字节，SHA256=0369f7db28b054dca24cbd6acf94fa2fa2d4a5af8773cdc01ce7534242264892；内容非可读Lua文本，不能与本地30232字节源文件直接比较。最初全资源字节相等检查失败，未将它当作版本回退；没有解码/绕过资源流程。几何数量与r1相同，不用作版本指纹。
- 浏览器本轮可得日志中未发现新增Lua error/traceback或 RuinsGround 编译错误；实际岩石材质正常可见，判定本次可见场景渲染 PASS，不等于验证所有shader变体。仍有既存 POSITION无deferred pass警告（另一资源UUID）、SetMode零尺寸、preferences、batch download、日志限流警告，保留于 web-runtime-review.log。未用旧runtime日志当本轮证据。

## 实际结果

| 项目 | 结果 | 证据与边界 |
|---|---|---|
| 新版场景/岩石材质可渲染 | PASS | 新启动日志、资源源码和实拍；未见本轮新增编译/Lua错误。 |
| 竖向重复明暗条减弱 | PASS（已拍外环局部） | r1外缘直切深条在r2明显柔和；几何轮廓的格边仍在，不是全部消失。 |
| 连续浅灰腰带完全消除 | FAIL | 15:22低侧视、15:28斜侧仍读成上浅下暗连续带，局部下缘变柔和但目标尚未完全达到。不再自动修改。 |
| 岩底无明显胶质高光/整片涂黑 | PASS（已拍局部） | 外环和低裂隙图纹理可辨、无明显新增亮蓝高光，底面仍较暗。全底面和其他太阳角度未验证。 |
| 薄土/草/岛顶/墙保留 | PASS（可见范围） | 近景和俯瞰可见薄土、草及原墙；未走遍全地图。 |
| 外岸瞄准→22片回溯 | PASS | 清门残片后，01:47:02 rewinding22，01:47:04 restored，stage→key。站位约(-.234,6.24,-50.833)，yaw28.92/pitch-31.32。 |
| 走通修好桥/南桥头承托 | PASS | 正常W过桥到内岛(-.234,6,-35.84)附近，再横向走上草地；未瞬移。 |
| 坠落返回、保留进度 | PASS（已测点） | 南侧x≈8离岸，日志落到(8.010,3.432,-41.835)，随后回(7.984,6,-36.013)；桥仍完整、任务仍取钥匙。 |
| 持续移动键复位保护 | PASS（W键路径） | 保持W到返回后约1秒，return-held与return-still位置一致；最后松键。未重测充能中坠落/所有触摸路径。 |
| 白昼→黄昏 | PASS（局部观察） | 正午启动，经正常T快进到15:22，随后自然进至16:44，阴影与色温随时间改变。未验证完整夜晚/完整昼夜循环。 |
| 冻结/骑龙/北侧/全底封闭/旧蓝色四边形来源 | UNDETERMINED | 本轮未测到；低裂隙图未再看到该蓝色四边形，不能据此认定根因或全底封闭。 |

## 推荐实际查看的4张与r1对照

全部已逐张实际查看；文件均在本目录：

1. web-r2-outeroblique-afternoon.webp ↔ ../visual-r1/web-r1-outeroblique.webp。本轮15:28、r1 15:29，yaw22.32/pitch-14.64，Tab远景；本轮角色(-.815,6,-65.368)，r1(.948,6,-66.4)，站位有约2m偏差。竖条软化，亮腰带仍在。
2. web-r2-outerlowside-afternoon.webp ↔ ../visual-r1/web-r1-outerlowside2.webp。两图均15:22，本轮yaw-.12/pitch-24.96，r1 yaw0/pitch-25.08，站位同上偏差。下缘切换较柔和，仍有大面积明暗分层。
3. web-r2-lowrift.webp ↔ ../visual-r1/web-r1-lowrift-clean.webp。本轮16:41、r1 14:37，均正常离岸下落拍图；机位/时刻不严格一致，不据此量化亮度变化。底部灰岩纹理可读，没看到胶质亮斑。
4. web-r2-southaerial.webp ↔ ../visual-r1/web-r1-southaerial.webp。本轮16:32、r1 13:55，均Tab/pitch50.64；本轮(3.708,6,-35.838)，r1(3.17,6,-36.54)。岛形、宽缺口与桥头保持；更暗的草地主要伴随明显长阴影，不能将不同时间图作材质回退结论。

补充：web-r2-outeroblique-noon.webp、web-r2-spawn.webp；行为图 bridge-restored、crossbridge、return-held、return-still。所有前缀均为 web-r2-。

## 操作与收尾

- 操作使用Cindy白名单CDP键鼠，Tab为现有玩法远景相机；T为现有快进键。没有DOM合成触摸、Lua注入、解锁或瞬移。
- 首次打门瞄得过低命中不可破坏路面，调整俯仰后打通；瞄桥曾被门残片遮住，再打碎残片后回溯成功。不将这些有限校正当本轮shader故障。
- 完整操作回执 web-r2-operations.json；脱敏控制台 web-r2-runtime.json；摘要 web-runtime-review.log；版本 web-version.log。Lua资源直接字节比较失败记录 web-evidence-check.log；辅助脚本一次键路径读取错误见web-terrain-diff.log，属于证据整理工具错误，不是游戏报错。
- 最终角色(7.984,6,-36.013)内岛安全草面，stage=key，yaw179.76/pitch15。所有使用过的 W/A/S/D/Q/T/1/Tab 和左右鼠标已通过成功回执释放，停止操作。
- 本轮没有严格同机位性能基线，不判定性能达标或回退。截图工具压缩到1280宽，原浏览器CSS视口约2297×1129。
