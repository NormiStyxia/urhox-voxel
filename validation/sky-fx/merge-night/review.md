# 云/夜间/AO合并回归修复

仅改验证文件，没有改任何生产Lua/shader/纹理。没有commit/push/build/Runtime/浏览器操作。开工/收工状态见start-status.log、end-status.log。

失败证据：Lead日志validation/night-visibility/lead-motion.log，DayNight.lua:159向量Lerp缺方法。引擎接口证据：.emmylua/Vector3.d.lua:103声明Vector3:Lerp(rhs,t)返回Vector3；examples/30-pelican-bike/scripts/main.lua:146使用smoothFocus:Lerp。旧云fixture只有Normalized而没有Lerp，新DayNight平滑日月交接因此在mock上失败，不是已发现的引擎API错误。

实际改动：

- validation/sky-fx/check.lua、validation/settings/sky-integration.lua：添加返回新向量、不钳制t的逐分量Lerp；后者同时补Vector2.ZERO/Vector4，使当前天空/萤火虫/AO输入构造一致。新增测试验证端点、内插、外插、不改源向量及链式Normalized，未把Lerp替换成固定值。
- 两处SceneQuality集成fixture不再把Terrain置空，读取实际Terrain/Build常量与ColAngle，不创建几何；真实ContactAO模块初始化/档位/昼夜/销毁均运行，追加实际布局和uniform断言。注册顺序加入新scene-night-contact回调，保留天空回调先于场景的要求。
- validation/settings/quality_check.py：沿用设置事件模拟，只补native数学构造；使用真实Terrain/Build/ContactAO，dayNight接收方记录Apply并执行真实AO昼夜强度。额外验证高档强度与低档零；真实DayNight完整行为由云集成与night-visibility检查覆盖。
- validation/sky-fx/check.py、validation/settings/sky_integration.py：旧精确夜间底色断言改为B授权的(0.13,0.17,0.24)，日间(0.30,0.35,0.42)与groundCurve仍严格不变；没有删除配色断言。
- 设置sky-integration旧云影契约仍预期中档0.16与已删除的cloud_shadow_use_atlas，更新为已交付的中档0.08、真实绑定标记、同一wind对象。没有放宽为任意值。

新入口fixture_check.py/gate.py统一检查并保存完整日志。results.log / gate.log：11项PASS；diff-check.log：PASS。包含真实Lua运动与自动降档、矩阵旋转、冷DWP、289时刻风/云影、设置集成/预算、夜间强度/连续交接、ContactAO真实布局/空间数学。没有SurfaceShader实际编译、Web或GPU验收结论。
