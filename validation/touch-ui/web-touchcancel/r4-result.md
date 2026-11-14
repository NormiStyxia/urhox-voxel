# 续接 4：登录成功，可信 touchCancel 注入不可用

目标版本：8272fc2；预览 URL：https://maker.taptap.cn/app/f323832c-195d-4276-a841-0ceafd1f1cf1?localDev=1&hide_chat=1
浏览器：Cindy 管理的 external Chrome，CDP；页面 label=touchcancel-web-r3、targetId=8AA91AA51561D08403D5D9C30FA1CAB3。

## 实际步骤

1. Input handoff 结束，nothing_to_fill；实际授权页只有“确认登录”和“取消登录”。
2. 按新快照点击“确认登录”，成功返回目标 Maker 项目，关闭两条产品公告。未读取或填写凭据。
3. 页面含目标游戏 iframe，画面从加载资源 42% 进展至 57%，尚未显示场景。r4-web-loading.png 是实际浏览器截图，已查看。网页尚未取得构建 hash，不能只凭本地 HEAD 断言加载版本已核实。
4. 读取 CDP 能力时确认仅支持有限协议名单；act 操作枚举也没有触摸操作。
5. 实际调用 browser cdp：Input.dispatchTouchEvent，params={type:touchCancel,touchPoints:[]}。工具返回 BROWSER_RUNTIME_INVALID_REQUEST，明确“不支持 Input.dispatchTouchEvent”。该请求未送达浏览器，无正在进行的触摸被取消。原始回执见 r4-touch-protocol.json。
6. 未绕过工具的协议限制，也未用 DOM dispatchEvent 代替可信输入。

## 结果

| 检查 | 预期 | 实际 | 结论 |
|---|---|---|---|
| Maker 登录 | 到目标项目 | 已到项目和目标游戏加载页 | PASS |
| CDP touchCancel 能力 | 命令送达浏览器 | Cindy 工具明确拒绝该协议命令 | FAIL |
| 正常碎时长按松手基线 | 充能、施放一次 | 未实施触屏基线 | UNDETERMINED |
| 充能中 touchcancel | 清充能、不施放、不碎裂 | 无可信触摸注入，未实施 | UNDETERMINED |
| 浏览器 isTrusted 与 Lua 事件 | 记录真实传递路径 | 未取得 | UNDETERMINED |
| 边缘滑出/失焦/菜单 | held 清理、不误施放 | 未实施 | UNDETERMINED |

没有手机真机结果。未修改项目代码、提交/构建或启动本地游戏 Runtime。

## 下一步最小方案

先让 Cindy 浏览器受支持的操作提供可信触摸（至少 Input.dispatchTouchEvent，移动设备模拟还需相应 Emulation 能力），继续使用同一个受管理的专用 Chrome；或由用户在手机真机执行触摸取消并配合录屏/事件日志。当前仅切换 external 不足以开放 touchCancel 命令。
Lua 插桩尚未提出或修改：当前首要阻碍是输入注入未能送达浏览器，不能用改 Lua 绕过。待输入能力可用且场景加载后再检查是否需要只读 charging/lastCast/TouchEnd/TouchCancel 日志。
