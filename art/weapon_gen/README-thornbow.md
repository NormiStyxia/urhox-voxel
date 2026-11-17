# 荆棘花弓数据链

- `thornbow_blender.py`：建模，产出 `out/thornbow_game.json`（Blender 中间数据）。
- `thornbow_export.py`：纠正反射后的三角形绕序、量化、顶点去重，产出
  `assets/model/forge-blades/ThornBow.mesh.json`。只生成数据，不再覆盖 Lua。
- `scripts/combat/models/ThornBow.lua`：通过 `cache:GetFile` / 全局 `cjson`
  加载、校验并缓存数据。调用 `Load()`，共享返回的只读模型表。
- `scripts/combat/ThornBowVisual.lua`：分帧上传、材质、拉弓、沙粒、手持与背挂。
  资源缺失、解析或校验失败时返回错误，沿用原有体素弓回退。

重新导出（项目根目录，Python 需要 numpy）：

```sh
python3 art/weapon_gen/thornbow_export.py
```

可选两个位置参数为输入、输出 JSON 路径。旧命令的 `.lua` 输出会被拒绝，防止覆盖加载器。
首次增加资源时通过 Maker `generate_resource_meta` 生成 `.meta`；重导出保留 UUID。
资源路径在加载器中使用完整字面量，JSON 属于引擎启动前下载资源，不更改项目下载策略。

## 格式 v1

坐标单位米，握把中心为原点，+Y 指向上弓梢，+Z 指向目标，弦在 -Z。
`body`、`crystal`（半透明水晶通道）、`string` 各含 `triangles`、扁平顶点数组 `v`、从 1 开始的索引数组 `i`。
每个顶点 11 个整数：位置 xyz ×10000，法线 xyz ×1000，材质权重 rgb ×100，
alpha 参数 ×100，glow ×100。rgb 分别代表木枝、花瓣、水晶，全零为握把布带；
alpha 表示花瓣根尖位置或布带相位。解码与材质约定保持原版不变。
包围盒、挂点、高度与量化精度同文件保存，避免模型与元数据错配。

## 验证

```sh
python3 tests/combat/run_offline.py
```

需要 `lupa`（Lua 5.4）和 `numpy`。覆盖战斗离线回归、数据校验、失败回退、加载恢复，
并从中间数据重新导出到临时目录，与入库 JSON 逐字节比较。离线检查不证明 Web
资源分发、原生绑定或最终画面正常；这些仍需显式 Web 构建预览验收。
