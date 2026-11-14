# /review — 设置与日志离线自查

已修正：
- 改用引擎全局 cjson；File WriteString 返回 nil/false 不误判成功。
- 日志、保存、auto、FPS、菜单分别使用独立 LuaScriptObject，不覆盖/取消全局场景事件。
- 调试/FPS 开关不触发所有画质回调，避免无关重建。
- 关闭菜单后保留输入屏障直到所有动作键/指针释放；PC Escape 仍服务浏览器锁定。
- 绘制与原始触摸都走 PixelDraw 的 DPR/整数Zoom坐标；320宽说明换行。
- 原生草关闭后不再更新压草；草簇保留旧几何，仅隐藏批次。
- P95 用预分配固定直方图；默认关闭不分配采样表、不订阅Update、不格式化诊断。
- 后效不关闭 Bloom Enable，避免一并关掉曝光造成过曝。

当前本任务修改范围内未发现阻断问题。跨 worker 接线已复核并补齐：skyfx先注册；托管SetQuality/SetFeature均归一到GameSettings，低空云/云影有持久化键与菜单入口；ApplyProfile重置本地隐藏门控。LightQuality已分离，保持现有实现，离线断言托管ApplyStandaloneScene调用0次，ConfigureScene仅1次。Web savedata 按引擎规定刷新丢失；文档已明确。离线 mock 不替代 GPU/输入/画面验收。

代码归属：新增5个Lua；精确改动7个已有Lua；新增1个交接文档与 validation/settings 检查产物。工作区其他天空/回溯/战斗改动未回滚、未提交。


追加集成自查：
- 当前动态构造按24/12/0云与8/3/0光柱预算运行，真实顶点mock核对1440/720/0云三角、32/12/0光柱三角；保持集中档位与fallback一致，未用旧固定18/3推断覆盖。
- SetQuality(auto)保留auto模式与有效档，off明确为low别名并保留显式覆盖；独立无设置模式保留原off全关语义。
- 七项SetFeature全通过Set并保存；关闭主云不会剩低云；低云/云影覆盖不会被下一次Apply遗忘。
- Stop强引用释放已由天空方补入，现读确认并测试，没有重复改写。
- SceneQuality及LightQuality本轮无需改动；云/光柱/粒子的几何和更新逻辑未改。
- 完成sky_integration、quality_check、ui_check、check及14文件LSP；完整日志在同目录。无本轮范围内遗留离线阻断项；Web仍未验证。
