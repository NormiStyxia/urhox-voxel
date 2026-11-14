# 自查（不是运行验收）
- Height/HeightAt/CollideHeight/RAVINE_Y 全调用审计：固定建筑保护，植被先查岛域，碎片不拿哨兵造地板，渡槽墩只在岛域。
- 顶/底/侧 winding 与 +/-Y 法线检查；同格中心裁剪；共享底边点避免跨块裂缝。Web shader 编译未验证。
- 隐藏 Terrain 仅给草采样，无 CollisionShape，viewMask=0；169顶点/8格patch精确覆盖168m，真实碰撞单独跳空列。GrassField 与隐藏源组合未验证。
- 安全检查先于 Move 排入 Jump；骑乘/过渡旁路。复位输入锁覆盖施法与骑乘控制，直到键松开。
- 低碎片站立脱困；高符脉锚点包围球下界>9.5；实际视角仍需 Web。
- 新龙回调可选，只有遗迹绑定；其他场景默认行为不变。
- 无新增 runtime Lua/资源，沿用已有.meta；文档与离线日志不是 runtime 资源，无需生成 UUID。
- 未提交/构建/启动本地游戏 Runtime，未碰旧浏览器与触屏验收。
