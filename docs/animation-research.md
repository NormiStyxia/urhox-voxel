# MC 动作资源调研（2026-11-20）

## 结论

诺米当前是 Blockbench 体素数据 + Lua Node 骨骼，不是 `AnimatedModel`。不能把 `.ani`、FBX 或 GeckoLib 模型文件直接挂到角色上；正确做法是保留现有几何，只把动作关键帧重采样成 `CombatAnim` tracks。

转换入口：`art/animation/bedrock_to_lua.py`。它读取 Bedrock/GeckoLib 风格的 `animations`/`bones` JSON，映射到诺米的 `root/body/head/arm_right/arm_left/forearm_*/leg_*`，并处理 Nomi 的 Z 镜像。

## 候选来源

- [CyberNator](https://github.com/Jbenisek/CyberNator)：MIT，Blockbench 插件内置约 192 个动作模板，包含移动、待机、战斗、翻腾和情绪动作；最适合先在诺米 `.bbmodel` 上生成一版再导出关键帧。
- [bedrock-procedural-animation](https://github.com/plu007-fix/bedrock-procedural-animation)：公开仓库，包含 walk/idle/sneak/sprint/air；它的 contra-body、膝盖补偿、脚接地和跑步垂直节奏很适合迁移到当前 Lua 步态。
- [Gatepost Town Guard](https://blockbenchworkshop.com/model/yair/gatepost-town-guard)：29 骨骼、idle/walk/run/attack 等 8 个片段，页面标注 CC BY 4.0；只能按作者署名和原链接使用，商用前需再核对上传者许可。
- [Timberfell Lumberjack](https://blockbenchworkshop.com/model/yair/timberfell-lumberjack)：27 骨骼、idle/walk/run/work/hurt/death，页面标注 CC BY 4.0，适合参考挥砍和劳动动作。
- [GeckoLib](https://geckolib.org/) / [官方 Blockbench 插件](https://github.com/JannisX11/blockbench-plugins/tree/master/plugins/geckolib)：MIT 运行库和关键帧格式参考，支持 easing、并行轨道和事件关键帧；本身不是动作包。
- [Player Animation Library](https://modrinth.com/mod/player-animation-library)：支持 GeckoLib、Bedrock、Blender/Blockbench 数据，适合作为格式参考。

Fresh Animations、Epic Fight 等资源的模型和动作许可各自不同，目前只参考节奏，不直接复制进项目。

## 试用

```bash
python3 art/animation/bedrock_to_lua.py path/to/animation.json --name mc_walk --output /tmp/mc_walk.lua
```

输出片段应放进 `scripts/combat/AnimClips.lua`，然后用现有 F7 预览逐帧检查。真实 GIF 可以从 Web 预览抓固定帧后用 PIL/imageio 合成；本机 Blender 5.2.1 位于 `/Applications/Blender.app/Contents/MacOS/Blender`，只是没有加入 PATH。
