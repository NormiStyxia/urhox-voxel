# 2026-11-15 实际Web观察（修改前包）

- 入口：https://maker.taptap.cn/app/f323832c-195d-4276-a841-0ceafd1f1cf1?localDev=1&hide_chat=1
- Cindy Chrome自己的cloud-detail-retry标签，未改远端代码/配置；加载曾停在100%，一次恢复后成功进入游戏。其他会话标签未操作。
- latest.json：version 1.0.2，build 27，client b4eac18a，server b905d09d，engine ef9e23e2，generated 2026-11-14T16:30:43.432083Z。
- manifest-b4eac18a.json：project m_hi4f，入口ruins_main.lua。实际网络引擎资源为1.38.11/manifest-d9e7fc92.json，控制台Renderer Type: WebGPU。
- RuinsCloud shader UUID B7kCUdFGjP2SetnaTjmh7PX4，hash 53d97047，3327字节；通过浏览器获取响应体并计算SHA256：60a1067126b4dfa197fabec2476743ccbd431a51561683b1c2ea49c0d3f27aed，与本地修改前一致。
- SkyClouds Lua UUID GZVsubjhgXZh6G1VXJLerni0，hash45e1c5cb；响应为封装二进制，未能文本对比，不声称全包代码一致。
- 高图UUID Hxf6YaCUt5wJjkqmqEq9BrUa/hash2ce42023/1250837字节，低图UUID CH2ukU53R-k9JMWAciHBMyyt/hashf30f716b/315121字节；构建转码尺寸与源PNG不同，未验证其通道像素。

实际读过正午12:00、12:16、12:38、13:06、13:23及17:38夕阳画面。保存detail-web-day.webp（13:23）、detail-web-dusk.webp（17:38）。地形、天空渐变、可见云片轮廓真实可见，但建筑/树与屏幕上边遮住部分云，未取得受控仰角的完整大云特写。普通鼠标操作改变视野但未稳定取得所需角度，停止反复尝试。图片不是新版。

可见云为较大的浅色团块，夕阳中仍近白，内部阴影弱于CPU图。发布贴图数据/实际uniform/曝光差异均待核实；本轮未通过修改远端代码插入诊断，也未凭此改DayNight或场景。画面左下“修复错误1”值得后续核对。已读取控制台，没有发现可明确归因云更新的异常；发现HQ-5qfZwSR37r_zXuUDQ01dw-668d00f6.shader的POSITION导致opaque无deferred pass警告，该UUID不是云shader，不能当云根因。

未保留含preview_login的完整原始控制台。只保存以上无凭证事实。新Web尚未构建，本轮没有新的实际GPU编译/视觉/帧率或历史黑屏验证。
