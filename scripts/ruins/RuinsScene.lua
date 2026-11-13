-- ====================================================================
-- RuinsScene.lua — 时之遗迹：场景装配、输入、相机、谜题流程、龙看守者
--
-- 模块：
--   RuinsTerrain  地形（盆地 / 峡谷 / 梯田山脊）     RuinsBuild   静态建筑与景观
--   RuinsPuzzles  时之物件与谜题进度                 TimeObject   碎时 / 冻结 / 回溯的物件模型
--   TimeSpells    法术定义（数据驱动）+ 特效          NomiController 诺米步行 + 第三人称瞄准
--   RuinsHUD      目标 / 法术槽 / 准星 / 提示
-- 龙：复用 dragon/ 的骨架、动画控制器与骑乘（DragonRide 的步行部分交给 NomiController）。
-- 龙在苏醒前趴在祭坛上沉睡（不走动、不可骑）；四座时之碑复原后苏醒，之后可以骑乘飞行。
-- 巨龙动画测试面板（DragonDebugUI）不在本场景加载；需要时把 DEBUG_PANEL 设为 true（F10 切换）。
-- ====================================================================

local Pal = require("ruins.RuinsPalette")
local Brush = require("ruins.VoxelBrush")
local DayNight = require("ruins.DayNight")
local Terrain = require("ruins.RuinsTerrain")
local Build = require("ruins.RuinsBuild")
local Puzzles = require("ruins.RuinsPuzzles")
local Spells = require("ruins.TimeSpells")
local Sigil = require("ruins.TimeSigil")
local RuinsDragon = require("ruins.RuinsDragon")
local Nomi = require("ruins.NomiController")
local HUD = require("ruins.RuinsHUD")
local TouchInput = require("ui.TouchInput")
local TouchControls = require("ui.TouchControls")
local touchRevision = 0
local Rig = require("dragon.DragonRig")
local Controller = require("dragon.DragonAnimationController")
local Variants = require("dragon.DragonVariants")
local DragonRide = require("dragon.DragonRide")
local Breath = require("dragon.DragonBreath")
local PlatformUtils = require("urhox-libs.Platform.PlatformUtils")
local PointerCapture = require("ruins.PointerCapture")
Breath.Register(Controller)

---@class RuinsSceneModule
---@field fake table|nil
---@field fakePress table|nil
---@field forceCamMode string|nil
---@field stream table|nil Ordinary breath owned by RuinsDragon.
local M = {}

M.DEBUG_PANEL = false   -- 巨龙动画测试面板：默认隐藏（代码保留在 dragon/DragonDebugUI.lua）
M.SPAWN = Vector3(0, Terrain.RING_Y + 0.1, -64.0)
M.DRAGON_POS = Vector3(0, 0.5, 4.0)  -- 祭坛中心（台面 y=0.5）
M.DRAGON_YAW = 180.0                 -- 头朝南（面向入口阶梯）

---@type Scene
local scene_ = nil
---@type VoxelPhysicsWorld
local world_ = nil
---@type NomiController
local nomi_ = nil
---@type TimeCaster
local caster_ = nil
---@type TimeFX
local fx_ = nil
local time_ = 0
local perf = { elapsed = 0.0, frames = 0, peak = 0.0 }
local stage_ = "gate"
local mouseLocked = false
local farView = false
local isWeb = PlatformUtils.IsWebPlatform()
local resumeHint = isWeb and "点击激活画面 · 未锁定时按住鼠标拖动视角 · 再点击可锁定" or "点击画面锁定鼠标 · Esc 释放"
local inputTakenOver = false
local drag = { buttons = 0, x = 0, y = 0, distance = 0, samples = 0 }
local pointer = PointerCapture.New({
    web = isWeb,
    now = function() return GetTime():GetElapsedTime() end,
    focused = function() return input.focus and not input.minimized end,
    captured = function()
        if isWeb then return input:IsMouseLocked() end
        return input.mouseMode == MM_RELATIVE
    end,
    request = function()
        if not TouchInput.IsEnabled() then input:SetMouseMode(MM_RELATIVE) end
    end,
    release = function()
        input:SetMouseMode(MM_FREE)
        input:SetMouseGrabbed(false)
        input:SetMouseVisible(true)
    end,
    changed = function(locked, reason)
        mouseLocked = locked
        if locked or reason == "escape" or reason == "focus" or reason == "panel" or reason == "stop" then
            drag.buttons = 0
        end
        if not locked then input:SetMouseVisible(true) end
        if reason ~= "fallback" and not locked and caster_ ~= nil then
            caster_.charging, caster_.charge = false, 0
        end
        local hint = locked and "" or (M.debugOn and "F10 关闭调试面板后，点击画面继续" or resumeHint)
        if reason == "fallback" then hint = "未锁定：按住鼠标拖动视角 · 技能可用 · 点击可重试锁定" end
        if reason == "activate" then hint = "画面已激活：按住拖动视角 · 再点击可请求锁定" end
        HUD.SetHint(hint)
        print("RuinsScene: pointer " .. reason .. ", mode=" .. tostring(input.mouseMode))
    end,
})

local function Clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
local function Smooth(t) t = Clamp(t, 0, 1) return t * t * (3 - 2 * t) end

-- ---------------------------------------------------------------- 目标文本
local OBJECTIVES = {
    gate = { "打通被封的城门", "南门被碎石堵住了。准星对准碎石，按左键施放「碎时」把它打碎。" },
    bridge = { "修复断桥", "古桥碎落在峡谷里。对准任意一块带金色符脉的桥体碎片，按 Q 施放「回溯」。" },
    key = { "取得时之钥", "时之碑被封印了。西侧塔台顶上有「时之钥」：打碎悬石，趁碎块下落时按 E「冻结」，踩着碎块爬上塔台。" },
    steles = { "复原四座时之碑", "带着时之钥回到内环，对倒塌的时之碑按 Q 施放「回溯」。（%d / 4）" },
    awake = { "遗迹看守者已苏醒", "巨龙认可了你。走近它按 F 骑乘，Space 起飞。时之物件仍可以随意碎时 / 冻结 / 回溯。" },
}

local function RefreshObjective()
    local o = OBJECTIVES[stage_]
    if o == nil then return end
    local n = 0
    for i = 1, 4 do if Puzzles.steps["stele" .. i] then n = n + 1 end end
    HUD.SetObjective(o[1], string.format(o[2], n))
end

local function SetStage(s)
    stage_ = s
    RefreshObjective()
    print("RuinsScene: stage -> " .. s)
end

local banner = { text = nil, t = 0 }
local function Banner(text, dur)
    banner.text, banner.t = text, dur or 3.0
    HUD.SetMessage(text)
end

-- ---------------------------------------------------------------- 光照 / 氛围
M.START_HOUR = 12.0   -- 正午开场，常速约 12 分钟后日落。
local function SetupLighting()
    local lg = scene_:CreateChild("LightGroup")
    lg:LoadXML(cache:GetResource("XMLFile", "LightGroup/RuinsDay.xml"):GetRoot())
    local zone = lg:GetComponent("Zone")
    M.zone = zone
    local sunNode = lg:GetChild("Directional Light")
    M.sun = sunNode:GetComponent("Light")
    -- 保留近景阴影；减少远级联和每像素 PCF 采样，不关闭建筑/角色阴影。
    local sun = M.sun
    sun.castShadows = true
    sun.shadowCascade = CascadeParameters(10.0, 38.0, 140.0, 0.0, 0.85)
    renderer.shadowPCFSamples = 4
    sun.shadowBias = BiasParameters(0.00025, 0.6)
    sun.shadowIntensity = 0.0
    sun.shadowResolution = 1.0
    renderer.shadowMapSize = 2048
    -- 天空 + 昼夜（环境光由 SkyLightCapture 跟随天空，替代旧的渐变天空和补光）
    M.dayNight = DayNight.New({ scene = scene_, zone = zone, zoneNode = lg, sun = sun, sunNode = sunNode, hour = M.START_HOUR })
    -- 尺寸与砌筑类型共同缓存；谜题、雕像、金饰不自动套墙砖纹。
    local vmats = {}
    M.surfaceMaterials = vmats
    Brush.materialFor = function(size, masonry)
        local key = tostring(size) .. ":" .. (masonry or "plain")
        local m = vmats[key]
        if m ~= nil then return m end
        m = Material:new()
        if not m:SetSurfaceShader("Shaders/BLGL/RuinsVoxel.shader") then
            print("RuinsScene: RuinsVoxel.shader failed, using palette material")
            Brush.materialFor = nil
            return nil
        end
        m:SetSurfaceTexture("palette_tex", world_:GetPaletteTexture())
        m:SetShaderParameter("voxel_size", Variant(size))
        m:SetShaderParameter("masonry_mode", Variant(masonry == "ring" and 2.0 or (masonry == "floor" and 3.0 or (masonry == "ashlar" and 1.0 or 0.0))))
        m:SetShaderParameter("wall_radius", Variant(Terrain.WALL_R))
        vmats[key] = m
        return m
    end
    -- 法阵灯：龙庭中央的蓝色点光（苏醒时变亮）
    local rl = scene_:CreateChild("CourtLight")
    rl.position = Vector3(0, 3.0, 0)
    local l = rl:CreateComponent("Light")
    l.lightType = LIGHT_POINT
    l.range = 26
    l.brightness = 0.0
    l.color = Color(0.35, 0.55, 1.0)
    M.courtLight = l
end

-- ---------------------------------------------------------------- 龙
local function SetupDragon()
    M.variant = "large"
    local rig = Rig.Build(scene_, world_, nil, Variants.Get(M.variant))
    local ctrl = Controller.New(rig, world_)
    M.rig, M.ctrl = rig, ctrl
    ctrl:Teleport(M.DRAGON_POS, M.DRAGON_YAW)
    M.breath = Breath.New(scene_, rig, ctrl, M.variant, nil)
    -- DragonRide 需要 DragonTest 风格的宿主表：nomi、nomiNode、rig、ctrl、breath
    M.nomi = nomi_.nomi
    M.nomiNode = nomi_.node
    local ride = DragonRide.New(M)
    -- DragonRide.New 会把诺米摆到测试场的默认位置，这里放回出生点
    nomi_.node.worldPosition = M.SPAWN
    nomi_.node.rotation = Quaternion(nomi_.yaw, Vector3.UP)
    nomi_.cc:Teleport(M.SPAWN)
    ride.pos = M.SPAWN
    ride.yaw = nomi_.yaw
    ride.external = true
    ride.aiOff = true
    ride.locked = true
    ride.lockedHint = ""
    ride.wander = { center = M.DRAGON_POS, min = 3, max = 11 }
    ride.node = nomi_.node
    ride.controlsEnabled = function() return not M.debugOn and not TouchControls.IsBlocked() and (TouchInput.IsEnabled() or pointer:IsEnabled() or M.fake~=nil) end
    ride.onNotice = function(text) caster_:Say(text) end
    ride.onMount = function()
        caster_.charging,caster_.charge=false,0
        nomi_.cc.enabled = false
        M.mounted = true
    end
    ride.onDismount = function(pos)
        nomi_.cc.enabled = true
        nomi_.cc:Teleport(pos + Vector3(0, 0.2, 0))
        nomi_.node.rotation = Quaternion(nomi_.yaw, Vector3.UP)
        M.mounted = false
    end
    M.ride = ride
    M.dragonWorld=RuinsDragon.New(M,world_,nomi_,Puzzles,Terrain)
    -- 沉睡：趴伏 + 闭眼（动画控制器没有睡眠状态，用暂停在待机第一帧并降低身体）
    M.dragonAwake = false
    M.sleepK = 1.0
    print("RuinsScene: dragon ready (" .. M.variant .. ")")
end

-- 沉睡姿态用绝对基姿态，不依赖每帧完整 FK/IK 重置来避免累积下沉。
local sleepBase = { valid = false, position = Vector3.ZERO, neck = {} }
local function UpdateDragonPose(dt)
    local ctrl, rig = M.ctrl, M.rig
    local sleeping = not M.dragonAwake and not M.debugOn and ctrl.state == "IDLE"
        and not ctrl.jointTest.enabled and not ctrl.loco.airborne
    if not sleeping then
        sleepBase.valid = false
        ctrl:Update(dt)
        return
    end
    ctrl.input.move, ctrl.input.turn = 0, 0
    if not sleepBase.valid then
        ctrl:Update(0)
        sleepBase.position = rig.root.position
        for _, name in ipairs({ "neck1", "neck2", "head" }) do
            sleepBase.neck[name] = rig.bones[name].rotation
        end
        sleepBase.valid = true
        print("RuinsPerf: sleeping dragon pose cached")
    end
end

local function ApplySleepPose(dt)
    local rig = M.rig
    if M.sleepK <= 0.001 then return end
    local k = Smooth(M.sleepK)
    local breathe = math.sin(time_ * 0.9) * 0.04
    local base = sleepBase.valid and sleepBase.position or rig.root.position
    rig.root.position = base + Vector3(0, (-0.55 + breathe) * k * (rig.size or 1), 0)
    local function Bend(name, pitch)
        local b = rig.bones[name]
        if b ~= nil then
            local rotation = sleepBase.valid and sleepBase.neck[name] or b.rotation
            b.rotation = rotation * Quaternion(pitch * k, Vector3.RIGHT)
        end
    end
    Bend("neck1", 14); Bend("neck2", 10); Bend("head", 16)
end

local function WakeDragon()
    if M.dragonAwake then return end
    M.dragonAwake = true
    M.wakeT = 0
    M.ride.locked = false
    Banner("遗迹看守者 · 苏醒", 4.0)
    print("RuinsScene: dragon awakening")
end

-- ---------------------------------------------------------------- 谜题事件
local function OnPuzzle(name, data)
    if name == "gate" then
        Banner("城门已打通", 2.5)
        SetStage("bridge")
    elseif name == "bridge" then
        Banner("古桥 · 复原", 2.5)
        SetStage(Puzzles.steps.key and "steles" or "key")
    elseif name == "key" then
        Banner("获得「时之钥」——时之碑的封印解除了", 3.5)
        fx_:Burst(Puzzles.KEY_POS, "restore", 1.5)
        SetStage("steles")
    elseif name == "stele" then
        Banner(string.format("时之碑 %d / 4", data.count), 2.5)
        M.runeTarget = data.count / 4 * 0.6
        RefreshObjective()
    elseif name == "awake" then
        M.runeTarget = 1.0
        SetStage("awake")
        WakeDragon()
    end
end

-- Touch state is sampled from the actual gameplay state, never inferred from UI.
local function AttachTouchControls()
    local cooldown = {}
    for _,sp in ipairs(Spells.SPELLS) do cooldown[sp.id]=sp.cooldown end
    TouchControls.Attach(HUD.root,function()
        local ride,ctrl=M.ride,M.ctrl
        return { mounted=ride.mode~="free", mounting=ride.mode=="mounting",
            airborne=ctrl.loco.airborne, gliding=ctrl.state=="GLIDE", blocked=M.debugOn,
            breathActive=M.stream and M.stream.active,
            canMount=M.dragonAwake and not ride.locked and ride.mode=="free" and ride.onGround and ride:NearDragon()<3.6,
            cool=caster_.cool, cooldown=cooldown, charging=caster_.charging,
            charge=caster_.charging and caster_.charge or 0 }
    end,function(on)
        pointer:Release("touch-mode")
        drag.buttons=0
        caster_.charging,caster_.charge=false,0
    end,function()
        caster_.charging,caster_.charge=false,0
        if M.stream then M.stream:Stop(true) end
    end)
end

-- ---------------------------------------------------------------- 启动
function M.Start()
    TouchInput.Detect()
    -- 引擎的自动点击重锁没有 UI / pending 过滤；接管一次，避免两个管理者竞争。
    if not inputTakenOver then
        local uninstall = _G["InputExtensions_Uninstall"]
        if type(uninstall) == "function" then uninstall() end
        inputTakenOver = true
    end
    pointer:Release("start")
    local t0 = GetTime():GetElapsedTime()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")
    world_ = scene_:CreateComponent("VoxelPhysicsWorld")
    -- 碎块预算（移动端友好）
    world_.maxFrozenFragments = 220
    world_.maxSpallChunks = 14
    world_.spallChunkVoxels = 3
    world_.spallSpeed = 3.0
    world_.minFragmentVoxels = 4
    world_.debrisMaxAge = 25.0
    world_.damageNoise = 0.45
    world_:SetMeshLodDistance(55.0)
    Pal.Setup(world_)
    SetupLighting()
    Terrain.Build(world_, scene_)
    Build.Build(world_, scene_)
    Puzzles.Build(world_, scene_)
    world_:OptimizeBroadPhase()
    Puzzles.On(OnPuzzle)

    nomi_ = Nomi.New(scene_, world_, M.SPAWN, 0)
    renderer:SetViewport(0, Viewport:new(scene_, nomi_:Camera()))
    fx_ = Spells.NewFX(scene_, nomi_:CameraNode())
    M.sigils=Sigil.New(scene_)
    caster_ = Spells.NewCaster({ world = world_, puzzles = Puzzles, scene = scene_, fx = fx_, sigils = M.sigils,
        handPos = function() return nomi_:HandPos() end,
        prepareCast = function(aim) nomi_:PrepareCast(aim) end }) -- 同帧转身与抬手
    SetupDragon()

    sleepBase.valid = false
    -- 龙体是纯视觉部件，不让瞄准 Grid 把它当成可破坏场景。
    for _, part in pairs(M.rig.parts) do
        if part.volume then part.volume.collisionLayer = 2; part.volume.collisionMask = 0 end
    end
    nomi_.aimMask = 0xffffffff & ~2
    HUD.Build(Spells.SPELLS)
    AttachTouchControls()
    SetStage("gate")
    HUD.SetHint(resumeHint .. "  ·  H 隐藏说明")
    if M.DEBUG_PANEL then M.ToggleDebugPanel() end

    SubscribeToEvent("Update", "Ruins_HandleUpdate")
    SubscribeToEvent("PostUpdate", "Ruins_HandlePostUpdate")
    SubscribeToEvent("SceneUpdate", "Ruins_HandleSceneUpdate")
    SubscribeToEvent("MouseButtonDown", "Ruins_HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "Ruins_HandleMouseUp")
    SubscribeToEvent("MouseMove", "Ruins_HandleMouseMove")
    SubscribeToEvent("MouseModeChanged", "Ruins_HandleMouseModeChanged")
    SubscribeToEvent("KeyDown", "Ruins_HandleKeyDown")
    SubscribeToEvent("InputFocus", "Ruins_HandleInputFocus")
    RUINS = M
    M.scene, M.world, M.puzzles, M.nomiCtl, M.caster, M.fx = scene_, world_, Puzzles, nomi_, caster_, fx_
    print(string.format("RuinsScene: ready in %.2fs, volumes %d", GetTime():GetElapsedTime() - t0, world_:GetVolumeCount()))
end

-- 巨龙动画测试面板（隐藏，F10 打开；面板代码在 dragon/DragonDebugUI.lua）
function M.ToggleDebugPanel()
    M.debugOn = not M.debugOn
    pointer:SetBlocked(M.debugOn)
    if M.debugOn then
        local DebugUI = require("dragon.DragonDebugUI")
        DebugUI.Build(M.ctrl, M)
    else
        HUD.Build(Spells.SPELLS)
        AttachTouchControls()
        RefreshObjective()
        HUD.SetHint(resumeHint)
    end
end
-- DragonDebugUI 回调需要的字段 / 方法（面板打开时才用到）
M.cam = { yaw = 0, pitch = 0, dist = 10, target = Vector3(0, 0, 0), follow = true, pan = Vector3(0, 0, 0) }
M.showSkeleton, M.showHitZones, M.showStrips, M.showFeet, M.showNomi, M.playMode = false, false, false, false, true, true
M.breathStyle = "pixel"
function M.SetPlayMode(on) M.playMode = on end
function M.SetView() end
function M.RequestVariant() end
function M.ToggleBreathStyle() end
function M.ApplyCamera() end

-- ---------------------------------------------------------------- 输入
-- 拖动走事件中的绝对坐标差，不依赖未锁定时可能被归零的帧级 mouseMove。
---@param eventType string
---@param eventData MouseButtonDownEventData
function Ruins_HandleMouseDown(eventType, eventData)
    if TouchInput.IsEnabled() then return end
    local button = eventData:GetInt("Button")
    if button ~= MOUSEB_LEFT and button ~= MOUSEB_RIGHT and button ~= MOUSEB_MIDDLE then return end
    -- 正常 HUD 全部是展示层；只有打开调试面板时才禁止玩法拖动。
    if M.debugOn then return end
    if not mouseLocked then
        drag.buttons = drag.buttons | (1 << button)
        drag.x, drag.y = eventData:GetInt("X"), eventData:GetInt("Y")
        drag.distance, drag.samples = 0, 0
        print(string.format("RuinsInput: drag begin button=%d pos=%d,%d focus=%s", button, drag.x, drag.y, tostring(input.focus)))
    end
    pointer:Resume()
end

---@param eventType string
---@param eventData MouseMoveEventData
function Ruins_HandleMouseMove(eventType, eventData)
    if TouchInput.IsEnabled() then return end
    if mouseLocked or M.debugOn or nomi_ == nil or drag.buttons == 0 then return end
    local x, y = eventData:GetInt("X"), eventData:GetInt("Y")
    local dx, dy = x - drag.x, y - drag.y
    drag.x, drag.y = x, y
    if dx == 0 and dy == 0 then return end
    nomi_:Look(dx, dy, 0.12)
    drag.distance = drag.distance + math.abs(dx) + math.abs(dy)
    drag.samples = drag.samples + 1
    if drag.samples == 1 then
        print(string.format("RuinsInput: drag move delta=%d,%d yaw=%.2f", dx, dy, nomi_.camYaw))
    end
end

---@param eventType string
---@param eventData MouseButtonUpEventData
function Ruins_HandleMouseUp(eventType, eventData)
    if TouchInput.IsEnabled() then return end
    local button = eventData:GetInt("Button")
    local bit = 1 << button
    if drag.buttons & bit == 0 then return end
    drag.buttons = drag.buttons & (~bit)
    print(string.format("RuinsInput: drag end samples=%d distance=%d", drag.samples, drag.distance))
    -- 纯点击才申请锁定；拖动途中不切换模式，否则失败请求会破坏绝对坐标输入。
    if button == MOUSEB_LEFT and drag.distance < 4 and not M.debugOn then pointer:Click(false) end
end

---@param eventType string
---@param eventData MouseModeChangedEventData
function Ruins_HandleMouseModeChanged(eventType, eventData)
    if TouchInput.IsEnabled() then return end
    pointer:ModeChanged(eventData:GetInt("Mode") == MM_RELATIVE, eventData:GetBool("MouseLocked"))
end

---@param eventType string
---@param eventData KeyDownEventData
function Ruins_HandleKeyDown(eventType, eventData)
    if TouchInput.IsEnabled() then return end
    local key = eventData:GetInt("Key")
    if key == KEY_ESCAPE then
        pointer:Release("escape")
    elseif key == KEY_E or key == KEY_Q or key == KEY_W or key == KEY_A or key == KEY_S or key == KEY_D then
        pointer:Resume()
    end
end

---@param eventType string
---@param eventData InputFocusEventData
function Ruins_HandleInputFocus(eventType, eventData)
    if not eventData:GetBool("Focus") or eventData:GetBool("Minimized") then
        drag.buttons = 0
        pointer:Release("focus")
    end
end

-- M.fake / M.fakePress：自动化测试注入按键（正常游戏为 nil）
local function Down(k)
    if M.fake ~= nil and M.fake[k] ~= nil then return M.fake[k] end
    return input:GetKeyDown(k) or TouchInput.KeyDown(k)
end
local function Press(k)
    if M.fakePress ~= nil and M.fakePress[k] then M.fakePress[k] = nil return true end
    return input:GetKeyPress(k) or TouchInput.KeyPress(k)
end

-- Ordinary breath: the right-hand breath button is held input. Keyboard B
-- remains the separate special breath in DragonRide; simulated touch mouse is ignored.
function M.readStreamInput()
    local touch=TouchInput.IsEnabled()
    local mounted=M.ride and M.ride.mode=="mounted"
    local allowed=mounted and M.ctrl.state~="BREATH"
        and not M.debugOn and not TouchControls.IsBlocked()
        and input.focus and not input.minimized
        and (touch or pointer:CanAttack() or M.fake~=nil)
    local held=mounted and (TouchInput.Down("breath") or Down(KEY_1)
        or (not touch and pointer:CanAttack() and input:GetMouseButtonDown(MOUSEB_LEFT)))
    return held,allowed
end

-- 当前瞄准目标（时之物件）
local function UpdateAim()
    local aim = nomi_:Aim(60.0)
    if aim.hit then aim.object = aim.object or Puzzles.FindByVolume(aim.volume) end
    M.aim = aim
    local obj = aim.object --[[@as TimeObject?]]
    local signature = obj and (obj.id .. ":" .. obj.state) or (aim.breakable and "breakable" or "none")
    if signature ~= M.lastAimSignature or time_ >= (M.nextAimLog or 0) then
        M.lastAimSignature = signature
        M.nextAimLog = time_ + 3
        local volume = aim.volume --[[@as VoxelVolume?]]
        local node = volume and volume:GetNode()
        print(string.format("RuinsAim: target=%s assisted=%s origin=%s dir=%s hit=%s distance=%.3f volume=%s id=%s layer=%s voxel=%s player=%s yaw=%.2f pitch=%.2f",
            signature, tostring(aim.assisted == true), tostring(aim.origin), tostring(aim.dir), tostring(aim.pos),
            aim.distance or -1, node and node.name or "none", tostring(aim.volumeId),
            volume and tostring(volume.collisionLayer) or "none", tostring(aim.voxel),
            tostring(nomi_:Position()), nomi_.camYaw, nomi_.camPitch))
    end
    if obj ~= nil then
        obj.hoverTarget = 1
        local st = ({ WHOLE = "完整", SHATTERED = "破碎中", FROZEN = "已碎", REWIND = "回溯中" })[obj.state] or ""
        if obj.state == "FROZEN" and not obj.rubble then st = "冻结" end
        local actions = (obj.canShatter and "  [左键 碎时]" or "") .. (obj.canRewind and "  [Q 回溯]" or "")
        HUD.SetTarget(string.format("◆ %s · %s%s", obj.title or obj.id, st, actions),obj)
    elseif aim.hit and aim.breakable then
        HUD.SetTarget(aim.volume == Puzzles.gateRubble and "◇ 碎石堆 · 左键碎时" or "◇ 可破坏 · 左键碎时", true)
    else
        HUD.SetTarget("")
    end
    return aim
end

local function HandleSpells(dt, aim)
    if M.mounted then caster_.charging,caster_.charge=false,0; return end
    local testInput = M.fake ~= nil or M.fakePress ~= nil
    if M.debugOn or TouchControls.IsBlocked() or (not TouchInput.IsEnabled() and not pointer:IsEnabled() and not testInput) then
        caster_.charging,caster_.charge=false,0; return
    end
    local lmb = (not TouchInput.IsEnabled() and pointer:CanAttack() and input:GetMouseButtonDown(MOUSEB_LEFT)) or Down(KEY_1) or TouchInput.Down("shatter")
    -- A begin/end delivered together must still fire a zero-charge tap once.
    if TouchInput.Press("shatter") and not lmb then caster_:HandleCharge(true,aim,true) end
    caster_:HandleCharge(lmb,aim,true)
    -- 冻结 E、回溯 Q（不用鼠标右键）；数字键 2 / 3 保留给测试脚本
    if Press(KEY_E) or Press(KEY_2) then caster_:Cast("freeze", aim) end
    if Press(KEY_Q) or Press(KEY_3) then caster_:Cast("rewind", aim) end
end

function Ruins_HandleSceneUpdate(eventType, eventData)
    -- 角色意图在物理步进之前写入（见 voxel-physics.md 铁规 1）
    local dt = eventData["TimeStep"]:GetFloat()
    if nomi_ == nil or M.mounted or (M.ride ~= nil and M.ride.mode ~= "free") then return end
    if M.debugOn or TouchControls.IsBlocked() or (not TouchInput.IsEnabled() and not pointer:IsEnabled() and M.fake==nil) then
        nomi_:Move(dt,0,0,false,false,false); return
    end
    local f = (Down(KEY_W) and 1 or 0) - (Down(KEY_S) and 1 or 0)
    local r = (Down(KEY_D) and 1 or 0) - (Down(KEY_A) and 1 or 0)
    local tf,tr=TouchInput.MoveAxis()
    f,r=Clamp(f+tf,-1,1),Clamp(r+tr,-1,1)
    nomi_:Move(dt, f, r, Down(KEY_SHIFT), Press(KEY_SPACE), caster_.charging or caster_.castAnim > 0)
end

function Ruins_HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    time_ = time_ + dt
    TouchControls.Update(dt)
    if touchRevision~=TouchInput.revision then
        touchRevision=TouchInput.revision
        caster_.charging,caster_.charge=false,0
    end
    if not TouchInput.IsEnabled() then pointer:Update(input:GetMouseButtonDown(MOUSEB_LEFT)) end
    local tx,ty=TouchInput.ConsumeLook()
    if TouchInput.IsEnabled() and not M.debugOn and not TouchControls.IsBlocked() then nomi_:Look(tx*.14,ty*.12,1) end
    if Press(KEY_F10) then M.ToggleDebugPanel() end
    if Press(KEY_TAB) then farView = not farView end
    if not TouchInput.IsEnabled() and mouseLocked and pointer:CanLook(false) then
        local mm = input.mouseMove
        nomi_:Look(mm.x, mm.y, 0.12)
    end
    -- 龙
    local ctrl = M.ctrl
    M.ride.externalGround = nomi_.cc.onGround
    M.ride:Update(dt, nomi_.camYaw)
    UpdateDragonPose(dt)
    if M.ride.mode=="mounted" then
        M.ride:SeatPose(); M.ride:AttachToSaddle()
        M.ride.pos=nomi_.node.worldPosition
    end
    if M.mounted then
        local a=nomi_:Aim(100)
        M.breath.aimTarget=a.hit and a.pos or a.far
        if TouchInput.IsEnabled() then HUD.SetTarget("按住【龙息】持续吐息 · 朝准星方向喷射")
        else HUD.SetTarget("长按破坏键持续吐息（左键/1）") end
    else M.breath.aimTarget=nil end
    M.breath:Update()
    if not M.dragonAwake then
        ctrl.input.move, ctrl.input.turn = 0, 0
    else
        M.wakeT = (M.wakeT or 0) + dt
        M.sleepK = math.max(0, 1 - M.wakeT / 2.5)
        if M.wakeT > 2.0 and not M.roared then
            M.roared = true
            ctrl:Request("ROAR")
        end
        if M.wakeT > 6.5 and not M.spread then
            M.spread = true
            ctrl:Request("SPREAD_WINGS")
        end
        if M.wakeT > 10.0 and M.spread and not M.settled then
            M.settled = true
            ctrl:Request("IDLE")
            M.ride.aiOff = false
        end
    end
    ApplySleepPose(dt)
    M.dragonWorld:Update(dt)
    -- 谜题 / 法术
    local aim = (not M.mounted) and UpdateAim() or { hit = false, dir = Vector3.FORWARD, far = Vector3.ZERO }
    HandleSpells(dt, aim)
    caster_:Update(dt)
    -- 法阵、手光读取本帧骨骼；不再先画特效再更新手臂。
    if M.ride.mode == "free" then nomi_:Animate(dt, caster_.charging or caster_.castAnim > 0) end
    -- 法阵只更新一次，在 PostUpdate 中使用本帧最终相机与施法方向。
    Puzzles.Update(dt)
    Puzzles.CheckGate()
    Puzzles.UpdateKey(time_, nomi_:Position())
    -- 法阵点亮
    M.runeK = (M.runeK or 0) + ((M.runeTarget or 0) - (M.runeK or 0)) * (1 - math.exp(-1.2 * dt))
    local pulse = 0.5 + 0.5 * math.sin(time_ * 2.0)
    local q = math.floor((M.runeK * 40 + pulse * 4)) / 40
    if q ~= M.lastRuneQ then
        M.lastRuneQ = q
        Pal.SetFloorRune(world_, M.runeK, pulse)
    end
    -- 昼夜：按住 T 快进
    local dn = M.dayNight
    dn.fast = Down(KEY_T)
    dn:Update(dt)
    HUD.SetClock(dn:ClockText())
    -- 法阵灯：苏醒后常亮；夜里本来就有一点微光
    M.courtLight.brightness = 2.2 * M.runeK + 0.6 * (dn.nightK or 0)
    -- 草：诺米 / 龙脚下压开
    Terrain.SetInteractor(0, nomi_:Position(), 0.6)
    Terrain.SetInteractor(1, M.rig.root.worldPosition, (M.rig.size or 1) * 2.2)
    Build.UpdateFloaters(time_, 1.0)
    -- 特效 / 手光
    local glowCol = caster_.charging and Spells.GOLD or Spells.BLUE
    local glow = caster_.charging and (0.4 + 0.6 * caster_.charge) or (caster_.castAnim > 0 and 1.0 or 0.12)
    fx_:Update(dt, nomi_:HandPos(), glowCol, glow)
    -- HUD
    HUD.UpdateSlots(caster_.cool, caster_.charging and caster_.charge or 0,Spells.ShatterRadius(caster_.charge))
    if banner.t > 0 then
        banner.t = banner.t - dt
        if banner.t <= 0 then HUD.SetMessage(caster_.message) end
    else
        HUD.SetMessage(caster_.message)
    end
    if mouseLocked then
        local h = M.ride.hint
        if M.ride.locked or M.ride.mode == "free" and (h == nil or h:find("WASD")) then h = "" end
        HUD.SetHint(h)
    end
    TouchControls.Sync()
    HUD.SetCrossVisible(not M.debugOn)
    -- 低频现场日志：使用实际帧间隔，Web 上不依赖返回 0 的 os.clock()。
    perf.elapsed, perf.frames = perf.elapsed + dt, perf.frames + 1
    perf.peak = math.max(perf.peak, dt)
    if perf.elapsed >= 10 then
        local pieces = 0
        for _, object in ipairs(Puzzles.list) do pieces = pieces + #object.pieces end
        print(string.format("RuinsPerf: fps=%.1f peak=%.1fms volumes=%d pieces=%d particles=%d awake=%s",
            perf.frames / perf.elapsed, perf.peak * 1000, world_:GetVolumeCount(), pieces,
            fx_.motesB:Count() + fx_.motesG:Count(), tostring(M.dragonAwake)))
        perf.elapsed, perf.frames, perf.peak = 0.0, 0, 0.0
    end
end

function Ruins_HandlePostUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    if M.mounted or M.ride.mode ~= "free" then
        nomi_:UpdateCamera(dt, "mounted", M.rig.bones.chest)
    else
        local mode = farView and "far" or ((caster_.charging or caster_.castAnim > 0) and "aim" or "normal")
        if M.forceCamMode ~= nil then mode = M.forceCamMode end
        nomi_:UpdateCamera(dt, mode, nomi_.node)
    end
    local aim = M.aim or {hit=false,far=nomi_:HandPos()+nomi_.node.worldDirection*60}
    M.sigils:Update(dt,aim,nomi_:HandPos(),nomi_:CameraNode(),caster_,Spells.ShatterRadius(caster_.charge),not M.mounted and not M.debugOn)
    fx_.motesB:Draw(); fx_.motesG:Draw()
end

function M.Stop()
    TouchControls.Stop()
    HUD.Stop()
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("PostUpdate")
    UnsubscribeFromEvent("SceneUpdate")
    UnsubscribeFromEvent("MouseButtonDown")
    UnsubscribeFromEvent("MouseButtonUp")
    UnsubscribeFromEvent("MouseMove")
    UnsubscribeFromEvent("MouseModeChanged")
    UnsubscribeFromEvent("KeyDown")
    UnsubscribeFromEvent("InputFocus")
    pointer:Release("stop")
end

return M
