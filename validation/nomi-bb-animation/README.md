# 诺米 BB 原始动画接入（离线验收）

源文件：/Users/xd/Downloads/诺米/诺米.bbmodel。

- 在现有 NomiYSMData.lua 中保存 idle（2 秒/73 根动画骨）、walk（1 秒/112 根）、run（0.6667 秒/111 根）的全部 rotation/position/scale 键。不新增运行时资源或 UUID。
- 按 import_bbmodel.py 同一套别名挂到完整 177 骨层级；保留膝、脚、裙褶位移、外套 Hip/Hem/Tat 与多段发束。原先压到大腿或一片头发上的动画不再参与此模型的基础层。
- 严格使用线性 Euler 采样、BB 的 bind Euler + animation Euler 后 ZYX 组合，以及 Z 轴反射；不是 bind 四元数乘 delta 四元数。已从本机 Blockbench app.asar 的 BoneAnimator.displayRotation/displayPosition 只读核对这两项语义。
- 走跑共用归一化相位。源两腿在半周期时互换；walk/run 的 0 相位均左大腿前、右大腿后，没有另加半周期偏移。三个源循环的首尾键完全一致。
- 沿用控制器测得的 actualSpeed；墙前停止推进相位，移动权重退到待机。4.2m/s 对应 1 秒走路，7.2m/s 对应 0.6667 秒跑步。平滑混合不重启衣摆/发束时钟。
- 游戏的跳跃/蹲下/施法姿态仍叠加在基础层。CombatAnim 保持在基础层之后覆盖；给旧 sprint_loop 加很窄的条件：导入模型使用 BB 的跑步腿/躯干/空手臂，持械臂继续保留游戏覆盖。其它战斗动作、体素模型不改变。
- run 唯一 Molang 项 0.4*ysm.head_yaw 保留为参数系数；可由 Update 的 headYaw 输入驱动。控制器当前没有独立头部 yaw，默认 0。

运行：python3 validation/nomi-bb-animation/check.py。

check.py 对写入 Lua 的全部原键及中间点逐分量比对，并在 9 个相位比对完整父子层级与世界变换；验证待机、走跑频率、挡墙、dt=0、重置攻击残留、旧 sprint 与持械/攻击覆盖。测试只使用数学/Node mock，不运行 UrhoX；不表示 Web 实机视觉验收。

自审已修复的问题：旧 sprint_loop 会覆盖 BB 跑步腿/躯干并将根节点高度回写到旧足底基线；已通过仅对导入模型的两处条件保留原相位和 root bob。尚未进行浏览器、构建或提交。

验收记录：check.log 为 PASS（69,891 个逐分量样本、4,779 组全层级变换）；lsp.log 为 0 个 error；diff-check.log 通过。combat-tests.log 的既有综合套件运行 69 项，55 通过、14 失败；baseline-exact.log 将这 14 项全部对照导入前 checkpoint dfd038f 重现到相同报错行及内容。本次专属覆盖契约与四组 locomotion 测试均通过。
