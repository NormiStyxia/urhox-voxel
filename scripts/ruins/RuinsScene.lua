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
local Nomi = require("ruins.NomiController")
local HUD = require("ruins.RuinsHUD")
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
local stage_ = "gate"
local mouseLocked = false
local farView = false
local isWeb = PlatformUtils.IsWebPlatform()
local resumeHint = "点击画面锁定鼠标 · Esc 释放"
local inputTakenOver = false
local pointer = PointerCapture.New({
    web = isWeb,
    now = function() return GetTime():GetElapsedTime() end,
    focused = function() return input.focus and not input.minimized end,
    captured = function()
        if isWeb then return input:IsMouseLocked() end
        return input.mouseMode == MM_RELATIVE
    end,
    request = function()
        input:SetMouseMode(MM_RELATIVE)
    end,
    release = function()
        input:SetMouseMode(MM_FREE)
        input:SetMouseGrabbed(false)
        input:SetMouseVisible(true)
    end,
    changed = function(locked, reason)
        mouseLocked = locked
        if not locked then input:SetMouseVisible(true) end
        if reason ~= "fallback" and not locked and caster_ ~= nil then
            caster_.charging, caster_.charge = false, 0
        end
        local hint = locked and "" or (M.debugOn and "F10 关闭调试面板后，点击画面继续" or resumeHint)
        if reason == "fallback" then hint = "浏览器未授予锁定 · 技能仍可使用 · 点击可重试锁定" end
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
M.START_HOUR = 16.2   -- 开局在下午偏晚，很快进入黄昏
local function SetupLighting()
    local lg = scene_:CreateChild("LightGroup")
    lg:LoadXML(cache:GetResource("XMLFile", "LightGroup/RuinsDay.xml"):GetRoot())
    local zone = lg:GetComponent("Zone")
    M.zone = zone
    local sunNode = lg:GetChild("Directional Light")
    M.sun = sunNode:GetComponent("Light")
    -- 太阳阴影：4 级 CSM，近处细（诺米、柱子、草的投影清楚），远到 260m 盖住整个盆地
    local sun = M.sun
    sun.castShadows = true
    sun.shadowCascade = CascadeParameters(10.0, 32.0, 90.0, 260.0, 0.85)
    sun.shadowBias = BiasParameters(0.00025, 0.6)
    sun.shadowIntensity = 0.0
    sun.shadowResolution = 1.0
    renderer.shadowMapSize = 2048
    -- 天空 + 昼夜（环境光由 SkyLightCapture 跟随天空，替代旧的渐变天空和补光）
    M.dayNight = DayNight.New({ scene = scene_, zone = zone, zoneNode = lg, sun = sun, sunNode = sunNode, hour = M.START_HOUR })
    -- 体素材质：静态建筑统一用带风化细节的 RuinsVoxel（每种体素尺寸一份）
    local vmats = {}
    Brush.materialFor = function(size)
        local m = vmats[size]
        if m ~= nil then return m end
        m = Material:new()
        if not m:SetSurfaceShader("Shaders/BLGL/RuinsVoxel.shader") then
            print("RuinsScene: RuinsVoxel.shader failed, using palette material")
            Brush.materialFor = nil
            return nil
        end
        m:SetSurfaceTexture("palette_tex", world_:GetPaletteTexture())
        m:SetShaderParameter("voxel_size", Variant(size))
        vmats[size] = m
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
    ride.onMount = function()
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
    -- 沉睡：趴伏 + 闭眼（动画控制器没有睡眠状态，用暂停在待机第一帧并降低身体）
    M.dragonAwake = false
    M.sleepK = 1.0
    print("RuinsScene: dragon ready (" .. M.variant .. ")")
end

-- 沉睡姿态：整体压低、头贴地；苏醒时 sleepK 1 → 0
local function ApplySleepPose(dt)
    local rig = M.rig
    if M.sleepK <= 0.001 then return end
    local k = Smooth(M.sleepK)
    local breathe = math.sin(time_ * 0.9) * 0.04
    rig.root.position = rig.root.position + Vector3(0, (-0.55 + breathe) * k * (rig.size or 1), 0)
    local function Bend(name, pitch)
        local b = rig.bones[name]
        if b ~= nil then b.rotation = b.rotation * Quaternion(pitch * k, Vector3.RIGHT) end
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

-- ---------------------------------------------------------------- 启动
function M.Start()
    -- 引擎的自动点击重锁没有 UI / pending 过滤；接管一次，避免两个管理者竞争。
    if not inputTakenOver then
        local uninstall = _G["InputExtensions_Uninstall"]
        if type(uninstall) == "function" then uninstall() end
        inputTakenOver = true
    end
    pointer:Release("start")
    local t0 = os.clock()
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
    fx_ = Spells.NewFX(scene_)
    caster_ = Spells.NewCaster({ world = world_, puzzles = Puzzles, scene = scene_, fx = fx_,
        handPos = function() return nomi_:HandPos() end })
    SetupDragon()

    HUD.Build(Spells.SPELLS)
    SetStage("gate")
    HUD.SetHint(resumeHint .. "  ·  H 隐藏说明")
    if M.DEBUG_PANEL then M.ToggleDebugPanel() end

    SubscribeToEvent("Update", "Ruins_HandleUpdate")
    SubscribeToEvent("PostUpdate", "Ruins_HandlePostUpdate")
    SubscribeToEvent("SceneUpdate", "Ruins_HandleSceneUpdate")
    SubscribeToEvent("MouseButtonDown", "Ruins_HandleMouseDown")
    SubscribeToEvent("MouseModeChanged", "Ruins_HandleMouseModeChanged")
    SubscribeToEvent("KeyDown", "Ruins_HandleKeyDown")
    SubscribeToEvent("InputFocus", "Ruins_HandleInputFocus")
    RUINS = M
    M.scene, M.world, M.puzzles, M.nomiCtl, M.caster, M.fx = scene_, world_, Puzzles, nomi_, caster_, fx_
    print(string.format("RuinsScene: ready in %.2fs, volumes %d", os.clock() - t0, world_:GetVolumeCount()))
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
-- 只在一次有效的左键事件中请求；模式通知不再反向设置鼠标模式。
---@param eventType string
---@param eventData MouseButtonDownEventData
function Ruins_HandleMouseDown(eventType, eventData)
    if eventData:GetInt("Button") ~= MOUSEB_LEFT then return end
    pointer:Click(HUD.IsPointerOverUI())
end

---@param eventType string
---@param eventData MouseModeChangedEventData
function Ruins_HandleMouseModeChanged(eventType, eventData)
    pointer:ModeChanged(eventData:GetInt("Mode") == MM_RELATIVE, eventData:GetBool("MouseLocked"))
end

---@param eventType string
---@param eventData KeyDownEventData
function Ruins_HandleKeyDown(eventType, eventData)
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
    if not eventData:GetBool("Focus") or eventData:GetBool("Minimized") then pointer:Release("focus") end
end

-- M.fake / M.fakePress：自动化测试注入按键（正常游戏为 nil）
local function Down(k)
    if M.fake ~= nil and M.fake[k] ~= nil then return M.fake[k] end
    return input:GetKeyDown(k)
end
local function Press(k)
    if M.fakePress ~= nil and M.fakePress[k] then M.fakePress[k] = nil return true end
    return input:GetKeyPress(k)
end

-- 当前瞄准目标（时之物件）
local function UpdateAim()
    local aim = nomi_:Aim(60.0)
    if aim.hit then aim.object = Puzzles.FindByVolume(aim.volume) end
    M.aim = aim
    local obj = aim.object
    if obj ~= nil then
        obj.hoverTarget = 1
        local st = ({ WHOLE = "完整", SHATTERED = "破碎中", FROZEN = "已碎", REWIND = "回溯中" })[obj.state] or ""
        if obj.state == "FROZEN" and not obj.rubble then st = "冻结" end
        HUD.SetTarget(string.format("◆ %s · %s", obj.title or obj.id, st))
    elseif aim.hit and aim.volume ~= nil and aim.volume.destructible and aim.volume ~= Puzzles.gateRubble then
        HUD.SetTarget("")
    elseif aim.hit and aim.volume == Puzzles.gateRubble then
        HUD.SetTarget("◇ 碎石堆（可碎时）")
    else
        HUD.SetTarget("")
    end
    return aim
end

local function HandleSpells(dt, aim)
    if M.mounted then return end
    local testInput = M.fake ~= nil or M.fakePress ~= nil
    if M.debugOn or (not pointer:IsEnabled() and not testInput) then return end
    local lmb = (pointer:CanAttack() and input:GetMouseButtonDown(MOUSEB_LEFT)) or Down(KEY_1)
    if pointer:CanAttack() or Down(KEY_1) then
        -- 碎时：按下开始蓄力，松开施放
        if lmb then
            if not caster_.charging and caster_:Ready("shatter") then caster_.charging = true; caster_.charge = 0 end
        elseif caster_.charging then
            caster_:Cast("shatter", aim)
            caster_.charging = false
            caster_.charge = 0
        end
    end
    -- 冻结 E、回溯 Q（不用鼠标右键）；数字键 2 / 3 保留给测试脚本
    if Press(KEY_E) or Press(KEY_2) then caster_:Cast("freeze", aim) end
    if Press(KEY_Q) or Press(KEY_3) then caster_:Cast("rewind", aim) end
end

function Ruins_HandleSceneUpdate(eventType, eventData)
    -- 角色意图在物理步进之前写入（见 voxel-physics.md 铁规 1）
    local dt = eventData["TimeStep"]:GetFloat()
    if nomi_ == nil or M.mounted or (M.ride ~= nil and M.ride.mode ~= "free") then return end
    local f = (Down(KEY_W) and 1 or 0) - (Down(KEY_S) and 1 or 0)
    local r = (Down(KEY_D) and 1 or 0) - (Down(KEY_A) and 1 or 0)
    nomi_:Move(dt, f, r, Down(KEY_SHIFT), Press(KEY_SPACE), caster_.charging or caster_.castAnim > 0)
end

function Ruins_HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    time_ = time_ + dt
    pointer:Update(input:GetMouseButtonDown(MOUSEB_LEFT))
    if Press(KEY_F10) then M.ToggleDebugPanel() end
    if Press(KEY_TAB) then farView = not farView end
    if pointer:CanLook() then
        local mm = input.mouseMove
        if isWeb and not mouseLocked then
            local pos = input.mousePosition
            local w, h = graphics:GetWidth(), graphics:GetHeight()
            if pos.x >= 0 and pos.y >= 0 and pos.x < w and pos.y < h and not HUD.IsPointerOverUI() then
                local edge = math.min(w, h) * 0.08
                local xEdge = Clamp((pos.x - (w - edge)) / edge, 0, 1) - Clamp((edge - pos.x) / edge, 0, 1)
                local yEdge = Clamp((pos.y - (h - edge)) / edge, 0, 1) - Clamp((edge - pos.y) / edge, 0, 1)
                nomi_:Look(Clamp(mm.x, -120, 120) + xEdge * 600 * dt, Clamp(mm.y, -120, 120) + yEdge * 360 * dt, 0.12)
            end
        else
            nomi_:Look(mm.x, mm.y, 0.12)
        end
    end
    -- 龙
    local ctrl = M.ctrl
    M.ride.externalGround = nomi_.cc.onGround
    M.ride:Update(dt, nomi_.camYaw)
    ctrl:Update(dt)
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
    -- 谜题 / 法术
    local aim = (not M.mounted) and UpdateAim() or { hit = false, dir = Vector3.FORWARD, far = Vector3.ZERO }
    HandleSpells(dt, aim)
    caster_:Update(dt)
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
    -- 动画
    if M.ride.mode == "free" then nomi_:Animate(dt, caster_.charging or caster_.castAnim > 0) end
    -- HUD
    HUD.UpdateSlots(caster_.cool, caster_.charging and caster_.charge or 0)
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
    HUD.SetCrossVisible(not M.mounted)
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
end

function M.Stop()
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("PostUpdate")
    UnsubscribeFromEvent("SceneUpdate")
    UnsubscribeFromEvent("MouseButtonDown")
    UnsubscribeFromEvent("MouseModeChanged")
    UnsubscribeFromEvent("KeyDown")
    UnsubscribeFromEvent("InputFocus")
    pointer:Release("stop")
end

return M
