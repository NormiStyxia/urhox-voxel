# 移动端 UI 程序接入

2026-11-13。设计依据为《移动端UI设计规范.md》及负责人对阶梯动画的修订。

## 结构

- scripts/ui/TouchInput.lua：虚拟按住/单次按下、移动轴、视角累积、Android/iOS/Web 首触检测与 F9 覆盖。取消输入增加 revision，场景据此取消蓄力，不把取消当松手施放。
- scripts/ui/TouchControls.lua：独立 LuaScriptObject 监听 TouchBegin/Move/End、InputFocus、KeyDown 和 EndFrame，避免覆盖场景的同名事件监听。按 touchID 分配摇杆、各按钮与单指视角；切换地面/空中只释放按钮拥有者，保留移动与视角。
- scripts/ui/PixelDraw.lua：严格 2×、NEAREST、纹理晚就绪重试；九宫格与卷轴采用 2× 原像素平铺/裁切；24 格冷却、32 格充能、像素描边环。自定义 Panel 在 UI 自有 NanoVG 帧中绘图，补偿 UI.Scale.DEFAULT 的密度因子，使尺寸仍是系统 dp。
- scripts/ruins/RuinsHUD.lua：保留原调用接口；像素目标、时钟、提示条、卷轴、准星、目标名与 PC 法术槽。HUD 树保持 pointerEvents=none；提示条按内容换行，并避让右侧按钮与目标名。
- RuinsScene.lua：局部接入 Down/Press、移动轴、碎时按住/释放、触屏视角与鼠标锁定旁路；AttachTouchControls 提供实际骑乘状态；M.readStreamInput() 提供普通吐息 held/allowed。
- DragonRide.lua：虚拟键接入、模拟量移动/转向、刹车优先、触屏滑翔切换。存在 host.stream 时，触屏龙息按钮只控制普通吐息，实体键盘 B 保留特殊吐息。
- DragonTest.lua：dragon_main 复用触屏控件和像素 HUD；PC 默认仍为原调试界面。
- NomiController.lua：速度保留输入幅度；键盘单位输入和对角线行为保持。

## 输入与生命周期

显示坐标和原始触摸坐标均为物理像素 / DPR。安全区取自 UI.GetSafeAreaInsets，再从 UI 基准单位换算为 dp；按钮中心限制在 2dp 网格内侧，避免奇数屏宽时突破 20dp 边距。

所有动作保持到对应手指释放，不以鼠标模拟补触屏。短促碎时点击在同一帧内按下/释放仍可施放一次。帮助、失焦、调试面板、模式开关和 Stop 均清理输入。骑乘地面/空中切换不会让旧按钮上的手指误触新按钮。

按钮本体始终 2×。原“缩放”反馈改成整数描边环、2dp 位移、2/3 帧阶梯透明度；卷轴端头保持 2×，中部宽度按 2dp 变化。

## 验证与限制

2026-11-13 收到“禁止所有本地 Runtime”要求后，没有继续运行任何 preview/validate/UrhoXRuntime。后续验收由主会话统一协调 Web 构建；本任务没有 commit、push 或远端 build。

- 最终静态诊断见 validation/touch-ui/lsp-final.json；Lua 5.4 仅解析检查见 syntax-final.log。
- 禁令前离线输入测试通过 29 项断言（input-test.log），既有 dragon_controls.py 通过（dragon-controls.log）。这些结果早于最后的普通吐息接入与安全区边界收尾，不能冒充最后版本的运行验收。
- 禁令前完整场景本地渲染出现 Metal 顶点描述断言 SIGABRT；原始日志还记录 RuinsFrost.shaderinc 引用未加载。本任务未修改该资源或其他并行着色器。
- 独立 UI fixture 的原始验证报告为 PASS、0 Lua/资源/引擎错误；截图文件未落盘，外层采集为 FAIL。不能据此宣称视觉通过。
- Chrome 844×390、915×412 的徒步/骑乘地面/骑乘空中六张截图：**未验证、尚未取得**。
- 实际 Web 三指并发、普通吐息 held 行为、像素清晰度与完整场景视觉：**未验证**。

文件 tests/touch/input_test.py 为离线回归源；scripts/ui/tests/ 是显式选择才运行的验收 fixture，不由正式游戏入口加载。当前不要执行本地 Runtime fixture。

## 美术侧待确认

全部 PNG 与字体原文件未修改。Maker 官方工具已为 47 张 PNG、字体及其伴随 XML 生成 49 个 .meta，另为 7 个新增 Lua 文件生成 .meta。

现有 assets/Fonts/ArkPixel-12px-zh_hans.xml 引用了缺失的 Fonts/FusionPixel-12px-Prop-zh_hans.ttf；主字体本身存在。是否移除这条 fallback 或补字体由美术/负责人处理。当前没有其他缺图。
