# 云运动修复自审

范围检查：运行修改只有SkyClouds、SkyAtmosphere云时钟几行、RuinsCloud一句注释。没有改夜间/AO/Scene/设置/地面/备用草/战斗/UI/资产。不提交、不构建、不Runtime、不浏览器。共享Ground只读记录在shared-ground.log，B的AO接线不覆盖。

证实：旧低档强制冻结已用旧源码重现；新真实Lua时钟/材质uniform经过真实shader表达式投影后，0/10/20/60秒有数值及图像位移。真实GameSettings事件自动高→中→低过程中连续走时。冷缓存延迟保留相位/迟到回调不复活，motion=false冻结，超1秒dt不被截短，host刷新不虚增0.2秒。

兼容审查：shader除注释完全一致（hash-check.log）；世界坐标/光照空间和片元一次采样保持原契约，没有新增可能影响SurfaceShader编译的表达式。云影仍消费共享wind，低档关影。材质与图集未改，无新meta。

已读正式sequence-cpu.png：三档固定FOV55/镜头/曝光，0/10/20/60秒。低档20秒偏移细微但可辨；高档近处云比远处快。没有为了更夸张的演示增倍时间或更换形状。两小时实际顶点表达式检查没有整圈挤云、240个真实接缝两侧透明；低档全球最少1片，局部视野空云仍可能发生。

未证实：用户当时实际档位、cloudMotion持久化值、线上资源hash、GPU uniform更新、实际可感知度/5Hz阶梯/帧率/黑屏原因。本机runtime.log不存在，不推断线上无错误；state回执不提供运行参数。B/Lead统一浏览器应核对并观察20秒后再下实机结论。

性能：保持原约5Hz少量uniform，新增每帧仅标量cloudStep累加；无每帧新Lua表/向量、无顶点重建，渲染预算和采样数不变。较快的云会改变屏幕覆盖，所以不声称GPU时间完全相同。

回滚范围见fix.diff，基线before.txt/hash齐全；不要整文件恢复SkyAtmosphere以免删其他并行接口。
