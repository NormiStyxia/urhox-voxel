# P0：云消失的离线追链与最小修复（2026-11-15）

## 结论边界

已证实一个源码级冷缓存缺陷，尚未证实它就是用户build29画面的唯一根因。此前验证把GetResource永远模拟成完整图，没有模拟DWP占位，因此漏掉此问题。新PNG的hash变化会令旧资源缓存失效，与新构建才消失的反馈相容；但未取得用户运行中占位尺寸、cloudUnavailable或下载时序，不能写“实机根因确认/已恢复”。

`engine-docs/recipes/download-while-playing.md`完整说明Texture2D的GetResource可先给占位、下载后热替换；消除跳变应用GetResourceAsync等待真实资源。读取了preload-and-build-refs全文、SurfaceShader材质绑定/失败章节，以及只读urhox-libs/Engine/ResourceCacheExtensions.lua完整实现：GetResourceAsync先Exists，本地已有同步回调，否则下载完成再GetResource。没有修改引擎库。

build29已保存manifest中两图没有blocking组；脚本/材质/shader是blocking，启动时可先于图集准备好。旧SkyClouds.Init立即GetResource(Texture2D)，尺寸不是2048×1024或1024×512就unavailable=true并丢弃texture，不建material/root。Update/Follow不会重新加载，ApplySwitches在预算/upper/lower相同时也不会重建失败实例。即使引擎后来热替换占位纹理，也无可显示节点。这是**先误判失败，永久隐藏**，而不是纹理自动完成后会自行显示。

## 最小修复

运行只改scripts/ruins/SkyClouds.lua：改用GetResourceAsync，完成回调进入CompleteAtlas，真实资源就绪后才验证尺寸/创建原网格与材质。等待时无节点/白块、无轮询/重试。保留严格尺寸和真正下载/绑定/编译失败的安全隐藏。回调检查disposed/loading，切档/关闭后迟到结果不能复活旧实例；不取消共享下载。等待期间只暂存昼夜引用和最新跟随位置，显示前应用当前颜色与包围盒位置，避免夜间闪白或高空首次剔除。缓存热路径仍同步完成。shader/图集/颜色/布局/数量/世界方向均未改。

## 隐藏路径逐项

| 路径 | 源码行为与可证伪观察 |
|---|---|
| 设置clouds=false | GameSettings.Resolve将cloudCount=0、cloudsEnabled=false，ApplySwitches不建云；settings.json会持久化，当前用户实际值未读取。high/medium/low默认24/12/4均开云，auto降档不会降到0。 |
| lowClouds=false | 只减下半球，不应让上半球消失；低档只有4个地平线云，单朝向可无云。 |
| 占位/尺寸失败 | 上述已复现缺陷。新回调在资源就绪后才检查；若真实GPU尺寸被其他纹理质量策略缩小仍可能失败，需Web记录实际width/height。 |
| 真实下载失败/nil | 当前候选unavailable=true、无节点，无自动重试；切换不同预算或关闭再开可建立新实例。同档Set返回早，不是重试。 |
| SetSurfaceShader/SetSurfaceTexture=false | 清理材质/贴图并隐藏；只有DebugLog开启才打印SkyFx提示；引擎错误另行记录。SetSurfaceTexture名称cloud_atlas与shader一致；返回类型在绑定声明中为boolean。 |
| cloud_enabled | XML和shader默认0；只在两项绑定成功后写Variant(1)，无后续归零调用。Update不负责修复失败初始化。材质Clone正常路径在设shader后写覆盖，不被本项目随后重设。实际GPU值尚未读取。 |
| renderer/node disabled | Cloud脚本没有将root/geometry设disabled；root为Scene子节点，非相机子节点；Dispose明确销毁。当前场景调用Update受atmosphere.active与Safe保护，若发生异常可影响Follow，实际异常尚未见。 |
| 包围盒/投影 | Follow平移到玩家/骑龙位置，两个零面积三角扩大±2048m界；shader按相机位置平移固定天球。此次shader和布局未动，不能用矩阵数值测试证明实际可见。 |

## PNG/manifest证据

父版与1a78a3d高/低图均RGBA8、PNG color type6、无交错；只有IHDR/IDAT/IEND，无iCCP/sRGB/gAMA/tRNS等新增profile/调色板块。尺寸保持2048×1024及1024×512；两meta仍仅原UUID，未改变。线性是在Lua纹理对象上设sRGB=false，不是meta已有线性字段。源图A仍有完整非零覆盖。

远端manifest的size1250837/315121是**转码文件字节数，不是纹理宽高**，新旧byte size相同也不能证明像素/维度/格式相同。远端hash已变；没有读取转码头部或GPU尺寸，不能排除转码通道问题。在线shaderSHA256已与本地1a78a3d一致；新增shape_light、mix等目前没有实际编译失败证据，不盲目回滚fragment。

## 离线验证与自审

missing_dwp_check.py用真实旧/新Cloud Lua及只读执行实际ResourceCacheExtensions.lua，底层下载队列/纹理以mock提供：旧版收到1×1占位后，真实尺寸到达再过600帧仍隐藏；新版不读取占位，下载成功只建一次，先应用夜色/30000m跟随位置；缓存热加载立即就绪；高/中/低Dispose迟到回调被丢弃；下载中高切低仅新实例生成；真实下载失败不重试；关闭600帧无资源工作。测试不模拟GPU编译/真实下载时序。

现有check.lua与settings/sky-integration.lua仅补同步就绪的GetResourceAsync mock，原设置/开关/资源失败/日志零格式化断言保留。LSP Error=0；新增代码无每帧资源查询/顶点上传/日志构造。源码自审检查回调重入、Dispose后scene=nil、重复完成、夜间延迟出现和旧材质泄漏。

## 待协调后的最小Web顺序（尚未执行）

1. 保留自己的诊断tab，不清其他标签；确认仍build29/hash6b06cfa1，读取现有控制台与云PNG请求状态，先判断场景已ready而非loading100%。
2. 读取设置界面的clouds/lowClouds/质量实际值。不得为验证擅改全局日志配置；若不能读运行对象，就如实留白，不从缺少日志推断正常。
3. 若宿主已有只读Lua/对象检查，记录clouds是否nil、budget/count/ready/unavailable、贴图width/height、material/root和cloud_enabled；不注入新shader或远端修改。若unavailable=true且请求后来200，重点验证DWP尺寸时序；若ready=24且纹理/参数正常，再查GPU编译/可见性。
4. 协调允许普通交互后，绕一圈并仰视区分“所有云都没了”和“低档该方向没有云”。保存画面、时刻、设置，不用CPU图代替。
5. 候选修复尚未构建，现有Web不会包含GetResourceAsync改动。需用户另行明确构建后验证新图冷缓存首次打开、热缓存重进、下载中切档/关云、夜间迟到加载和手机网络。

本段期间按Lead要求完全未操作浏览器。此前自己的诊断页消失只记录事实，不归因任何具体会话。未构建/提交/Runtime/Git同步；并行战斗/UI差异保留。
