-- ====================================================================
-- DragonTest.lua — 体素巨龙独立测试场景（入口：dragon_main.lua 或 config.START_SCENE）。
--
-- 场景：简洁雪地（2m 棋盘格，便于观察是否滑步）+ 白天光组；默认只生成一条龙。
-- 相机：右键 / 左键拖动旋转，滚轮缩放，中键或 Shift+左键拖动平移，
--       1/2/3/4 = 正 / 侧 / 背 / 3/4 视角，F = 跟随龙。
-- 键盘：见 DragonDebugUI 面板底部。
-- ====================================================================

local SkyUtils = require("urhox-libs.Rendering.SkyUtils")
local Rig = require("dragon.DragonRig")
local Controller = require("dragon.DragonAnimationController")
local DebugUI = require("dragon.DragonDebugUI")
local BlockCharacter = require("game.BlockCharacter")
local NomiVoxelData = require("game.NomiVoxelData")
local DragonRide = require("dragon.DragonRide")

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

local cam = { yaw = -128.0, pitch = 12.0, dist = 17.0, target = Vector3(0, 2.4, -0.6), follow = true, pan = Vector3(0, 0, 0) }
M.cam = cam
M.showSkeleton = false
M.showHitZones = false
M.showStrips = false
M.showFeet = false
M.showNomi = true
M.playMode = true -- 玩法模式：操作诺米，靠近龙按 F 骑乘；关掉则回到纯动画调试
-- 诺米体素小人（复用 VoxelTown 玩家角色的体素模型，约 1.7m，用来对比龙的体型）
local NOMI_POS = Vector3(-2.6, 0, -3.4)
local NOMI_YAW = -150.0
M.externalDrive = false -- 自动化验证时由测试脚本以固定步长驱动控制器

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
    return g
end

function M.SetPlayMode(on)
    if on == M.playMode then return end
    M.playMode = on
    ctrl_.input.move, ctrl_.input.turn, ctrl_.input.climb = 0, 0, 0
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
    camNode_.position = cam.target - rot * Vector3(0, 0, cam.dist)
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

function M.Start()
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
    local fillNode = scene_:CreateChild("FillLight")
    fillNode.direction = Vector3(0.45, -0.55, -0.7)
    local fill = fillNode:CreateComponent("Light")
    fill.lightType = LIGHT_DIRECTIONAL
    fill.brightness = 0.55
    fill.color = Color(0.86, 0.92, 1.0)
    fill.castShadows = false
    SkyUtils.CreateGradientSky(scene_, { zenith = Color(0.10, 0.28, 0.66), horizon = Color(0.447, 0.638, 1.0), skyExp = 0.5 })

    BuildGround(world_)
    rig_ = Rig.Build(scene_, world_)
    M.rig = rig_
    ctrl_ = Controller.New(rig_, world_)
    M.ctrl = ctrl_
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
    M.ApplyCamera()

    SubscribeToEvent("Update", "DragonTest_HandleUpdate")
    SubscribeToEvent("PostRenderUpdate", "DragonTest_HandlePostRender")
    DRAGON_TEST = M -- 供自动化验证脚本访问
    print("DragonTest: ready")
end

function M.Stop()
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
        return
    end
    c.input.move = KeyAxis(KEY_W, KEY_S)
    c.input.turn = KeyAxis(KEY_D, KEY_A)
    c.input.climb = KeyAxis(KEY_SPACE, KEY_C)
    if (c.input.move > 0 or c.input.turn ~= 0) and (c.state == "IDLE") then c.demo = nil; c:Request("WALK") end
    if input:GetKeyPress(KEY_Q) then c.demo = nil; c:Request("TURN", -90) end
    if input:GetKeyPress(KEY_E) then c.demo = nil; c:Request("TURN", 90) end
    if input:GetKeyPress(KEY_SPACE) and not c.loco.airborne then c.demo = nil; c:Request("FLY") end
    if input:GetKeyPress(KEY_G) then c.demo = nil; c:Request("GLIDE") end
    if input:GetKeyPress(KEY_L) then c.demo = nil; c:Request("LAND") end
    if input:GetKeyPress(KEY_R) and not c.loco.airborne then c.demo = nil; c:Request("ROAR") end
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
    if shotCfg ~= nil and shotCfg.update ~= nil then shotCfg.update(M, dt) end
    if shotCfg == nil or not shotCfg.noInput then HandleKeys() end
    HandleMouse()
    if not M.externalDrive then ctrl_:Update(dt) end
    if M.playMode and not M.externalDrive then
        ride_:Update(dt, cam.yaw)
        DebugUI.SetHint(ride_.hint)
        local want = ride_:CameraTarget()
        if cam.follow then cam.target = cam.target:Lerp(want + cam.pan, 1.0 - math.exp(-10.0 * dt)) end
    else
        if M.nomi ~= nil then
            if M.nomiNode.enabled ~= M.showNomi then M.nomiNode:SetDeepEnabled(M.showNomi) end
            if M.showNomi then M.nomi:Update(dt, { moveSpeed = 0, onGround = true }) end
        end
        if cam.follow and cam.ortho == nil then
            local p = rig_.body.worldPosition + Vector3(0, 0.4, 0)
            cam.target = cam.target:Lerp(p + cam.pan, 1.0 - math.exp(-4.0 * dt))
        end
    end
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
