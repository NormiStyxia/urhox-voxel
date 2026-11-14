# 远端同步复核

- 只有 Nomi 类型声明、桥符文、地形有文本冲突。类型字段并存；桥艺术取完整远端细桥且只移植悬片；Terrain 人工组合空域裁剪与先判新台阶/碰撞-1/视觉-1.2。
- 原版 BuildStairs、BridgeVoxels、HandPos/PrepareCast、Animate/精确瞄准、Scene PostUpdate 与远端区段逐字一致。
- Scene 正午、gateMaterial、相机 NewFX、prepareCast 全保留。安全输入清理只做局部叠加。
- 全部11原文件SHA在首次写回前匹配；scoped stash仅指定10 tracked路径，不含-u。ff后写回前逐文件再与remote原件比对，原stash保留。
- 同步后HEAD=origin/main=19f0d635779e3752d3f0a48c5a36efc62cb5fa84，包含c9df58a后30提交。未创建代码提交/推送/构建。
- 备份：/Users/xd/Desktop/体素test-island-sync-backup-20261114-002042
  - local/原本地文件，base/c9df原件，remote/19f原件，island-original.patch，integrated/整合成品，manifest.json，integrated.sha256.json。
  - 原补丁stash OID：fb68d5822a78eafecf2480f0bc1352c6033e8c64，未drop。
  - 如需重现原始补丁，在独立c9df worktree应用island-original.patch并复制local/docs/空岛地形改造-2026-11-13.md；不要直接把旧stash apply到19f共享main。
  - 本次整合副本保留于 /tmp/island-integration-20261114-002042，主工作区待Maker提交。
- 实际Web/Shader编译、角色爬阶物理和TargetingTest引擎查询仍未验证；只执行远端StairGeometryTest.Structure与真实函数/形状的mock回归。
