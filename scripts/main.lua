-- ====================================================================
-- main.lua — VoxelTown 入口:官方体素物理脚手架
--
-- 一个完整可玩的小镇沙盒:可破坏的社区建筑(mmmm 模型)、可解体 Assembly
-- 载具、步行角色、四种玩法工具(炸药/散弹枪/喷漆/喷枪)与右键拖拽,
-- N 键昼夜切换(夜晚:月光 + 路灯体积光锥),P 键开关街道水坑。
-- 系统设计文档:docs/design/voxel-physics/;拿它当新项目起点时,先读
-- 项目根的 AGENTS.md。
--
-- 运行:UrhoXRuntime.exe main.lua -tapcode_dir=<本目录> -skip_login
-- ====================================================================

local config = require("config")
local town = require("town")
local vehicles = require("vehicles")
local player = require("player")
local tools = require("tools")
local SkyUtils = require("urhox-libs.Rendering.SkyUtils")

local world
local statusText
local isNight = false
local lightGroupNode = nil
local skyNode = nil
local waterMat_ = nil
local wakeSlots_ = {}          -- [slot0/1] = { entry, prev, trail } 两条船 → shader wake 轨迹链
local wakeClock_ = 0.0
local underwaterOverlay_ = nil
local assemblyAutoLaunchDelay_ = nil
local puddleMaterial = nil
local puddleZone = nil
local puddleHandle = 0
local puddlesEnabled = config.PUDDLES_ENABLED

-- 昼夜两套:光组 XML(CSM/曝光/泛光/雾/体积雾参数,float 属性只能经 XML
-- 反序列化设置)+ SkyUtils 程序化渐变天空(地平线色 == 雾色,零接缝)。
-- 白天体积雾验尸报告:曾经"远处灰蒙蒙"的元凶是摆在视线走廊上的
-- LocalFogVolume 雾团,全局介质在 Absorption=0 下视觉零负担。
local TIME_OF_DAY = {
    day = {
        lightGroup = "LightGroup/TownDay.xml",
        sky = { zenith = Color(0.10, 0.28, 0.66),
                horizon = Color(0.447, 0.638, 1.0), skyExp = 0.5 },
        waterSSS = 1.0,
    },
    night = {
        lightGroup = "LightGroup/TownNight.xml",
        sky = { zenith = Color(0.004, 0.010, 0.035),
                horizon = Color(0.016, 0.055, 0.10), skyExp = 0.55 },
        waterSSS = 0.12, -- 月光弱,透光散射几乎不可见
    },
}

local function ApplyTimeOfDay(scene)
    local preset = isNight and TIME_OF_DAY.night or TIME_OF_DAY.day
    if lightGroupNode ~= nil then lightGroupNode:Remove() end
    local lightGroupFile = cache:GetResource("XMLFile", preset.lightGroup)
    lightGroupNode = scene:CreateChild("LightGroup", LOCAL)
    lightGroupNode:LoadXML(lightGroupFile:GetRoot())

    -- 昼夜切换会销毁旧 Zone;把同一效果重新注册到新的生效 Zone。
    puddleZone = lightGroupNode:GetComponent("Zone")
    puddleHandle = 0
    if puddleMaterial ~= nil and puddleZone ~= nil then
        puddleZone:SetSSREnabled(true)
        puddleHandle = puddleZone:AddGBufferPostProcess(puddleMaterial)
        puddleZone:SetGBufferPostProcessEnabled(puddleHandle, puddlesEnabled)
    end

    if skyNode ~= nil then skyNode:Remove() end
    skyNode = SkyUtils.CreateGradientSky(scene, preset.sky)

    if waterMat_ ~= nil then
        waterMat_:SetShaderParameter("sss_strength", Variant(preset.waterSSS))
    end

    town.SetLampsEnabled(isNight)
end

-- 船尾迹:轨迹链。船尾中心每前进 1m 投一个轨迹点(每船 8 点:p0=当前船尾,
-- 1..7=历史),shader 对相邻点连成的胶囊段做距离场——尾迹沿真实路径弯曲,
-- 随龄扩散消退,不存在解析 V 臂那种硬边/刚性转向(踩过,勿回退成解析式)。
-- 注意:必须每帧设置——SurfaceShader 异步编译/重载会重刷参数默认值,
-- Start 时一次性 SetShaderParameter 会被清掉(踩坑实录,勿改成只设一次)。
local function UpdateBoatWakes(timeStep)
    if waterMat_ == nil then return end
    wakeClock_ = wakeClock_ + timeStep
    -- 纹理与参数同罪:SurfaceShader 异步编译/重载会把 SetSurfaceTexture 一并清掉
    -- (时序随机——曾导致"我看是好的/用户看是坏的"两种状态并存)。每帧重申。
    waterMat_:SetSurfaceTexture("detail_normal",
        cache:GetResource("Texture2D", "Textures/WaterDetailNormal.png"))
    waterMat_:SetSurfaceTexture("foam_tex",
        cache:GetResource("Texture2D", "Textures/WaterFoam.png"))
    for slot, ws in pairs(wakeSlots_) do
        local node = ws.entry.chassis:GetNode()
        if node ~= nil then
            local pos = node.worldPosition
            local dx, dz = pos.x - ws.prev.x, pos.z - ws.prev.z
            local speed = math.sqrt(dx * dx + dz * dz) / math.max(timeStep, 1e-5)
            ws.prev = pos
            local s01 = 0.0
            if speed >= 0.4 then s01 = math.min(speed / 6.0, 1.0) end
            -- 船尾中心(node 原点在网格角上,不是船体中心——踩过)
            local stern = node.worldTransform *
                Vector3(0.12, 0.0, (ws.entry.width or 1.0) * 0.5)
            -- 距离驱动投点,间距随速度缩放(≈0.45s 航程/点,7 点覆盖 ~3s 尾迹;
            -- 固定 1m 间距在 8m/s 时只剩 7m 尾迹——踩过)
            local spacing = math.max(1.2, speed * 0.45)
            local head = ws.trail[1]
            if s01 > 0.0 and (head == nil or
                (stern.x - head.x) ^ 2 + (stern.z - head.z) ^ 2 >= spacing * spacing) then
                table.insert(ws.trail, 1,
                    { x = stern.x, z = stern.z, birth = wakeClock_, inten = s01 })
                if #ws.trail > 7 then table.remove(ws.trail) end
            end
            -- p0 = 当前船尾(age 0,强度=当前速度),链条永远衔接船尾
            waterMat_:SetShaderParameter(string.format("wake%d_p0", slot),
                Variant(Vector4(stern.x, stern.z, 0.0, s01)))
            for i = 1, 7 do
                local tp = ws.trail[i]
                local v = Vector4(0.0, 0.0, 0.0, 0.0)
                if tp ~= nil then
                    local age = wakeClock_ - tp.birth
                    if age < 4.0 then v = Vector4(tp.x, tp.z, age, tp.inten) end
                end
                waterMat_:SetShaderParameter(string.format("wake%d_p%d", slot, i), Variant(v))
            end
            waterMat_:SetShaderParameter("wake_width" .. slot,
                Variant((ws.entry.width or 1.0) * 0.7))
        end
    end
end

-- 相机没入水面 → 全屏水下色调罩层(廉价水下感;Snell 窗之类留给未来)
local function UpdateUnderwater()
    if underwaterOverlay_ == nil then return end
    local cam = player.GetCamera()
    underwaterOverlay_.visible = (cam ~= nil and cam.worldPosition.y < config.WATER_LEVEL)
end

function Start()
    math.randomseed(1337)
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    renderer:SetVolumetricFogFroxelEnabled(true)

    world = scene_:CreateComponent("VoxelPhysicsWorld")
    config.ApplyWorldSettings(world)
    -- 手建槽位必须先于任何 .vox 导入(导入会自动认领空槽)
    config.ApplyPalette(world)

    -- 全局水面:东三分之一是海湾(town.BuildGround 的海床块),引擎按体素
    -- 密度/浮力覆写自动施加阿基米德浮力与水阻——木箱能漂,炸烂的游艇会沉。
    world:SetWaterEnabled(true)
    world:SetWaterLevel(config.WATER_LEVEL)

    town.Build(world)
    -- 视觉回归测试模式(water_test_cam.txt 存在)不出载具:漂移的船进入测试
    -- 视野后,体素船体的 SSR 镜像是合法但强烈的周期结构,会污染水体判定(踩过)。
    -- 机位第 6 个值 =1 时保留载具(载具视觉验证用)。
    local camOv6 = player.GetCamOverride()
    if camOv6 == nil or camOv6[6] == 1 then
        vehicles.SpawnAll(world)

        -- 尾迹槽位:前两条船绑到 shader 的 wake_boat0/1(参数每帧由 UpdateBoatWakes 喂)。
        -- 注意别加 waterMat_ 守卫:水体材质在下面才创建,这里加守卫会静默跳过(踩过)。
        local wakeSlot = 0
        for _, entry in ipairs(vehicles.list) do
            if entry.isBoat and wakeSlot < 2 then
                wakeSlots_[wakeSlot] = { entry = entry, trail = {},
                    prev = entry.chassis:GetNode().worldPosition }
                wakeSlot = wakeSlot + 1
            end
        end
    end

    -- 水面视觉:SurfaceShader 水体(assets/Shaders/BLGL/BayWater.shader)。
    -- 引擎内置 Water.glsl 为遗产路径,本场景不依赖;失败时回退简易 BayWater.xml。
    -- Gerstner 顶点位移需要真实几何:Plane.mdl 只有 4 个顶点,这里用 CustomGeometry
    -- 铺 1.5m 细分网格(40×120 格,一次性构建,位移在 GPU 顶点阶段做)。
    local waterNode = scene_:CreateChild("BayWater")
    waterNode.position = Vector3(60.0, config.WATER_LEVEL, 0.0)
    local waterGeom = waterNode:CreateComponent("CustomGeometry")
    waterGeom:SetNumGeometries(1)
    waterGeom:BeginGeometry(0, TRIANGLE_LIST)
    local halfX, halfZ, cell = 30.0, 90.0, 1.5
    local nx = math.floor(halfX * 2 / cell)
    local nz = math.floor(halfZ * 2 / cell)
    local up = Vector3(0.0, 1.0, 0.0)
    local tangent = Vector4(1.0, 0.0, 0.0, 1.0)
    local function WaterVert(ix, iz)
        local lx = -halfX + ix * cell
        waterGeom:DefineVertex(Vector3(lx, 0.0, -halfZ + iz * cell))
        waterGeom:DefineNormal(up)
        -- 顶点色 R = 离岸波幅衰减:西侧沙滩(世界 x 30~41)波幅归零,
        -- 否则 Gerstner 浪峰会把水面网格顶进滩坡里穿模(踩过)
        local wx = lx + 60.0
        local atten = (wx - 32.5) / 8.5
        if atten < 0.0 then atten = 0.0 elseif atten > 1.0 then atten = 1.0 end
        waterGeom:DefineColor(Color(atten, 1.0, 1.0, 1.0))
        waterGeom:DefineTexCoord(Vector2(ix / nx, iz / nz))
        waterGeom:DefineTangent(tangent)
    end
    for iz = 0, nz - 1 do
        for ix = 0, nx - 1 do
            WaterVert(ix, iz); WaterVert(ix, iz + 1); WaterVert(ix + 1, iz + 1)
            WaterVert(ix, iz); WaterVert(ix + 1, iz + 1); WaterVert(ix + 1, iz)
        end
    end
    waterGeom:Commit()
    waterMat_ = Material:new()
    if waterMat_:SetSurfaceShader("Shaders/BLGL/BayWater.shader") then
        -- 细节法线:FFT 频谱烘焙的定向风浪纹理(引擎自带 WaterNormal.png 是各向同性
        -- 鹅卵石凸包,效果差已弃用);泡沫纹理为本项目生成的 Worley 气泡花边
        waterMat_:SetSurfaceTexture("detail_normal",
            cache:GetResource("Texture2D", "Textures/WaterDetailNormal.png"))
        waterMat_:SetSurfaceTexture("foam_tex",
            cache:GetResource("Texture2D", "Textures/WaterFoam.png"))
        waterGeom:SetMaterial(waterMat_)
    else
        print("VoxelTown: BayWater.shader load failed, fallback to BayWater.xml")
        waterMat_ = cache:GetResource("Material", "Materials/BayWater.xml")
        waterGeom:SetMaterial(waterMat_)
    end
    waterGeom.castShadows = false
    local camOv = player.GetCamOverride()
    if camOv ~= nil then
        player.Init(world, scene_, Vector3(camOv[1], camOv[2], camOv[3]))
        -- 视觉回归机位的第 7 个值可在场景稳定后自动触发撞墙,避免桌面
        -- 自动化按键被首次 shader 编译吞掉;正常游戏仍只由 B 键触发。
        if camOv[7] == 1 then
            assemblyAutoLaunchDelay_ = 1.0
        end
    else
        player.Init(world, scene_, Vector3(-3.0, 2.0, -8.0))
    end
    tools.Init(world, player)

    -- 水坑与海湾共用延迟光照/SSR,不增加水坑平面或修改原始地面材质。
    puddleMaterial = Material:new()
    if puddleMaterial:SetSurfaceShader("Shaders/BLGL/Puddles.shader") then
        puddleMaterial:SetShaderParameter("coverage", Variant(config.PUDDLE_COVERAGE))
        puddleMaterial:SetShaderParameter("puddle_size", Variant(config.PUDDLE_SIZE))
        puddleMaterial:SetShaderParameter("puddle_roughness", Variant(config.PUDDLE_ROUGHNESS))
    else
        print("VoxelTown: Puddles.shader failed to load; puddles are unavailable")
        puddleMaterial = nil
    end
    ApplyTimeOfDay(scene_)

    -- 水下色调罩层(压在所有文字之下,默认隐藏)
    underwaterOverlay_ = ui.root:CreateChild("BorderImage")
    underwaterOverlay_:SetFixedSize(graphics.width, graphics.height)
    underwaterOverlay_.color = Color(0.04, 0.20, 0.28)
    underwaterOverlay_.opacity = 0.5
    underwaterOverlay_.blendMode = BLEND_ALPHA
    underwaterOverlay_.priority = -100
    underwaterOverlay_.visible = false

    statusText = ui.root:CreateChild("Text")
    statusText:SetFont(cache:GetResource("Font", "Fonts/Anonymous Pro.ttf"), 14)
    statusText:SetPosition(12, 12)
    statusText.color = Color(1.0, 1.0, 1.0)

    -- 第三人称工具准星
    local crosshair = ui.root:CreateChild("Text")
    crosshair:SetFont(cache:GetResource("Font", "Fonts/Anonymous Pro.ttf"), 18)
    crosshair.text = "+"
    crosshair.color = Color(1.0, 1.0, 1.0, 0.7)
    crosshair.horizontalAlignment = HA_CENTER
    crosshair.verticalAlignment = VA_CENTER

    -- SceneUpdate: 同帧、自动步进之前触发，输入/施力意图当帧生效（Update 事件在场景步进之后才轮到脚本，会晚一帧）
    SubscribeToEvent("SceneUpdate", "HandleUpdate")
    -- 物理结束后再同步动画参数和第三人称相机。
    SubscribeToEvent("PostUpdate", "HandlePostUpdate")
end

function HandleUpdate(eventType, eventData)
    local timeStep = eventData["TimeStep"]:GetFloat()

    if assemblyAutoLaunchDelay_ ~= nil then
        assemblyAutoLaunchDelay_ = assemblyAutoLaunchDelay_ - timeStep
        if assemblyAutoLaunchDelay_ <= 0.0 then
            vehicles.LaunchAssemblyDemo()
            assemblyAutoLaunchDelay_ = nil
        end
    end
    if input:GetKeyPress(KEY_N) then
        isNight = not isNight
        ApplyTimeOfDay(scene_)
    end
    if input:GetKeyPress(KEY_B) then
        vehicles.LaunchAssemblyDemo()
    end
    if input:GetKeyPress(KEY_P) and puddleZone ~= nil and puddleHandle ~= 0 then
        puddlesEnabled = not puddlesEnabled
        puddleZone:SetGBufferPostProcessEnabled(puddleHandle, puddlesEnabled)
        print("VoxelTown: puddles " .. (puddlesEnabled and "ON" or "OFF"))
    end

    player.Update(timeStep)
    tools.Update(timeStep)
    vehicles.UpdateAll(timeStep)   -- 游艇破舱进水等每帧杂务
    UpdateBoatWakes(timeStep)


    local timeName = isNight and "夜晚" or "白天"
    if player.driving ~= nil then
        if player.driving.kind == "heli" then
            statusText.text = string.format(
                "驾驶中: %s   W/S 前后  A/D 偏航  Space 上升  C 下降  F 下机  N 昼夜[%s]",
                player.driving.name, timeName)
        elseif player.driving.kind == "plane" then
            statusText.text = string.format(
                "驾驶中: %s   W 油门  S 反推  A/D 转向  Space 拉杆  C 推杆  F 下机  N 昼夜[%s]",
                player.driving.name, timeName)
        else
            statusText.text = string.format(
                "驾驶中: %s   W/S 油门  A/D 转向  Space 刹车  F 下车  N 昼夜[%s]\n" ..
                "挖掘机: Q/E 转舱  Z/X 大臂  C/V 斗杆  G 挖掘",
                player.driving.name, timeName)
        end
    elseif player.IsSwimming() then
        statusText.text = string.format(
            "游泳中: WASD 朝视向游  Space 上浮  C 下潜  N 昼夜[%s]\nvolume %d",
            timeName, world.volumeCount)
    else
        statusText.text = string.format(
            "WASD 移动  Shift 跑  Space 跳  C 蹲伏  F 上车  Q 切换工具  R 换弹  N 昼夜[%s]\n" ..
            "工具[%s/姿态:%s]: 1 炸药  2 散弹枪  3 喷漆  4 喷枪   左键 使用  右键 持械瞄准/普通拖动\n" ..
            "volume %d",
            timeName, config.TOOL_NAMES[tools.current],
            player.GetWeaponName(), world.volumeCount)
    end
    local puddleStatus = puddleHandle == 0 and "不可用" or (puddlesEnabled and "开启" or "关闭")
    statusText.text = statusText.text .. "\n[P] 街道水坑[" .. puddleStatus .. "]"
    local assemblyStatus = vehicles.GetAssemblyStatus()
    if assemblyStatus ~= nil then
        statusText.text = statusText.text .. "\n[B] 撞墙演示 | " .. assemblyStatus
    end
    local helicopterStatus = vehicles.GetAssemblyHelicopterStatus(player.driving)
    if helicopterStatus ~= nil then
        statusText.text = statusText.text .. "\n" .. helicopterStatus
    end
end

function HandlePostUpdate(eventType, eventData)
    local timeStep = eventData["TimeStep"]:GetFloat()
    player.PostUpdate(timeStep)
    UpdateUnderwater()
end
