-- ====================================================================
-- DragonTest.lua — 体素巨龙独立测试场景（入口：dragon_main.lua）。
--
-- 场景：简洁雪地（2m 棋盘格，便于观察是否滑步）+ 白天光组；默认只生成一条龙。
-- 相机：右键 / 左键拖动旋转，滚轮缩放，中键或 Shift+左键拖动平移，
--       1/2/3/4 = 正 / 侧 / 背 / 3/4 视角，F = 跟随龙。
-- 键盘：见 DragonDebugUI 面板底部。
-- ====================================================================

local SkyUtils = require("urhox-libs.Rendering.SkyUtils")
local PlatformUtils = require("urhox-libs.Platform.PlatformUtils")
local Rig = require("dragon.DragonRig")
local Controller = require("dragon.DragonAnimationController")
local DebugUI = require("dragon.DragonDebugUI")
local UI = require("urhox-libs/UI")
local TouchInput = require("ui.TouchInput")
local TouchControls = require("ui.TouchControls")
local TouchHUD = require("ruins.RuinsHUD")
local BlockCharacter = require("game.BlockCharacter")
local NomiVoxelData = require("game.NomiVoxelData")
local DragonRide = require("dragon.DragonRide")
local Variants = require("dragon.DragonVariants")
local Breath = require("dragon.DragonBreath")
local BreathClassic = require("dragon.DragonBreathClassic")
local Stream = require("dragon.DragonStream")
Breath.Register(Controller)

local M = {}

---@type Scene
local scene_ = nil
---@type Node
local camNode_ = nil
---@type Camera
local camera_ = nil
---@type DragonRig
local rig_ = nil
---@type DragonAnimationController
local ctrl_ = nil
---@type VoxelPhysicsWorld
local world_ = nil
---@type DragonRide
local ride_ = nil
---@type DragonBreath|DragonBreathClassic
local breath_ = nil

local cam = { yaw = -128.0, pitch = 12.0, dist = 17.0, target = Vector3(0, 2.4, -0.6), follow = true, pan = Vector3(0, 0, 0) }
M.cam = cam
M.showSkeleton = false
M.showHitZones = false
M.showStrips = false
M.showFeet = false
M.showNomi = true
M.playMode = true -- 玩法模式：操作诺米，靠近龙按 F 骑乘；关掉则回到纯动画调试
-- 诺米体素小人（诺米的体素模型，约 1.7m，用来对比龙的体型）
local NOMI_POS = Vector3(-2.6, 0, -3.4)
local NOMI_YAW = -150.0
M.externalDrive = false -- 自动化验证时由测试脚本以固定步长驱动控制器
M.variant = "medium"    -- 当前型号：small / medium / large（调试面板切换）

-- 自动截图 / 回归测试配置（可选模块，测试时临时生成，不随项目发布）
---@type table|nil
local shotCfg = nil

local GROUND_A, GROUND_B = 60, 61

local function BuildGround(world)
    world:SetPaletteEntry(GROUND_A, Color(0.86, 0.88, 0.92), 50.0)
    world:SetPaletteEntry(GROUND_B, Color(0.78, 0.81, 0.87), 50.0)
    local n, s = 140, 1.0
    local g = world:CreateVolume(n, 1, n, s, Vector3(-n * s * 0.5, -s, -n * s * 0.5))
    local grid = g:GetGrid()
    grid:FillBox(0, 0, 0, n - 1, 0, n - 1, true)
    for i = 0, n - 1 do
        for k = 0, n - 1 do
            -- 2m 一格的棋盘，方便看出脚是否打滑
            local c = ((i // 2 + k // 2) % 2 == 0) and GROUND_A or GROUND_B
            grid:SetVoxelMaterial(i, 0, k, c)
        end
    end
    g.destructible = false
    world:FinalizeVolume(g)
    g:RebuildGeometry()
    -- 龙息在地面上结霜 / 灼烧时直接改这一层的体素颜色
    M.groundInfo = { volume = g, origin = Vector3(-n * s * 0.5, -s, -n * s * 0.5), cell = s }
    return g
end

function M.SetPlayMode(on)
    if on == M.playMode then return end
    M.playMode = on
    ctrl_.input.move, ctrl_.input.turn, ctrl_.input.climb, ctrl_.input.sprint = 0, 0, 0, false
    if not on then
        if ride_ ~= nil then ride_:Release() end
        DebugUI.SetHint("")
        ctrl_.input.free = false
    else
        ctrl_.input.free = false
        M.nomiNode:SetDeepEnabled(true)
        M.showNomi = true
    end
end

-- 泛光阈值：光组 XML 里 UE 模式的阈值是 -1（所有亮度都参与泛光），桌面端高光
-- 被 LUT 压住没问题；移动端 / Web 只能走 ACES，吐息时的高亮点光与加法粒子会被
-- 泛光扩散成整屏白。这里给低配平台设一个阈值，只让真正亮的部分发光。
function M.SetupBloom(zone)
    if zone == nil then return end
    local lowFx = PlatformUtils.IsWebPlatform() or PlatformUtils.IsMobilePlatform()
    if not lowFx then return end
    zone.bloomMode = BLOOM_MODE_UE
    zone.bloomUEThreshold = 1.2
    zone.bloomUEIntensity = 0.45
    print("[DragonTest] bloom tuned for mobile/web (threshold 1.2)")
end

function M.ApplyCamera()
    -- 近似正交（比对三视图用）：超长焦，视野高度 = cam.ortho 米
    if cam.ortho ~= nil then
        if M.zone ~= nil and not M.fogOff then
            M.fogOff = true
            M.zone:SetFogStart(2000.0)
            M.zone:SetFogEnd(3000.0)
            M.zone:SetHeightFogEnable(false)
            M.zone:SetVolumetricFogEnabled(false)
        end
        cam.dist = 400.0
        world_:SetMeshLodDistance(0.0)
        camera_.farClip = 1000.0
        camera_.fov = math.deg(2.0 * math.atan(cam.ortho * 0.5 / cam.dist))
    end
    local rot = Quaternion(cam.pitch, cam.yaw, 0.0)
    local rush = cam.ortho == nil and (cam.flightVisual or 0) or 0
    if cam.ortho == nil then camera_.fov = 45 + 5 * rush end
    local shake = (breath_ ~= nil and cam.ortho == nil) and breath_.shake or 0
    local jitter = Vector3.ZERO
    if shake > 0.001 then
        local t = time:GetElapsedTime()
        local k = shake * (0.6 + 0.4 * (rig_.size or 1.0)) * 0.55
        jitter = Vector3(math.sin(t * 53.0) + 0.5 * math.sin(t * 97.0), math.sin(t * 61.0 + 1.3) + 0.4 * math.sin(t * 113.0), 0) * k
        rot = rot * Quaternion(shake * 1.6 * math.sin(t * 71.0), Vector3.FORWARD)
    end
    camNode_.position = cam.target - rot * Vector3(0, 0, cam.dist + 1.5 * rush) + rot * jitter
    camNode_.rotation = rot
end

-- 视角预设（相对龙的朝向）
function M.SetView(which)
    local base = (ctrl_ ~= nil) and ctrl_.loco.yaw or 0.0
    if which == "front" then cam.yaw, cam.pitch = base + 180.0, 6.0
    elseif which == "side" then cam.yaw, cam.pitch = base - 90.0, 4.0
    elseif which == "back" then cam.yaw, cam.pitch = base, 8.0
    else cam.yaw, cam.pitch = base - 128.0, 12.0 end
end

-- 龙息两套特效：pixel = 体素像素版（DragonBreath），classic = 柔光经典版（DragonBreathClassic）
M.breathStyle = "pixel"

function M.NewBreath(id)
    if M.breathStyle == "classic" then return BreathClassic.New(scene_, rig_, ctrl_, id) end
    return Breath.New(scene_, rig_, ctrl_, id, M.groundInfo)
end

-- The standalone scene has no RuinsDragon host, so owns its ordinary stream here.
local ordinarySource
local streamMode
local function DestroyStream()
    if M.stream then M.stream:Destroy(); M.stream=nil end
    if ordinarySource then ordinarySource:Destroy(); ordinarySource=nil end
end
local function CreateStream()
    local source=breath_ --[[@as DragonBreath]]
    if M.breathStyle=="classic" then
        ordinarySource=Breath.New(scene_,rig_,ctrl_,M.variant,M.groundInfo)
        source=ordinarySource
    end
    if source:Available() then M.stream=Stream.New(scene_,source) end
    ctrl_.breathCfg=breath_.cfg -- Preserve the selected special-breath style.
    streamMode=nil
end

-- 切换龙息特效版本（吐息中途切换会直接中断当前这一口）
function M.ToggleBreathStyle()
    M.breathStyle = (M.breathStyle == "pixel") and "classic" or "pixel"
    DestroyStream()
    if breath_ ~= nil then breath_:Destroy() end
    if ctrl_.state == "BREATH" then ctrl_:Request("IDLE") end
    breath_ = M.NewBreath(M.variant)
    M.breath = breath_
    CreateStream()
    print("DragonTest: breath style -> " .. M.breathStyle)
    if shotCfg == nil or not shotCfg.noUI then DebugUI.Build(ctrl_, M) end
end

function M.Start()
    TouchInput.Detect()
    local ok, cfg = pcall(require, "dragon._shotcfg")
    if ok then shotCfg = cfg end

    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")
    world_ = scene_:CreateComponent("VoxelPhysicsWorld")

    local lg = scene_:CreateChild("LightGroup")
    lg:LoadXML(cache:GetResource("XMLFile", "LightGroup/TownDay.xml"):GetRoot())
    M.zone = lg:GetComponent("Zone")
    -- 展示用补光：抬高环境光、加一盏不投影的正面补光，让白色腹甲 / 翼膜不被压成灰色
    if M.zone ~= nil then M.zone:SetAmbientColor(Color(0.30, 0.34, 0.42)) end
    M.SetupBloom(M.zone)
    local fillNode = scene_:CreateChild("FillLight")
    fillNode.direction = Vector3(0.45, -0.55, -0.7)
    local fill = fillNode:CreateComponent("Light")
    fill.lightType = LIGHT_DIRECTIONAL
    fill.brightness = 0.55
    fill.color = Color(0.86, 0.92, 1.0)
    fill.castShadows = false
    SkyUtils.CreateGradientSky(scene_, { zenith = Color(0.10, 0.28, 0.66), horizon = Color(0.447, 0.638, 1.0), skyExp = 0.5 })

    BuildGround(world_)
    rig_ = Rig.Build(scene_, world_, nil, Variants.Get(M.variant))
    M.rig = rig_
    ctrl_ = Controller.New(rig_, world_)
    M.ctrl = ctrl_
    breath_ = M.NewBreath(M.variant)
    M.breath = breath_
    CreateStream()
    -- 诺米：站在龙的右前方，面朝默认机位，只播待机动画
    M.nomiNode = scene_:CreateChild("Nomi")
    M.nomiNode.position = NOMI_POS
    M.nomiNode.rotation = Quaternion(NOMI_YAW, Vector3.UP)
    M.nomi = BlockCharacter.CreateVoxel(M.nomiNode, NomiVoxelData, BlockCharacter.SLENDER)
    ride_ = DragonRide.New(M)
    M.ride = ride_

    -- 面朝太阳出生（光组的太阳在 -Z 方向），默认机位在受光的斜前方
    ctrl_:Teleport(Vector3(0, 0, 0), 180.0)
    cam.yaw = 180.0 - 145.0
    cam.target = Vector3(0, 2.4, 0.6)
    if M.playMode then
        -- 玩法模式：镜头在诺米身后看向龙
        local d = ride_.pos
        cam.yaw = math.deg(math.atan(-d.x, -d.z))
        cam.pitch = 16.0
        cam.dist = 9.0
        cam.target = d + Vector3(0, 1.1, 0)
    end

    camNode_ = scene_:CreateChild("Camera")
    camera_ = camNode_:CreateComponent("Camera")
    camera_.farClip = 400.0
    camera_.fov = 45.0
    renderer:SetViewport(0, Viewport:new(scene_, camera_))

    if shotCfg == nil or not shotCfg.noUI then DebugUI.Build(ctrl_, M) end
    if shotCfg ~= nil and shotCfg.setup ~= nil then shotCfg.setup(M) end
    TouchControls.Attach(UI.GetRoot(),function()
        return {mounted=ride_.mode~="free",mounting=ride_.mode=="mounting",airborne=ctrl_.loco.airborne,
            gliding=ctrl_.state=="GLIDE",breathActive=M.stream and M.stream.active,canMount=ride_.rideable and ride_.onGround and ride_:NearDragon()<3.6,
            blocked=not M.playMode,noSpells=true}
    end,function(on)
        if on then
            TouchHUD.Build({})
            TouchHUD.SetObjective("骑乘巨龙", "靠近龙，点【上龙】")
            TouchHUD.SetCrossVisible(true)
        else DebugUI.Build(ctrl_,M) end
        -- Reparent the existing display layer after the mode swaps UI roots.
        M.touchNeedsAttach=true
    end,function()
        if M.stream then M.stream:Stop(true) end
    end)
    ride_.controlsEnabled=function() return not TouchControls.IsBlocked() end
    M.ApplyCamera()

    SubscribeToEvent("Update", "DragonTest_HandleUpdate")
    SubscribeToEvent("PostRenderUpdate", "DragonTest_HandlePostRender")
    DRAGON_TEST = M -- 供自动化验证脚本访问
    print("DragonTest: ready")
end

function M.Stop()
    TouchControls.Stop()
    DestroyStream()
    TouchHUD.Stop()
end

-- 切换型号：拆掉当前的龙，在原地按新型号重建（诺米、镜头、显示开关保留）
function M.SetVariant(id)
    if id == M.variant or ctrl_ == nil then return end
    local t0 = os.clock()
    local L = ctrl_.loco
    local pos, yaw = Vector3(L.pos.x, 0, L.pos.z), L.yaw
    if ride_ ~= nil then ride_:Release() end
    local oldSize = rig_.size or 1.0
    local oldId = M.variant
    DestroyStream()
    if breath_ ~= nil then breath_:Destroy() end
    rig_:Destroy()
    local ok, built = pcall(function() return Rig.Build(scene_, world_, nil, Variants.Get(id)) end)
    if not ok then
        print("DragonTest: variant " .. id .. " failed: " .. tostring(built))
        id = oldId
        built = Rig.Build(scene_, world_, nil, Variants.Get(id))
    end
    M.variant = id
    rig_ = built
    M.rig = rig_
    ctrl_ = Controller.New(rig_, world_)
    M.ctrl = ctrl_
    ctrl_:Teleport(pos, yaw)
    breath_ = M.NewBreath(id)
    M.breath = breath_
    CreateStream()
    ride_:BindDragon(M)
    -- 镜头距离随体型缩放
    local k = (rig_.size or 1.0) / oldSize
    cam.dist = math.max(4.0, math.min(80.0, cam.dist * (0.4 + 0.6 * k)))
    if shotCfg == nil or not shotCfg.noUI then DebugUI.Build(ctrl_, M) end
    print(string.format("DragonTest: variant -> %s (%.2fs)", id, os.clock() - t0))
end

-- 面板按钮只登记请求：等提示显示出来（两帧）后再在 Update 里重建，避免在 UI 回调里替换 UI 树
function M.RequestVariant(id)
    M.pendingVariant, M.pendingFrames = id, 2
end

-- ---------------------------------------------------------------- 输入
local function KeyAxis(pos, neg)
    local v = 0
    if input:GetKeyDown(pos) then v = v + 1 end
    if input:GetKeyDown(neg) then v = v - 1 end
    return v
end

local function HandleKeys()
    local c = ctrl_
    if c.jointTest.enabled then return end
    if M.playMode then
        -- 玩法模式下键盘归诺米 / 骑乘（见 DragonRide）；只保留暂停 / 单步
        if input:GetKeyPress(KEY_P) then c.paused = not c.paused end
        -- 骑乘时 B 由 DragonRide 处理；步行时也能让龙吐息
        if input:GetKeyPress(KEY_B) and ride_ ~= nil and ride_.mode == "free" then breath_:Trigger() end
        return
    end
    c.input.move = KeyAxis(KEY_W, KEY_S)
    c.input.turn = KeyAxis(KEY_D, KEY_A)
    c.input.climb = KeyAxis(KEY_SPACE, KEY_C)
    c.input.sprint = c.loco.airborne and input:GetKeyDown(KEY_SHIFT) and c.input.move >= 0
    if (c.input.move > 0 or c.input.turn ~= 0) and (c.state == "IDLE") then c.demo = nil; c:Request("WALK") end
    if input:GetKeyPress(KEY_Q) then c.demo = nil; c:Request("TURN", -90) end
    if input:GetKeyPress(KEY_E) then c.demo = nil; c:Request("TURN", 90) end
    if input:GetKeyPress(KEY_SPACE) and not c.loco.airborne then c.demo = nil; c:Request("FLY") end
    if input:GetKeyPress(KEY_G) then c.demo = nil; c:Request("GLIDE") end
    if input:GetKeyPress(KEY_L) then c.demo = nil; c:Request("LAND") end
    if input:GetKeyPress(KEY_R) and not c.loco.airborne then c.demo = nil; c:Request("ROAR") end
    if input:GetKeyPress(KEY_B) then breath_:Trigger() end
    if input:GetKeyPress(KEY_V) then M.pendingBreathToggle = true end
    if input:GetKeyPress(KEY_T) and not c.loco.airborne then
        c.demo = nil
        c:Request(c.state == "SPREAD_WINGS" and "IDLE" or "SPREAD_WINGS")
    end
    if input:GetKeyPress(KEY_X) and c.state == "WALK" then c:Request("IDLE") end
    if input:GetKeyPress(KEY_P) then c.paused = not c.paused end
    if input:GetKeyPress(KEY_N) then c.paused = true; c.stepFrames = c.stepFrames + 1 end
    if input:GetKeyPress(KEY_1) then M.SetView("front") end
    if input:GetKeyPress(KEY_2) then M.SetView("side") end
    if input:GetKeyPress(KEY_3) then M.SetView("back") end
    if input:GetKeyPress(KEY_4) then M.SetView("34") end
    if input:GetKeyPress(KEY_F) then cam.follow = not cam.follow end
end

local function HandleMouse()
    if TouchInput.IsEnabled() then
        local dx,dy=TouchInput.ConsumeLook()
        if not TouchControls.IsBlocked() then
            cam.yaw=cam.yaw+dx*.14
            cam.pitch=math.max(-30,math.min(85,cam.pitch+dy*.12))
        end
        return
    end
    if cam.ortho ~= nil then return end
    local overUI = DebugUI.IsPointerOverUI()
    local mm = input.mouseMove
    local shift = input:GetKeyDown(KEY_SHIFT)
    local lmb, rmb, mmb = input:GetMouseButtonDown(MOUSEB_LEFT), input:GetMouseButtonDown(MOUSEB_RIGHT),
        input:GetMouseButtonDown(MOUSEB_MIDDLE)
    if M.dragging == nil and (lmb or rmb or mmb) and not overUI then M.dragging = true end
    if not (lmb or rmb or mmb) then M.dragging = nil end
    if M.dragging then
        if mmb or (lmb and shift) then
            local rot = Quaternion(cam.pitch, cam.yaw, 0.0)
            local k = cam.dist * 0.0018
            cam.pan = cam.pan + rot * Vector3(-mm.x * k, mm.y * k, 0)
            if not cam.follow then cam.target = cam.target + rot * Vector3(-mm.x * k, mm.y * k, 0) end
        else
            cam.yaw = cam.yaw + mm.x * 0.25
            cam.pitch = math.max(-30, math.min(85, cam.pitch + mm.y * 0.2))
        end
    end
    local wheel = input.mouseMoveWheel
    if wheel ~= 0 and not overUI then
        cam.dist = math.max(4.0, math.min(80.0, cam.dist * (1.0 - wheel * 0.1)))
    end
end

function M.Update(dt)
    TouchControls.Update(dt)
    if M.touchNeedsAttach then
        M.touchNeedsAttach=false
        TouchControls.Reattach(UI.GetRoot())
    end
    if TouchInput.IsEnabled() then
        TouchHUD.SetHint(ride_.hint)
        if TouchInput.Press("farview") then cam.dist=cam.dist<18 and 26 or 9 end
    end
    -- 面板按钮 / V 键只登记，换特效（会重建面板）放到 Update 里做
    if M.pendingBreathToggle then
        M.pendingBreathToggle = false
        M.ToggleBreathStyle()
    end
    if M.pendingVariant ~= nil then
        M.pendingFrames = M.pendingFrames - 1
        DebugUI.SetHint("正在生成 " .. Variants.Name(M.pendingVariant) .. " …")
        if M.pendingFrames <= 0 then
            local id = M.pendingVariant
            M.pendingVariant = nil
            M.SetVariant(id)
        end
        return
    end
    if shotCfg ~= nil and shotCfg.update ~= nil then shotCfg.update(M, dt) end
    if shotCfg == nil or not shotCfg.noInput then HandleKeys() end
    HandleMouse()
    -- 龙息卡帧：命中瞬间动画几乎停住一小下
    local animDt = (breath_.hitstop > 0) and dt * 0.08 or dt
    if not M.externalDrive then ctrl_:Update(animDt) end
    breath_:Update()
    if M.playMode and not M.externalDrive then
        ride_:Update(dt, cam.yaw)
        DebugUI.SetHint(ride_.hint)
        local want = ride_:CameraTarget()
        if ride_.mode == "mounted" and cam.ortho == nil then
            -- World-space lag follows travel, so mouse orbit and zoom stay intact.
            local L = ctrl_.loco
            local a = math.rad(L.travelYaw or L.yaw)
            want = want - Vector3(math.sin(a), 0, math.cos(a)) * (L.cameraPull or 0)
        end
        if cam.follow then cam.target = cam.target:Lerp(want + cam.pan, 1.0 - math.exp(-10.0 * dt)) end
    else
        if M.nomi ~= nil then
            if M.nomiNode.enabled ~= M.showNomi then M.nomiNode:SetDeepEnabled(M.showNomi) end
            if M.showNomi then M.nomi:Update(dt, { moveSpeed = 0, onGround = true }) end
        end
        if cam.follow and cam.ortho == nil then
            local p = rig_.body.worldPosition + Vector3(0, 0.4 * (rig_.size or 1.0), 0)
            cam.target = cam.target:Lerp(p + cam.pan, 1.0 - math.exp(-4.0 * dt))
        end
    end
    TouchControls.Sync()
    if M.stream then
        if streamMode~=ride_.mode then streamMode=ride_.mode; M.stream:Stop(true) end
        local allowed=M.playMode and ride_.mode=="mounted" and ctrl_.state~="BREATH"
            and input.focus and not input.minimized and not TouchControls.IsBlocked()
        local target=camNode_.worldPosition+camNode_.worldDirection*100
        M.stream:Update(dt,TouchInput.Down("breath"),target,allowed)
        if ordinarySource then ordinarySource:UpdateRings(dt) end
    end
    local rush = M.playMode and ride_.mode == "mounted" and (ctrl_.loco.stream or 0) or 0
    cam.flightVisual = (cam.flightVisual or 0) + (rush - (cam.flightVisual or 0)) * (1 - math.exp(-3 * dt))
    M.ApplyCamera()
    M.fpsAcc, M.fpsN = (M.fpsAcc or 0) + dt, (M.fpsN or 0) + 1
    if M.fpsAcc >= 0.5 then
        M.fps = M.fpsN / M.fpsAcc
        M.fpsAcc, M.fpsN = 0, 0
    end
    DebugUI.Update(ctrl_, M.fps)
end

function DragonTest_HandleUpdate(eventType, eventData)
    M.Update(eventData["TimeStep"]:GetFloat())
end

local COL_FOOT = Color(1, 0.4, 0.9)
local COL_FOOT_SW = Color(0.3, 1, 1)
local COL_AXIS = { Color(1, 0.2, 0.2), Color(0.2, 1, 0.2), Color(0.3, 0.5, 1) }

function DragonTest_HandlePostRender(eventType, eventData)
    local dbg = scene_:GetComponent("DebugRenderer")
    if M.showSkeleton or M.showStrips then rig_:DrawSkeleton(dbg, M.showStrips) end
    if M.showHitZones then rig_:DrawHitZones(dbg) end
    if M.showFeet then
        for _, f in ipairs(ctrl_.gait.feet) do
            if f.pos ~= nil then
                dbg:AddCross(f.pos, 0.25, f.swing and COL_FOOT_SW or COL_FOOT, false)
                dbg:AddCircle(f.planted, Vector3.UP, 0.18, COL_FOOT, 12, false)
            end
        end
    end
    local jt = ctrl_.jointTest
    if jt.enabled then
        local n = rig_.bones[jt.joint]
        if n ~= nil then
            local o = n.worldPosition
            local r = n.worldRotation
            dbg:AddLine(o, o + r * Vector3(0.6, 0, 0), COL_AXIS[1], false)
            dbg:AddLine(o, o + r * Vector3(0, 0.6, 0), COL_AXIS[2], false)
            dbg:AddLine(o, o + r * Vector3(0, 0, 0.6), COL_AXIS[3], false)
        end
    end
end

return M
