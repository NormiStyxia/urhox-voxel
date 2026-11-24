-- ====================================================================
-- RuinsScene.lua — 时之遗迹：场景装配、输入、相机、谜题流程、龙看守者
--
-- 模块：
--   RuinsTerrain  地形（主岛 / 环形虚空 / 遗迹外环）     RuinsBuild   静态建筑与景观
--   RuinsPuzzles  时之物件与谜题进度                 TimeObject   碎时 / 冻结 / 回溯的物件模型
--   TimeSpells    法术定义（数据驱动）+ 特效          NomiController 诺米步行 + 第三人称瞄准
--   RuinsHUD      目标 / 法术槽 / 准星 / 提示
-- 龙：复用 dragon/ 的骨架、动画控制器与骑乘（DragonRide 的步行部分交给 NomiController）。
-- 默认训练场由中央木桩派出单只敌人；仅旧探索模式创建龙和骑乘控制器。
-- 巨龙动画测试面板（DragonDebugUI）不在本场景加载；需要时把 DEBUG_PANEL 设为 true（F10 切换）。
-- ====================================================================

local Pal = require("ruins.RuinsPalette")
local Brush = require("ruins.VoxelBrush")
local DayNight = require("ruins.DayNight")
local SkyAtmosphere = require("ruins.SkyAtmosphere")
local LightQuality = require("ruins.LightQuality")
local RenderBudget = require("ruins.RenderBudget")
local GroundContact = require("ruins.GroundContact")
local Terrain = require("ruins.RuinsTerrain")
local Build = require("ruins.RuinsBuild")
local Puzzles = require("ruins.RuinsPuzzles")
local Spells = require("ruins.TimeSpells")
local Sigil = require("ruins.TimeSigil")
local TimeCatalyst = require("combat.TimeCatalystVisual")
local RuinsDragon = require("ruins.RuinsDragon")
local Nomi = require("ruins.NomiController")
local HUD = require("ruins.RuinsHUD")
local VoidRewind = require("ruins.VoidRewind")
local TouchInput = require("ui.TouchInput")
local TouchControls = require("ui.TouchControls")
local HomeIsland = require("ruins.HomeIsland")
local HomeTrees = require("ruins.HomeTrees")
local WorldMap = require("ui.WorldMap")
local PixelDraw = require("ui.PixelDraw")
local lastRuinsLanding,homeJob
local SettingsMenu = require("ui.SettingsMenu")
local PerformanceHUD = require("ui.PerformanceHUD")
local DebugLog = require("ruins.DebugLog")
local CombatState = require("combat.CombatState")
local Safe=CombatState.Isolated
local CombatMoves = require('combat.CombatMoves')
local SwingPerf=require('combat.SwingPerf')
local FootLocomotion=require('ruins.FootLocomotion')
local ClothInertia=require('combat.ClothInertia')
local foot_
local combatControls,combatMoveOptions={},{}
local CombatAnim = require('combat.CombatAnim')
local WeaponSelectGesture=require('combat.WeaponSelectGesture')
local WeaponWheel=require('ui.WeaponWheel')
local weaponGesture_
local CombatHit = require('combat.Hit')
local Hit = CombatHit
local CombatAudio = require('combat.CombatAudio')
local BowArrowTrailFx = require('combat.BowArrowTrailFx')
-- Keep failed audio playback from aborting damage/projectile settlement.
local combatAudioPort={}
function combatAudioPort.Play(name,opts)
    local _,handle=Safe('Audio.Play',CombatState.PerfCall,'audio',CombatAudio.Play,name,opts)
    return handle
end
function combatAudioPort.Stop(handle)
    if handle then Safe('Audio.Stop',CombatAudio.Stop,handle) end
end
local combatAudioWarmup_ = nil
-- Queue once after startup settles; resource work stays in Audio.Update's
-- per-engine-frame budget, on real time even during hitstop/menu/preview.
local function UpdateCombatAudio(realDt)
    if combatAudioWarmup_ ~= nil then
        combatAudioWarmup_ = combatAudioWarmup_ + realDt
        if combatAudioWarmup_ >= 2 then
            combatAudioWarmup_ = nil
            Safe('Audio.Preload',CombatAudio.Preload)
        end
    end
    CombatAudio.Update(realDt)
end
local CombatSettings = require('ruins.GameSettings')
local combatLowQuality_=false
local Projectile = require('combat.Projectile')
local EnvironmentDamage = require('combat.EnvironmentDamage')
local combatEnvironment_
local WeaponRig = require('combat.WeaponRig')
local EnemySpawner = require('combat.enemies.Spawner')
local CombatHUD = require('ui.CombatHUD')
local ForgePanel = require('ui.ForgePanel')
local WeaponStore = require('combat.WeaponStore')
local ForgeShowroom = require('combat.ForgeShowroom')
local combatMoves_,combatAnim_,combatArrows_,combatEnemies_
local bowArrowTrailFx_
---@type ClothInertia?
local clothInertia_
local combatParticles_
local hitParticleOwner_={position=Vector3.ZERO,radius=0,age=0,config={height=0,hover=0}}
local combatLookScale_=1
local combatHUDData={}
local hudClockMinute,hudClockPhase
local CombatCamera=require('combat.CombatCamera')
local combatCamera_,combatCameraFrame_
local arrowNodes_={}
local arrowTailMaterial_
local emptyAfterimages_={}
local animPreview_={index=0,t=0,params={moveX=0,moveZ=-1,bow=0,p=.5,weaponInHand=1},direction='后'}
local CombatTest=require('combat.CombatTest')
local combatTest_
local trainingDummy_,handMotes_
local debugDestination_=0
local combatDebugText_,combatDebugUntil_=nil,0
local handWasOn_
---@type table|nil
local combatRig_ = nil
local timeCatalyst_ = nil -- floating star-clock orb for time (casting) mode; visual only
local combatInputBlocked = false
local touchRevision = 0
local voidInputBlocked = false
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
local M = {trainingMode=true}
local Station=require('ruins.TrainingStation')
local Training={position=Vector3(0,.5,0)} -- BuildAltar is .5 m above the court at the origin.
local Resources={world=require('ruins.RuinsResources'),prompt=require('ui.MaterialPrompt'),catalog=require('combat.MaterialCatalog')}
local function OnFoot() return not M.ride or M.ride.mode=='free' end

-- Explicit frame hooks; the pacing service owns GC state and restores it on Stop.
local sceneGC=require('ruins.SceneGC').New()
M.gcEnabled,M.gcDebug=true,false
function M.SetGCEnabled(enabled)
    M.gcEnabled=enabled==true
    sceneGC:SetEnabled(M.gcEnabled)
end
local function StartSceneGC()
    sceneGC.enabled,sceneGC.debug=M.gcEnabled,M.gcDebug
    sceneGC:Start()
end
local function StopSceneGC() sceneGC:Stop() end
function Ruins_HandleGCBeginFrame()
    SwingPerf.BeginFrame(CombatState)
    sceneGC:BeginFrame()
end
function Ruins_HandleGCEndFrame()
    sceneGC.enabled,sceneGC.debug=M.gcEnabled,M.gcDebug
    Safe('GC.Step',sceneGC.Step,sceneGC)
    Safe('Perf.Flush',CombatState.FlushSwapPerf)
    SwingPerf.EndFrame()
end

M.DEBUG_PANEL = false   -- 巨龙动画测试面板：默认隐藏（代码保留在 dragon/DragonDebugUI.lua）
M.SPAWN = M.trainingMode and Vector3(0,.35,-3.05) or Vector3(0, Terrain.RING_Y + 0.1, -64.0)
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
        if DebugLog.enabled then DebugLog.Log("RuinsInput","pointer %s mode=%s",reason,tostring(input.mouseMode)) end
    end,
})

local function Clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
local function Smooth(t) t = Clamp(t, 0, 1) return t * t * (3 - 2 * t) end

-- ---------------------------------------------------------------- 目标文本
local OBJECTIVES = {
    gate = { "打通被封的城门", "南门被碎石堵住了。准星对准碎石，按左键施放「碎时」把它打碎。" },
    bridge = { "修复断桥", "桥体残片悬在裂隙中。站在岸边，瞄准带金色符脉的悬空桥片，按 R 施放「回溯」。" },
    key = { "取得时之钥", "时之碑被封印了。西侧塔台顶上有「时之钥」：打碎悬石，趁碎块下落时按 E「冻结」，踩着碎块爬上塔台。" },
    steles = { "复原四座时之碑", "带着时之钥回到内环，对倒塌的时之碑按 R 施放「回溯」。（%d / 4）" },
    awake = { "遗迹看守者已苏醒", "巨龙认可了你。走近它按 F 骑乘，Space 起飞。时之物件仍可以随意碎时 / 冻结 / 回溯。" },
}

local function RefreshObjective()
    if M.region=="home" then
        HUD.SetObjective("家园小岛", "J 家园房屋　 G 锻造　 M 地图")
        return
    end
    if M.trainingMode and (stage_=='gate' or stage_=='awake') then
        HUD.SetObjective(stage_=='awake' and '四座时之碑已复原' or '遗迹训练场', '靠近中央木桩选择训练对手，或前往南门探索遗迹。')
        return
    end
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
    LightQuality.ApplyShadowFocus(sun)
    renderer.shadowPCFSamples = 4
    sun.shadowBias = BiasParameters(0.00025, 0.6)
    sun.shadowIntensity = 0.0
    sun.shadowResolution = 1.0
    renderer.shadowMapSize = 2048
    -- 天空 + 昼夜（环境光由 SkyLightCapture 跟随天空，替代旧的渐变天空和补光）
    M.dayNight = DayNight.New({ scene = scene_, zone = zone, zoneNode = lg, sun = sun, sunNode = sunNode, hour = M.START_HOUR })
    M.atmosphere = SkyAtmosphere.New(scene_, M.dayNight)
    -- 尺寸与砌筑类型共同缓存；谜题、雕像、金饰不自动套墙砖纹。
    local vmats = {}
    M.surfaceMaterials = vmats
    Brush.materialFor = function(size, masonry)
        local key = tostring(size) .. ":" .. (masonry or "plain")
        if masonry == "meadow" then
            vmats[key] = HomeIsland.meadowMaterial
            return vmats[key]
        end
        local m = vmats[key]
        if m == nil then
            m = Material:new()
            if not m:SetSurfaceShader("Shaders/BLGL/RuinsVoxel.shader") then
                print("RuinsScene: RuinsVoxel.shader failed, using palette material")
                Brush.materialFor = nil
                return nil
            end
            m:SetSurfaceTexture("palette_tex", world_:GetPaletteTexture())
            m:SetShaderParameter("voxel_size", Variant(size))
            m:SetShaderParameter("masonry_mode", Variant(masonry == "court" and 4.0 or (masonry == "ring" and 2.0 or (masonry == "floor" and 3.0 or (masonry == "ashlar" and 1.0 or 0.0)))))
            m:SetShaderParameter("wall_radius", Variant(masonry == "court" and Terrain.COURT_R or Terrain.WALL_R))
            -- Home stone palette slots may share a bank/entrance/house volume with other surfaces.
            m:SetShaderParameter("home_stone_origin",Variant(Vector3(HomeIsland.x,HomeIsland.base,HomeIsland.z)))
            if masonry=="homeMasonry" then m:SetShaderParameter("dressed_stone_draw",Variant(1.0)) end
            if masonry=="homeWindows" then m:SetShaderParameter("home_house_draw",Variant(1.0)) end
            vmats[key] = m
            GroundContact.Register(m)
        end
        -- Rebind on cache hits as well when a cancelled home build is retried.
        if masonry=="homeWindows" then HomeIsland.BindWindowMaterial(m) end
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

local function GameplayInputAllowed()
    return not Training.blocked() and not WorldMap.IsOpen() and not WeaponWheel.IsBlocked() and not voidInputBlocked and not M.debugOn
        and not TouchControls.IsBlocked() and input.focus and not input.minimized
        and (TouchInput.IsEnabled() or pointer:IsEnabled() or M.fake~=nil)
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
    ride.controlsEnabled = function() return GameplayInputAllowed()
        and not (combatMoves_ and combatMoves_.dead) and animPreview_.index==0 end
    ride.canMountInput=function() return not Resources.consumed and not Resources.nearest() end
    ride.onNotice = function(text) caster_:Say(text) end
    ride.onMount = function()
        nomi_:ResetJump()
        CombatState.SetMounted(true)
        caster_.charging,caster_.charge=false,0
        nomi_.cc.enabled = false
        M.mounted = true
    end
    ride.onDismount = function(pos)
        nomi_:ResetJump()
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
        if DebugLog.enabled then DebugLog.Log("RuinsPerf","sleeping dragon pose cached") end
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
        if not M.trainingMode then WakeDragon() end
    end
end

-- Touch state is sampled from the actual gameplay state, never inferred from UI.
local combatEnemyView,emptyEnemies={},{}
local function CombatEnemies()
    local list=combatEnemies_ and combatEnemies_:GetEnemies() or emptyEnemies
    if not trainingDummy_ then return list end
    local count=#list
    for i,enemy in ipairs(list) do combatEnemyView[i]=enemy end
    combatEnemyView[count+1]=trainingDummy_
    for i=#combatEnemyView,count+2,-1 do combatEnemyView[i]=nil end
    return combatEnemyView
end

-- Query only active enemy-owned fields.  The returned value is consumed by the
-- player controller and combat clock, never by UI, camera, enemy AI, or world
-- time.  Multiple fields compose by taking the strongest local slowdown.
local function PlayerTimeScale(position)
    local scale=1
    for _,enemy in ipairs(CombatEnemies()) do
        if enemy and enemy.active~=false and not enemy.dead and type(enemy.GetPlayerTimeScale)=='function' then
            local candidate=enemy:GetPlayerTimeScale(position)
            if type(candidate)=='number' and candidate<candidate then candidate=1 end
            if type(candidate)=='number' then scale=math.min(scale,math.max(.5,math.min(1,candidate))) end
        end
    end
    return scale
end

-- Independent ray safeguard: even a misconfigured native layer cannot let the
-- equipped model, sword afterimages or trail particles occlude aim/projectiles.
local function IsCombatVisualVolume(volume)
    local rig=combatRig_
    if not rig then return false end
    for _,entry in pairs(rig.entries) do if entry.mesh.volume==volume then return true end end
    for _,item in ipairs(rig.trails) do if item.volume==volume then return true end end
    for _,item in ipairs(rig.images) do if item.volume==volume then return true end end
    for _,item in ipairs(rig.bowImages or {}) do if item.volume==volume then return true end end
    for _,item in ipairs(rig.bowStrings or {}) do if item.volume==volume then return true end end
    for _,item in ipairs(rig.bowDrawMeshes or {}) do if item.volume==volume then return true end end
    for _,item in ipairs(rig.flightArrows or {}) do if item.volume==volume then return true end end
    if rig.bowArrow and rig.bowArrow.volume==volume then return true end
    for _,item in pairs(rig.flashes or {}) do if item.volume==volume then return true end end
    for _,item in ipairs(rig.particles) do if item.volume==volume then return true end end
    return false
end
-- Enemy poses/telegraphs author these cues. One native subscription owns their audio.
---@param data VariantMap
function Ruins_HandleEnemyAttackCue(_,data)
    if not M.combat then return end
    local cue=M.combat.enemyCue or {}
    cue.enemyId, cue.attack, cue.phase=data:GetString('EnemyId'),data:GetString('Attack'),data:GetString('Phase')
    cue.position, cue.duration=data:GetVector3('Position'),data:GetFloat('Duration')
    M.combat.enemyCue=cue
    local name=data:GetString('Event')
    if name=='camera_shake' then
        Safe('Camera.EnemyCue',combatMoves_.Envelope,combatMoves_,'enemy:'..cue.enemyId..':'..name..':'..time_,data:GetFloat('Magnitude'),data:GetFloat('Duration'),0,Vector3.RIGHT,0)
    elseif name~='attack_active' and name~='attack_stop' and name~='' then
        if name=='die' then name='enemy_die' end
        combatAudioPort.Play(name,{pos=cue.position,enemy=data:GetString('Enemy'),material=data:GetString('Material'),
            tier=data:GetBool('Danger') and 'danger' or data:GetString('Tier')})
    end
    DebugLog.Log('combat-cue','%s / %s / %s',cue.enemyId,cue.attack,cue.phase)
end
-- Read-only queries. The optional second result identifies the exact world cell
-- for real weapon impacts; aiming/LOS/prediction never damage geometry.
---@param a Vector3
---@param b Vector3
local function CombatCast(a,b,decorative)
    local delta=b-a
    local length=delta:Length()
    if length<.0001 then return nil end
    local hit=nomi_:GridHit(Ray(a,delta/length),length,decorative)
    return hit.hit and Clamp(hit.distance/length,0,1) or nil,hit
end
local function CombatFeedback(event)
    if not combatParticles_ or event.presentationConsumed then return end
    -- W3 owns real enemy particles at successful settlement. The same shared
    -- scene pool handles player and training impacts only, never a duplicate.
    if not event.player and event.enemy and (event.enemy.OnHitEvent or event.enemy.particles) then return end
    hitParticleOwner_.position,hitParticleOwner_.age=event.pos,time_
    combatParticles_:Emit(hitParticleOwner_,event)
end
local function CombatMeleeEnvironment(moves,active)
    if not combatEnvironment_ then return end
    local root,tip
    if not moves.dead and combatRig_.active=='sword' and combatRig_.visualState=='hand' and combatRig_.pose=='hand' then
        local pivot=combatRig_.entries.sword.pivot
        root=pivot:LocalToWorld(combatRig_.bladeRoot)
        tip=pivot:LocalToWorld(combatRig_.bladeTip)
    end
    Safe('Environment.Melee',combatEnvironment_.Melee,combatEnvironment_,root,tip,nomi_:Position(),
        moves.swingSerial,moves.hitClip,active,moves.age)
end
local function CombatArrowEnvironment(event)
    local ok,removed=Safe('Environment.Arrow',combatEnvironment_.Arrow,combatEnvironment_,event)
    CombatFeedback(event)
    return ok and removed>0
end
local function CombatEnvironmentTrace(kind,reason,hit,center,radius,removed)
    local volume=hit and hit.volume
    print(string.format('WeaponVoxel kind=%s stage=%s volume=%s destructible=%s layer=%s voxel=%s material=%s hit=%s normal=%s center=%s radius=%s removed=%s',
        kind,reason,tostring(volume and volume.volumeId),tostring(volume and volume.destructible),
        tostring(volume and volume.collisionLayer),tostring(hit and hit.voxel),tostring(hit and hit.material),
        tostring(hit and hit.position),tostring(hit and hit.normal),tostring(center),tostring(radius),tostring(removed)))
end
local function CombatHasAggro()
    for _,enemy in ipairs(CombatEnemies()) do if enemy.active and enemy.aggro and not enemy.dead then return true end end
    return false
end
local function CanOpenForge()
    if Training.blocked() or (M.housePanel and M.housePanel.open) then return false end
    if WorldMap.IsOpen() or not nomi_ or not OnFoot() or CombatState.Engaged()
        or combatMoves_.dead or voidInputBlocked or SettingsMenu.IsBlocked() or animPreview_.index>0 then return false end
    local p=nomi_:Position()
    if M.region=="home" then return nomi_.cc.onGround and HomeIsland.NearForge(p) end
    return nomi_.cc.onGround and Terrain.IsSafeGround(p.x,p.y,p.z)
end
local function OpenForge()
    if weaponGesture_ then weaponGesture_:ForceClose('forge') end
    if not CanOpenForge() then
        print(('Forge: refused reason=blocked mode=%s onGround=%s aggro=%s dead=%s'):format(
            tostring(M.ride and M.ride.mode),tostring(nomi_ and nomi_.cc.onGround),tostring(CombatState.Engaged()),
            tostring(combatMoves_.dead)))
        caster_:Say(CombatState.Engaged() and '战斗中无法锻造' or (M.region=='home' and '走近屋前的锻造炉' or '请在安全地面、脱离警戒后锻造'),1.2); return
    end
    -- Bind the exact live module's read-only getter; no package.loaded key or
    -- separately maintained HUD state is required for the primary route.
    HUD.SetForgeVisibility(ForgePanel.HudHidden); CombatHUD.SetForgeVisibility(ForgePanel.HudHidden)
    TouchControls.SetForgeVisibility(ForgePanel.HudHidden); PerformanceHUD.SetForgeVisibility(ForgePanel.HudHidden)
    ForgePanel.Open({rig=combatRig_,canOpen=CanOpenForge,
        onOpen=function()
            -- Once per opening: distinguish a stale/missing module cache from a
            -- phase issue in Web logs, without probing or printing each frame.
            print('Forge: HUD lookup cachedSame='..tostring(package.loaded['ui.ForgePanel']==ForgePanel)
                ..' getter='..tostring(type(ForgePanel.HudHidden)))
            pointer:Release('forge'); pointer:SetBlocked(true)
            TouchControls.Cancel(); drag.buttons=0
            caster_.charging,caster_.charge=false,0
        end,
        onClose=function()
            TouchControls.Cancel(); pointer:SetBlocked(M.debugOn or SettingsMenu.IsBlocked())
            pointer:Release('forge-close')
        end})
end
function Training.blocked()
    return Training.release or (M.trainingStation and M.trainingStation:IsOpen()) or false
end

function Resources.available()
    return Resources.live and M.region=='ruins' and OnFoot() and nomi_.cc.onGround and not combatMoves_.dead
        and input.focus and not input.minimized and not voidInputBlocked and not VoidRewind.IsActive()
        and not Training.blocked() and not M.debugOn and animPreview_.index==0
        and not WorldMap.IsOpen() and not ForgePanel.IsOpen() and not WeaponWheel.IsBlocked()
        and not SettingsMenu.IsBlocked() and not TouchControls.menuOpen and not (M.housePanel and M.housePanel.open)
end

function Resources.nearest()
    if Resources.available() then return Resources.live:Nearest(nomi_:Position()) end
end

function Resources.interact(target)
    if not target or not Resources.available() then return end
    Resources.consumed=true
    local ok,message=Resources.live:Claim(target.id,nomi_:Position(),function(item)
        return WeaponStore.AddMaterial(combatRig_,item.itemId,item.count,item.trainingKind,
            item.source=='site' and item.key or nil)
    end)
    if ok then
        Resources.prompt.Clear()
        CombatHUD.Say(('%s +%d'):format(target.name,target.count),1.6)
        DebugLog.Log('Ruins','Material pickup %s x%d from %s',target.itemId,target.count,target.id)
    elseif message then CombatHUD.Say(message,1.7) end
end

function Resources.present(cameraNode)
    local target=Resources.nearest()
    if not target then Resources.prompt.Clear(); return end
    local offset=target.source=='drop' and .45 or 1.15
    Resources.prompt.Set(target,Resources.catalog.ById[target.itemId],target.verb,
        target.position+Vector3(0,offset,0),nomi_:Camera(),cameraNode)
end

function Resources.attach()
    TouchControls.onGatherHit=function(x,y)
        if Resources.available() then return Resources.prompt.Hit(x,y) end
    end
    TouchControls.onGather=Resources.interact
    Resources.prompt.Attach(HUD.root,Resources.available)
end

function Training.near()
    if not M.trainingStation or M.region~='ruins' or not input.focus or input.minimized or not OnFoot()
        or voidInputBlocked or M.debugOn or combatMoves_.dead or animPreview_.index>0
        or WorldMap.IsOpen() or ForgePanel.IsOpen() or SettingsMenu.IsBlocked() or WeaponWheel.IsBlocked() then return false end
    local p=nomi_:Position()
    local dx,dz=p.x-Training.position.x,p.z-Training.position.z
    return dx*dx+dz*dz<=3.2^2 and math.abs(p.y-Training.position.y)<1.3
end

function Training.openChanged(open)
    Training.release=not open
    combatInputBlocked=true
    drag.buttons=0
    caster_.charging,caster_.charge,caster_.castAnim=false,0,0
    TouchControls.Cancel()
    pointer:SetBlocked(open or voidInputBlocked or WorldMap.IsOpen() or SettingsMenu.IsBlocked() or ForgePanel.IsOpen())
    if open and not TouchInput.IsEnabled() then
        input:SetMouseMode(MM_ABSOLUTE)
    elseif not open and not pointer.blocked then
        pointer:Release('training-close')
        pointer:Resume()
    end
    TouchControls.Sync()
end

function Training.update()
    local station=M.trainingStation
    if not station then return false end
    station:SetNear(Training.near() and (station:IsOpen() or not Resources.nearest()))
    if station:IsOpen() then return true end
    if not Training.release then return false end
    -- Retire the UI gesture through its final release frame, including keyboard row shortcuts.
    if input.numTouches==0 and not input:GetMouseButtonDown(MOUSEB_LEFT) and not input:GetMouseButtonDown(MOUSEB_RIGHT)
        and not input:GetKeyDown(KEY_F) and not input:GetKeyDown(KEY_E) and not input:GetKeyDown(KEY_ESCAPE) then
        local held=false
        for k=KEY_1,KEY_5 do if input:GetKeyDown(k) then held=true end end
        if not held then Training.release=false end
    end
    return true
end

local bowPrediction=Projectile.NewPrediction()
local bowAssistScale,bowAssistTarget=1,nil
function Training.clearTarget()
    bowAssistScale,bowAssistTarget=1,nil
    bowPrediction.valid,bowPrediction.working=false,false
    combatHUDData.aimed=nil
    combatMoves_.target,combatMoves_.strikeTarget=nil,nil
    M.combat.aimed,M.combat.enemyCue=nil,nil
    if M.aim then M.aim.enemy=nil end
    nomi_:SetCombatCamera(nil,false,false,false)
end

function Training.clearPlayerAttacks()
    Training.clearTarget()
    if not combatMoves_.dead and combatMoves_.clip~='getup' then combatMoves_:Cancel('training') end
    combatArrows_:Clear()
    BowArrowTrailFx.Clear(bowArrowTrailFx_)
    if combatParticles_ then combatParticles_:ClearOwner(hitParticleOwner_) end
end

function Training.clear()
    Training.clearPlayerAttacks()
    combatEnemies_:ClearTraining()
end

function Training.leave()
    if not M.trainingStation then return end
    M.trainingStation:SetNear(false)
    Training.clear()
end

function Training.select(modelName)
    if not Training.near() then return end
    -- Side clearings avoid the raised altar and its north wall, including the colossus footprint.
    local p=nomi_:Position()
    local x=p.x>0 and -7 or 7
    local z=-2
    local y=Terrain.GroundHeight(x,z)
    if not y or not Terrain.HasGround(x,z,2) or not Terrain.IsSafeGround(x,y,z) then
        CombatHUD.Say('训练落点不可用',1.5)
        return
    end
    Training.clearPlayerAttacks()
    combatEnemies_:SpawnTraining(modelName,Vector3(x,y,z))
end

local function StartCombat()
    CombatAudio.New(scene_)
    combatAudioWarmup_ = 0
    combatCamera_=CombatCamera.New()
    combatAnim_=CombatAnim.New(nomi_.nomi,nomi_.node,{bowRig=combatRig_})
    clothInertia_=ClothInertia.New(nomi_.nomi)
    local bowFireHits,bowFirePool={},{}
    for i=1,64 do bowFirePool[i]={} end
    combatMoves_=CombatMoves.New({anim=combatAnim_,rig=combatRig_,state=CombatState,
        clear=function(reason) if weaponGesture_ then weaponGesture_:Interrupt(reason) end end,
        position=function() return nomi_:Position() end,forward=function() return nomi_.node.worldDirection end,
        enemies=CombatEnemies,cast=CombatCast,feedback=CombatFeedback,audio=combatAudioPort,camera=combatCamera_,
        environmentMelee=CombatMeleeEnvironment,
        impactRing=function(pos,dir)
            if not nomi_.cc.onGround then return end
            CombatMoves.EmitImpactRing(combatParticles_,hitParticleOwner_,pos,dir)
        end,
        attackMotion=function(motion) return nomi_:ClipAttackMotion(motion) end,
        aimPitch=function()return nomi_.camPitch end,
        intent=function() local a=math.rad(nomi_.camYaw);return Vector3(math.sin(a),0,math.cos(a)) end,
        assist=function(intent,selectTarget)
            return nomi_:AssistMelee(CombatEnemies(),CombatCast,intent,selectTarget and CombatState.GetSetting('aimAssist'))
        end,
        protected=function() return not OnFoot() or voidInputBlocked or animPreview_.index>0 end,
        captureBowShot=function(shot)
            local cn=nomi_:CameraNode()
            shot.cameraOrigin,shot.cameraDirection=cn.worldPosition,cn.worldDirection
        end,
        fire=function(charge,stats,forceCrystal,snapshot)
            local hit=combatRig_:GetHit()
            local cn=nomi_:CameraNode()
            local a=snapshot and snapshot.cameraOrigin or cn.worldPosition
            local b=a+(snapshot and snapshot.cameraDirection or cn.worldDirection)*64
            local wall=CombatCast(a,b)
            local contacts=CombatHit.Query(CombatEnemies(),a,b,0,nil,bowFireHits,bowFirePool)
            local reach=wall or 1
            if contacts[1] and contacts[1].t<reach then reach=contacts[1].t end
            local target=a+(b-a)*reach
            local shotStats=stats
            if forceCrystal and not snapshot then
                shotStats={}; for key,value in pairs(stats) do shotStats[key]=value end
                shotStats.crystalRadius=.8; shotStats.crystalDamageMultiplier=.25
            end
            if combatTest_ and combatTest_.active and trainingDummy_ then
                target=trainingDummy_:GetHurtShapes()[1].center -- synthetic aim, real swept projectile collision
            end
            local tip=combatRig_:GetBowArrowTip()
            local fired,shot=combatArrows_:Fire(hit.origin,(target-tip):Normalized(),charge,shotStats,tip,combatRig_:GetBowModelId())
            if fired and combatTest_ and combatTest_.active then combatTest_:Arrow(shot) end
            return fired
        end,
        respawn=function()
            -- Use the established safe-point/fallback and camera snap; puzzle
            -- progress is untouched. Avoid starting the cinematic void path.
            nomi_:ReturnFromVoid()
            combatArrows_:Clear()
            if not M.trainingMode then combatEnemies_:Reset() end -- training clears in onVoidReturn
            caster_:Say('时之印记 · 生命已恢复',1.2)
        end})
    foot_=FootLocomotion.New({
        legAngles=function()
            return nomi_.nomi.bones.leg_right.rotation:EulerAngles().x,nomi_.nomi.bones.leg_left.rotation:EulerAngles().x
        end,
        start=function()
            caster_.charging,caster_.charge,caster_.castAnim=false,0,0
            local params=foot_.animOpts.params
            params.weaponInHand=combatMoves_:WeaponInHand() and 1 or 0
            params.sprintWeight,params.gaitPhase=foot_.weight,foot_.phase
            params.sprintAccel,params.bow=1,CombatState.GetWeapon()=='bow' and 1 or 0
            foot_.animHandle=combatAnim_:Play('sprint_loop',foot_.animOpts)
        end,
        step=function()
            if not combatLowQuality_ and nomi_.cc.onGround then
                combatMoves_:Sound('run_step',{pos=nomi_:Position(),volume=.35})
                CombatMoves.EmitDustStreak(combatParticles_,hitParticleOwner_,nomi_:Position(),
                    foot_.direction or nomi_.node.worldDirection,nomi_.slideGroundPort,1)
            end
        end})
    combatMoves_.o.locomotion=foot_
    foot_:Soles(nomi_.nomi,require('game.NomiVoxelDataElbow'),require('game.BlockCharacter').SLENDER)
    M.foot=foot_
    weaponGesture_=WeaponSelectGesture.New({character=nomi_.nomi,root=nomi_.node,
        wheel=WeaponWheel,moves=combatMoves_,rig=combatRig_,state=CombatState,
        items={{id='sword',name='长剑',tag='近距离 / 削切'},
            {id='bow',name='长弓',tag='远距离 / 单点'},
            {id='time',name='时间法器',tag='中距离 / 碎时 · 冻结 · 回溯'}},
        selection=CombatState.GetSelection,
        select=function(id) return combatMoves_:SelectLoadout(id) end,
        canOpen=function()
            if Training.blocked() or (M.housePanel and M.housePanel.open) then return false end
            local clip=combatMoves_.clip
            return OnFoot() and not combatMoves_.dead
                and not voidInputBlocked and not M.debugOn and not ForgePanel.IsOpen() and not SettingsMenu.IsBlocked()
                and input.focus and not input.minimized and animPreview_.index==0
                and clip~='getup' and clip~='knockdown' and clip~='death'
                and not (clip and clip:find('hit_',1,true))
        end,
        takeInput=function()
            combatInputBlocked=true
            -- WeaponWheel's gameplay gates own input without releasing pointer lock.
            TouchControls.Cancel(); drag.buttons=0
            pointer.attackArmed,pointer.skipLook=false,true
            caster_.charging,caster_.charge,caster_.castAnim=false,0,0
        end,
        releaseInput=function()
            combatInputBlocked=true; drag.buttons=0
            TouchControls.Cancel()
            pointer:SetBlocked(M.debugOn==true or SettingsMenu.IsBlocked() or ForgePanel.IsOpen() or voidInputBlocked)
            pointer.attackArmed,pointer.skipLook=false,true
            if input.focus and not input.minimized then pointer:Resume() end
        end})
    local tailMaterial=Material:new()
    arrowTailMaterial_=tailMaterial
    tailMaterial:SetTechnique(0,cache:GetResource('Technique','Techniques/NoTextureUnlit.xml'))
    tailMaterial:SetShaderParameter('MatDiffColor',Variant(Color(.65,.70,.65,1)))
    for i=1,12 do
        local node=scene_:CreateChild('CombatArrow_'..i)
        node.enabled=false
        local tails={}
        for j=1,4 do
            local tail=node:CreateChild('tail_'..j)
            local mesh=tail:CreateComponent('StaticModel')
            mesh:SetModel(cache:GetResource('Model','Models/Box.mdl')); mesh:SetMaterial(tailMaterial)
            tail.scale=Vector3(.022-(j-1)*.004,.022-(j-1)*.004,.09)
            tails[j]=tail
        end
        arrowNodes_[i]={node=node,tails=tails}
    end
    combatEnvironment_=EnvironmentDamage.New({world=world_,cast=CombatCast,timeObject=Puzzles.FindByVolume,
        feedback=CombatFeedback,trace=CombatEnvironmentTrace})
    bowArrowTrailFx_=BowArrowTrailFx.New(scene_)
    combatArrows_=Projectile.New({enemies=CombatEnemies,cast=CombatCast,log=CombatState.Log,audio=combatAudioPort,
        hit=function(...) combatMoves_:Feedback(...) end,wallHit=CombatArrowEnvironment,
        draw=function(p,visible)
            local entry=arrowNodes_[p.index]
            entry.node.enabled=visible
            combatRig_:DrawArrow(p,visible)
            if bowArrowTrailFx_ then BowArrowTrailFx.Draw(bowArrowTrailFx_,p,visible) end
            if visible then
                entry.node.position=Vector3.ZERO
                local current=p.renderPos or p.pos
                for j,tail in ipairs(entry.tails) do
                    tail.enabled=not p.embedded and j<=p.historyCount
                    if tail.enabled then
                        local previous=p.history[(p.historyWrite-j)%4+1]
                        local delta=current-previous
                        local distance=math.min(.15,delta:Length())
                        if distance<.001 then tail.enabled=false
                        else
                            tail.position=current-delta:Normalized()*(distance*.5)
                            tail:SetDirection(delta:Normalized())
                            local width=(p.critical and .014 or .007)*(1-(j-1)*.18)
                            tail.scale=Vector3(width,width,distance)
                        end
                        current=previous
                    end
                end
            end
        end})
    local createSpawner=EnemySpawner.New
    if M.trainingMode then createSpawner=EnemySpawner.NewTraining end
    combatEnemies_=createSpawner(scene_,world_,Terrain,{
        PlayerPos=function() return nomi_:Position() end,
        DamagePlayer=function(info)
            if ForgePanel.IsOpen() then ForgePanel.Close(true) end
            if SettingsMenu.IsBagOpen() then SettingsMenu.Close() end
            return CombatHit.Apply(combatMoves_,info)
        end,
        OnEnemyAggro=function(id)
            if ForgePanel.IsOpen() then ForgePanel.Close(true) end
            if SettingsMenu.IsBagOpen() then SettingsMenu.Close() end
            if animPreview_.index==0 then CombatState.OnEnemyAggro(id) end
        end,
        OnEnemyDead=function(enemy)
            local drop=Resources.live and Resources.live:SpawnDrop(enemy.kind,enemy.position,nomi_.safePos)
            if M.trainingMode then
                Training.clearTarget()
                CombatHUD.Say(drop and '训练完成，靠近拾取素材' or '训练完成，可回木桩再选对手',1.6)
                return
            end
            combatMoves_.target=enemy
            if ForgePanel.IsOpen() then ForgePanel.Close(true) end
            local _,message=WeaponStore.RewardKill(combatRig_)
            CombatHUD.Say(message,2.5)
        end})
    -- The legacy Spawner.New roster remains the default for tests and callers.
    -- Exploration explicitly opts into model-backed encounters; the central
    -- training arena stays empty and selects exactly one actor at a time.
    if not M.trainingMode then combatEnemies_:EnableModelEncounters() end
    M.combat={state=CombatState,moves=combatMoves_,enemies=combatEnemies_,anim=combatAnim_,arrows=combatArrows_}
    combatParticles_=combatEnemies_:GetParticlePool()
    CombatSettings.RegisterQuality('combat-presentation',function(profile)
        combatLowQuality_=profile.quality=='low'
        combatParticles_:SetLimit(combatLowQuality_ and 32 or 64)
        CombatAudio.SetQuality(combatLowQuality_ and 'low' or 'mid')
    end)
end
local function TravelToRegion(region)
    if not OnFoot() then return false,'先下龙，再启程' end
    if CombatState.Engaged() or combatMoves_.dead then return false,'脱离战斗后可启程' end
    if voidInputBlocked or not nomi_.cc.onGround then return false,'请先回到地面' end
    local destination,yaw
    if region=='home' then
        if not Terrain.home then
            HomeIsland.GetHouseOccupants=function()
                if not M.rig then return nomi_:Position(),{} end
                local root=M.rig.root.worldPosition
                local bounds={{base=root,radius=.65*M.rig.size,height=.2}}
                local rotation=Quaternion(M.ctrl.loco.yaw,Vector3.UP)
                for _,ball in ipairs(M.dragonWorld.hull) do
                    local center=root+rotation*ball.offset
                    bounds[#bounds+1]={base=Vector3(center.x,center.y-ball.radius,center.z),
                        radius=ball.radius,height=2*ball.radius}
                end
                return nomi_:Position(),bounds
            end
            homeJob=homeJob or HomeIsland.BeginBuild(world_,scene_,M.dayNight)
            return false,'正在展开家园小岛…'
        end
        destination=Vector3(HomeIsland.x+5,HomeIsland.base+.1,HomeIsland.z-12)
        yaw=-28
        lastRuinsLanding=nomi_.safePos
    else
        destination=lastRuinsLanding or M.SPAWN
        yaw=0
    end
    if not nomi_:TeleportToSafeGround(destination,yaw) then return false,'此落点暂不可用' end
    Training.leave()
    HomeIsland.ClearRipples()
    if region~='home' then
        HomeIsland.SetWindowLightingActive(false)
        HomeIsland.ReleaseReflection()
    end
    nomi_.fallbackPos=region=='home' and destination or M.SPAWN
    if M.ride then
        M.ride.pos=destination
        M.ride.vy,M.ride.speed=0,0
    end
    if M.dragonAwake then
        local nest=region=='home' and Vector3(HomeIsland.x+12,HomeIsland.base+1.75,HomeIsland.z+3) or M.DRAGON_POS
        M.ctrl.loco.arenaX=region=='home' and HomeIsland.x or 0
        M.ctrl.loco.arenaZ=region=='home' and HomeIsland.z or 0
        M.ctrl:Teleport(nest,M.DRAGON_YAW)
        M.ride.wander.center=nest
        M.ride.aiOff=region=='home' or not M.settled
        M.ctrl.input.move,M.ctrl.input.turn=0,0
        if M.ctrl.state=='WALK' then M.ctrl:Request('IDLE') end
    end
    combatArrows_:Clear()
    M.region=region
    RefreshObjective()
    return true
end
local function AdvanceHomeTravel()
    local done,err=homeJob:Step()
    if err then
        homeJob=nil
        print('HomeIsland build failed: '..tostring(err));WorldMap.SetNotice('载入中断，点家园重试')
    elseif done then
        homeJob=nil;Terrain.home=HomeIsland
        RenderBudget.Apply(scene_) -- 家园新建的体积/树木同样限制阴影与绘制距离
        local ok,why=TravelToRegion('home')
        if ok then WorldMap.Close() else WorldMap.SetNotice(why) end
    end
end
local function OpenWorldMap()
    if Training.blocked() or (M.housePanel and M.housePanel.open) then return end
    if M.debugOn or voidInputBlocked or combatMoves_.dead or SettingsMenu.IsBlocked() or ForgePanel.IsOpen()
        or WeaponWheel.IsBlocked() or animPreview_.index>0 then return end
    if weaponGesture_ then weaponGesture_:ForceClose('map') end
    TouchControls.Cancel();pointer:SetBlocked(true);drag.buttons=0
    WorldMap.Open(HUD.root,M.region,TravelToRegion,function()
        if homeJob then homeJob:Cancel();homeJob=nil end
        TouchControls.Cancel();combatInputBlocked=true;pointer:SetBlocked(false);pointer:Release('map-close');pointer:Resume()
    end,TouchInput.IsEnabled())
end
local function CanOpenWeaponBag()
    return OnFoot() and not Training.blocked() and nomi_.cc.onGround and not combatMoves_.dead
        and input.focus and not input.minimized
        and not CombatState.Engaged() and not voidInputBlocked and not M.debugOn
        and not WorldMap.IsOpen() and not ForgePanel.IsOpen() and not WeaponWheel.IsBlocked()
        and not (M.housePanel and M.housePanel.open) and animPreview_.index==0
end
local function AttachTouchControls()
    local touchState={}
    local cooldown = {}
    for _,sp in ipairs(Spells.SPELLS) do cooldown[sp.id]=sp.cooldown end
    TouchControls.Attach(HUD.root,function()
        local ride,ctrl=M.ride,M.ctrl
        touchState.mounted,touchState.mounting=not OnFoot(),ride and ride.mode=="mounting"
        touchState.airborne,touchState.gliding=ctrl and ctrl.loco.airborne,ctrl and ctrl.state=="GLIDE"
        touchState.blocked=Training.blocked() or M.debugOn or voidInputBlocked or ForgePanel.IsOpen() or WeaponWheel.IsBlocked() or WorldMap.IsOpen()
            or (M.housePanel and M.housePanel.open)
        touchState.breathActive=M.stream and M.stream.active
        touchState.skillLeft=math.max(0,(M.weaponSkillReadyAt or 0)-time_)
        touchState.noSpells=not CombatState.CanUseTime()
        touchState.readyFlash,touchState.aggro=CombatState.ReadyFlash(),CombatState.Engaged()
        touchState.unifiedSelection=true
        touchState.combat,touchState.weapon=CombatState.InCombat(),CombatState.GetWeapon()
        touchState.combatCharge=combatMoves_ and combatMoves_.charge or 0
        touchState.sprinting=foot_ and foot_:IsSprinting()
        touchState.canMount=ride~=nil and M.dragonAwake and not ride.locked and ride.mode=="free" and ride.onGround and ride:NearDragon()<3.6
        touchState.cool,touchState.cooldown,touchState.charging=caster_.cool,cooldown,caster_.charging
        touchState.charge=caster_.charging and caster_.charge or 0
        return touchState
    end,function(on)
        pointer:Release("touch-mode")
        drag.buttons=0
        caster_.charging,caster_.charge=false,0
    end,function()
        if foot_ then foot_:Cancel('touch-cancel') end
        combatInputBlocked=true
        local selecting=weaponGesture_ and (weaponGesture_:IsOpen() or weaponGesture_.committing or weaponGesture_.closing or WeaponWheel.IsBlocked())
        if not selecting and combatMoves_ and not combatMoves_.dead and combatMoves_.clip~='getup' then combatMoves_:Cancel('touch-clear') end
        caster_.charging,caster_.charge=false,0
        if M.stream then M.stream:Stop(true) end
    end)
    TouchControls.onMap=OpenWorldMap
    M.housePanel=HUD.AttachHouse({get=HomeIsland.GetHouseStage,set=HomeIsland.SetHouseStage,
        available=function()
            return M.region=='home' and OnFoot() and not combatMoves_.dead and not voidInputBlocked
                and not M.debugOn and not WorldMap.IsOpen() and not SettingsMenu.IsBlocked()
                and not ForgePanel.IsOpen() and not WeaponWheel.IsBlocked() and animPreview_.index==0
        end,
        changed=function(open)
            TouchControls.Cancel();drag.buttons=0;combatInputBlocked=true
            if open and weaponGesture_ then weaponGesture_:ForceClose('house') end
            pointer:SetBlocked(open or voidInputBlocked or M.debugOn or SettingsMenu.IsBlocked() or ForgePanel.IsOpen() or WorldMap.IsOpen() or WeaponWheel.IsBlocked())
            if not open then pointer:Release('house-close');pointer:Resume() end
        end})
    TouchControls.housePanel=M.housePanel
    VoidRewind.Attach(HUD.root)
    DebugLog.RegisterProbe('Ruins',function()
        local pieces=0
        for _,object in ipairs(Puzzles.list) do pieces=pieces+#object.pieces end
        return {volumes=world_:GetVolumeCount(),pieces=pieces,particles=fx_.motesB:Count()+fx_.motesG:Count(),awake=M.dragonAwake}
    end)
    PerformanceHUD.Attach(HUD.root)
    SettingsMenu.Attach(HUD.root,function(blocked)
        if blocked and weaponGesture_ then weaponGesture_:ForceClose('settings') end
        pointer:SetBlocked(blocked or M.debugOn==true)
        TouchControls.Cancel()
        drag.buttons=0
        caster_.charging,caster_.charge=false,0
        if M.stream then M.stream:Stop(true) end
    end,{
        available=CanOpenWeaponBag,
        unavailable=function() CombatHUD.Say('请脱离警戒并回到地面，再打开背包',1.5) end,
        selection=CombatState.GetSelection,
        progress=function() return combatRig_.config.progress end,
        equip=function(class,id)
            if not CanOpenWeaponBag() then return false,'请脱离警戒后换装' end
            local ok,message=WeaponStore.Forge(combatRig_,class,'select',id)
            return ok,ok and '已装备' or message
        end,
        equipImprint=function(class,id)
            if not CanOpenWeaponBag() then return false,'请脱离警戒后换装' end
            local ok,message=WeaponStore.Forge(combatRig_,class,'imprint',id)
            return ok,ok and '已装备' or message
        end,
    })
end

-- ---------------------------------------------------------------- 启动
function M.Start()
    if scene_ then M.Stop() end
    M.region,lastRuinsLanding,Terrain.home='ruins',nil,nil
    time_,stage_,farView=0,'gate',false
    M.mounted,M.roared,M.spread,M.settled,M.wakeT=false,false,false,false,0
    M.gateHover,M.gateHoverTarget,M.lastGateHover=0,0,nil
    M.runeK,M.runeTarget,M.lastRuneQ=0,0,nil
    M.aim,M.lastAimSignature,M.nextAimLog=nil,nil,nil
    M.debugOn,M.fake,M.fakePress,M.forceCamMode=false,nil,nil,nil
    hudClockMinute,hudClockPhase=nil,nil
    CombatState.ResetIsolation()
    Safe('GC.Start',StartSceneGC)
    voidInputBlocked=false
    combatInputBlocked=false
    M.weaponSkillReadyAt=0
    TouchInput.Detect()
    -- 引擎的自动点击重锁没有 UI / pending 过滤；接管一次，避免两个管理者竞争。
    if not inputTakenOver then
        local uninstall = _G["InputExtensions_Uninstall"]
        if type(uninstall) == "function" then uninstall() end
        inputTakenOver = true
    end
    pointer:Release("start")
    local t0 = GetTime():GetElapsedTime()
    GroundContact.Reset()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")
    world_ = scene_:CreateComponent("VoxelPhysicsWorld")
    -- 体素结构断裂后由 solver 接管脱离部分：失去下方支撑的上部会
    -- 自动成为动态碎块，使用统一重力下落并与地面碰撞；不要在玩法层把它
    -- 留成静态体积，否则底座被打掉后上半部分会悬空。
    world_:SetGravity(Vector3(0, -9.81, 0))
    world_:SetStressBreakFactor(200.0)
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
    M.atmosphere:SetPillarLayout(Build,Terrain.RING_Y) -- intact/broken layout now known
    Puzzles.Build(world_, scene_)
    -- 碎石堆独立材质也要接收霜冻等全局材质参数
    if Puzzles.gateMaterial ~= nil then M.surfaceMaterials.gateRubble = Puzzles.gateMaterial; GroundContact.Register(Puzzles.gateMaterial) end
    world_:OptimizeBroadPhase()
    Puzzles.On(OnPuzzle)

    nomi_ = Nomi.New(scene_, world_, M.SPAWN, 0)
    -- 环境光专用天空只给 SkyLightCapture 看，主相机排除它。
    nomi_:Camera().viewMask = nomi_:Camera().viewMask & ~DayNight.IBL_VIEW
    if not ForgeShowroom.Active() then renderer:SetViewport(0, Viewport:new(scene_, nomi_:Camera())) end
    fx_ = Spells.NewFX(scene_, nomi_:CameraNode())
    handMotes_=require('dragon.VoxelFX').WorldMotes(fx_.root,'CombatHandMotes',32,'square',true,nomi_:CameraNode())
    M.sigils=Sigil.New(scene_)
    caster_ = Spells.NewCaster({ world = world_, puzzles = Puzzles, scene = scene_, fx = fx_, sigils = M.sigils,
        canCast=function(id) return CombatState.CanUseTime() and (id~='shatter' or CombatState.GetSelection()=='time') end,
        enemies=function() return CombatEnemies() end,
        catalystStats=function() return combatRig_:GetStats('time') end,
        spellHit=function(enemy,info) return combatMoves_ and combatMoves_:SpellHit(enemy,info) or false end,
        handPos = function() return nomi_:HandPos() end,
        prepareCast = function(aim) nomi_:PrepareCast(aim) end }) -- 同帧转身与抬手
    combatRig_=WeaponRig.New(scene_,world_,nomi_)
    Resources.live=Resources.world.New(scene_,world_,{training=M.trainingMode,cast=CombatCast,
        wasClaimed=function(key,kind)
            local progress=combatRig_.config.progress
            if kind then return progress.trainingClaims[kind] end
            return progress.siteClaims[key]
        end})
    world_:OptimizeBroadPhase()
    do
        local catalyst,err=TimeCatalyst.New(scene_,nomi_:CameraNode())
        if catalyst then timeCatalyst_=catalyst
        else print('TimeCatalyst unavailable: '..tostring(err)) end
    end
    nomi_.ignoreAimVolume=IsCombatVisualVolume
    CombatState.Configure({rig=combatRig_,weapon=combatRig_.active,aggro=CombatHasAggro,explicitSelection=true,
        cancel=function(reason)
            if weaponGesture_ and reason~='weapon' and reason~='attack' then weaponGesture_:Interrupt(reason) end
            if reason=='manual' or reason=='aggro' or reason=='quiet' or reason=='weapon' or reason=='attack' or reason=='loadout' then
                TouchControls.CancelActions()
            else TouchControls.Cancel() end
            combatInputBlocked=true
            caster_.charging,caster_.charge,caster_.castAnim=false,0,0
            if M.stream then M.stream:Stop(true) end
        end,
        changed=function(state)
            if state~=CombatState.EXPLORE then
                Safe('Audio.Preload',CombatAudio.Preload)
                fx_.handGlow,fx_.handAcc,fx_.handL.brightness=0,0,0
                fx_.handLight.enabled=false
                handMotes_:Clear(); handMotes_.handAcc=0
            end
        end,
        say=function(text) CombatHUD.Say(text,1.2) end})
    M.combatState=CombatState
    if M.trainingMode then
        M.nomi,M.nomiNode,M.dragonAwake=nomi_.nomi,nomi_.node,false
    else SetupDragon() end
    StartCombat()
    nomi_.onVoidReturn=function(pos)
        Training.leave()
        if weaponGesture_ then weaponGesture_:ForceClose('void') end
        CombatState.Exit('void')
        TouchControls.Cancel()
        caster_.charging,caster_.charge=false,0
        drag.buttons=0
        voidInputBlocked=true -- PC 仍物理按住的键必须松开，不能返回后自动施法/继续跑落崖
        if M.ride then
            M.ride.pos=pos
            M.ride.vy,M.ride.speed=0,0
        end
        if M.stream then M.stream:Stop(true) end
        caster_:Say("时之印记将你带回安全处")
    end
    local function ReturnUnderBlack() nomi_:ReturnFromVoid() end
    local function FinishVoidReturn()
        nomi_.voidReturning=false
        TouchControls.Cancel()
        -- Keep voidInputBlocked until held PC keys/buttons are released.
    end
    nomi_.onVoidFall=function(pos,forced)
        if not VoidRewind.CONFIG.enabled then return false end
        if not forced and (nomi_.cc.onGround or pos.y>=Terrain.RING_Y-VoidRewind.CONFIG.fallDepth
            or nomi_.cc:GetLinearVelocity().y>=-.1) then return false end
        if not VoidRewind.Start(ReturnUnderBlack,FinishVoidReturn) then return false end
        if SettingsMenu.IsOpen() then SettingsMenu.Close() end
        voidInputBlocked=true
        if weaponGesture_ then weaponGesture_:ForceClose('void') end
        TouchControls.Cancel()
        Safe('Touch.Sync',TouchControls.Sync)
        caster_.charging,caster_.charge=false,0
        drag.buttons=0
        if M.stream then M.stream:Stop(true) end
        return true
    end

    sleepBase.valid = false
    -- 龙体是纯视觉部件，不让瞄准 Grid 把它当成可破坏场景。
    for _, part in pairs(M.rig and M.rig.parts or {}) do
        if part.volume then part.volume.collisionLayer = 2; part.volume.collisionMask = 0 end
    end
    nomi_.aimMask = 0xffffffff & ~2
    HUD.Build(Spells.SPELLS)
    AttachTouchControls()
    Resources.attach()
    if M.trainingMode then
        M.trainingStation=Station.New(scene_,Training.position,Training.select,Training.clear)
        M.trainingStation.onOpenChanged=Training.openChanged
        M.trainingStation:SetNear(Training.near())
    end
    SetStage("gate")
    HUD.SetHint(resumeHint .. "  ·  M 地图 · F10 设置 · H 隐藏说明")
    if M.DEBUG_PANEL then M.ToggleDebugPanel() end

    SubscribeToEvent("BeginFrame", "Ruins_HandleGCBeginFrame")
    SubscribeToEvent("EndFrame", "Ruins_HandleGCEndFrame")
    SubscribeToEvent("Update", "Ruins_HandleUpdate")
    SubscribeToEvent("PostUpdate", "Ruins_HandlePostUpdate")
    SubscribeToEvent("SceneUpdate", "Ruins_HandleSceneUpdate")
    SubscribeToEvent("MouseButtonDown", "Ruins_HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "Ruins_HandleMouseUp")
    SubscribeToEvent("MouseMove", "Ruins_HandleMouseMove")
    SubscribeToEvent("MouseModeChanged", "Ruins_HandleMouseModeChanged")
    SubscribeToEvent("KeyDown", "Ruins_HandleKeyDown")
    SubscribeToEvent("InputFocus", "Ruins_HandleInputFocus")
    SubscribeToEvent("EnemyAttackCue", "Ruins_HandleEnemyAttackCue")
    RUINS = M
    M.scene, M.world, M.puzzles, M.nomiCtl, M.caster, M.fx = scene_, world_, Puzzles, nomi_, caster_, fx_
    print(string.format("RuinsScene: ready in %.2fs, volumes %d", GetTime():GetElapsedTime() - t0, world_:GetVolumeCount()))
end

-- 巨龙动画测试面板（隐藏，F10 打开；面板代码在 dragon/DragonDebugUI.lua）
function M.ToggleDebugPanel()
    if not M.ctrl or VoidRewind.IsActive() then return end
    if weaponGesture_ then weaponGesture_:ForceClose('debug') end
    M.debugOn = not M.debugOn
    pointer:SetBlocked(M.debugOn)
    if M.debugOn then
        local DebugUI = require("dragon.DragonDebugUI")
        DebugUI.Build(M.ctrl, M)
    else
        HUD.Build(Spells.SPELLS)
        AttachTouchControls()
        Resources.attach()
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
    if Training.blocked() then return end
    if M.housePanel and (M.housePanel.open or not mouseLocked) and not TouchInput.IsEnabled() then
        local k=PixelDraw.PixelToHUD()
        if eventData:GetInt('Button')==MOUSEB_LEFT and M.housePanel:Down('mouse',eventData:GetInt('X')*k,eventData:GetInt('Y')*k) then return end
        if M.housePanel.open then return end
    end
    if WorldMap.IsOpen() then
        local button=eventData:GetInt('Button')
        if not TouchInput.IsEnabled() and (button==MOUSEB_LEFT or button==MOUSEB_RIGHT) then
            local k=PixelDraw.PixelToHUD()
            WorldMap.Down(-button,eventData:GetInt('X')*k,eventData:GetInt('Y')*k,button==MOUSEB_LEFT and 'orbit' or 'pan')
        end
        return
    end
    if (weaponGesture_ and WeaponWheel.IsBlocked()) or voidInputBlocked or SettingsMenu.IsBlocked() or ForgePanel.IsOpen() or TouchInput.IsEnabled() then return end
    local button = eventData:GetInt("Button")
    if button ~= MOUSEB_LEFT and button ~= MOUSEB_RIGHT and button ~= MOUSEB_MIDDLE then return end
    -- 正常 HUD 全部是展示层；只有打开调试面板时才禁止玩法拖动。
    if M.debugOn then return end
    if not mouseLocked then
        drag.buttons = drag.buttons | (1 << button)
        drag.x, drag.y = eventData:GetInt("X"), eventData:GetInt("Y")
        drag.distance, drag.samples = 0, 0
        if DebugLog.enabled then DebugLog.Log("Ruins","RuinsInput: drag begin button=%d pos=%d,%d focus=%s", button, drag.x, drag.y, tostring(input.focus)) end
    end
    pointer:Resume()
end

---@param eventType string
---@param eventData MouseMoveEventData
function Ruins_HandleMouseMove(eventType, eventData)
    if Training.blocked() then return end
    if M.housePanel and (M.housePanel.open or M.housePanel.contact) then
        local k=PixelDraw.PixelToHUD();M.housePanel:Move('mouse',eventData:GetInt('X')*k,eventData:GetInt('Y')*k);return
    end
    if WorldMap.IsOpen() then
        if not TouchInput.IsEnabled() then
            local k=PixelDraw.PixelToHUD()
            local x,y=eventData:GetInt('X')*k,eventData:GetInt('Y')*k
            WorldMap.Move(-MOUSEB_LEFT,x,y);WorldMap.Move(-MOUSEB_RIGHT,x,y)
        end
        return
    end
    if (weaponGesture_ and WeaponWheel.IsBlocked()) or voidInputBlocked or SettingsMenu.IsBlocked() or ForgePanel.IsOpen() or TouchInput.IsEnabled() then return end
    if mouseLocked or M.debugOn or nomi_ == nil or drag.buttons == 0 then return end
    local x, y = eventData:GetInt("X"), eventData:GetInt("Y")
    local dx, dy = x - drag.x, y - drag.y
    drag.x, drag.y = x, y
    if dx == 0 and dy == 0 then return end
    if animPreview_.index>0 then
        animPreview_.orbit=Clamp((animPreview_.orbit or 0)+dx*.12,-25,25)
    else nomi_:Look(dx, dy, 0.12*combatLookScale_) end
    drag.distance = drag.distance + math.abs(dx) + math.abs(dy)
    drag.samples = drag.samples + 1
    if drag.samples == 1 then
        if DebugLog.enabled then DebugLog.Log("Ruins","RuinsInput: drag move delta=%d,%d yaw=%.2f", dx, dy, nomi_.camYaw) end
    end
end

---@param eventType string
---@param eventData MouseButtonUpEventData
function Ruins_HandleMouseUp(eventType, eventData)
    if Training.blocked() then return end
    if M.housePanel and not TouchInput.IsEnabled() then
        local k=PixelDraw.PixelToHUD()
        if eventData:GetInt('Button')==MOUSEB_LEFT and M.housePanel:Up('mouse',eventData:GetInt('X')*k,eventData:GetInt('Y')*k) then return end
        if M.housePanel.open then return end
    end
    if WorldMap.IsOpen() then
        if not TouchInput.IsEnabled() then
            local k=PixelDraw.PixelToHUD()
            WorldMap.Up(-eventData:GetInt('Button'),eventData:GetInt('X')*k,eventData:GetInt('Y')*k)
        end
        return
    end
    if (weaponGesture_ and WeaponWheel.IsBlocked()) or SettingsMenu.IsBlocked() or ForgePanel.IsOpen() then return end
    if TouchInput.IsEnabled() then return end
    local button = eventData:GetInt("Button")
    local bit = 1 << button
    if drag.buttons & bit == 0 then return end
    drag.buttons = drag.buttons & (~bit)
    if DebugLog.enabled then DebugLog.Log("Ruins","RuinsInput: drag end samples=%d distance=%d", drag.samples, drag.distance) end
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
    local mapKey=eventData:GetInt('Key')
    local repeated=eventData:GetBool('Repeat')
    local station=M.trainingStation
    if station then
        if station:HandleKey(mapKey,repeated) or Training.blocked() then return end
    end
    if mapKey==KEY_F and not TouchInput.IsEnabled() then
        local target=Resources.nearest()
        if target then
            if not repeated then Resources.interact(target) end
            return
        elseif station and Training.near() then
            if not repeated then station:SetNear(true);station:Interact() end
            return
        end
    end
    if combatTest_ and combatTest_.active and eventData:GetInt('Key')~=KEY_F11 then
        Safe('Debug.F11Stop',combatTest_.Stop,combatTest_,'key') -- deliberately continue dispatching the original key
    end
    if M.housePanel and (M.housePanel.open or mapKey==KEY_J) and M.housePanel:Key(mapKey,eventData:GetBool('Repeat')) then return end
    if WorldMap.IsOpen() then
        if not eventData:GetBool('Repeat') then WorldMap.Key(mapKey) end
        return
    end
    if mapKey==KEY_M then
        if not eventData:GetBool('Repeat') then OpenWorldMap() end
        return
    end
    if weaponGesture_ and WeaponWheel.IsBlocked() and eventData:GetInt("Key")~=KEY_F10 then return end
    if ForgePanel.IsOpen() then return end -- ForgePanel owns Escape and its release latch.
    local menuKey=eventData:GetInt("Key")
    if menuKey==KEY_F10 and not M.DEBUG_PANEL then
        if not eventData:GetBool("Repeat") and not voidInputBlocked then SettingsMenu.Toggle() end
        return
    end
    if menuKey==KEY_B and OnFoot() then
        if eventData:GetBool('Repeat') then return end
        if SettingsMenu.IsBagOpen() then SettingsMenu.Close()
        elseif not SettingsMenu.IsBlocked() and not SettingsMenu.Open('bag') then
            CombatHUD.Say('请脱离警戒并回到地面，再打开背包',1.5)
        end
        return
    end
    if SettingsMenu.IsOpen() then
        SettingsMenu.Key(menuKey,repeated)
        return
    end
    if SettingsMenu.IsBlocked() then return end
    if TouchInput.IsEnabled() then return end
    local key = eventData:GetInt("Key")
    if key == KEY_ESCAPE then
        pointer:Release("escape")
    elseif key == KEY_E or key == KEY_R or key == KEY_Q or key == KEY_W or key == KEY_A or key == KEY_S or key == KEY_D then
        pointer:Resume()
    end
end

---@param eventType string
---@param eventData InputFocusEventData
function Ruins_HandleInputFocus(eventType, eventData)
    if not eventData:GetBool("Focus") or eventData:GetBool("Minimized") then
        if M.trainingStation then M.trainingStation:SetNear(false) end
        Resources.prompt.Clear()
        if M.housePanel then M.housePanel:Close() end
        if WorldMap.IsOpen() then WorldMap.CancelPointers() end
        if combatTest_ and combatTest_.active then Safe('Debug.F11Stop',combatTest_.Stop,combatTest_,'focus') end
        combatInputBlocked=true
        if weaponGesture_ then weaponGesture_:ForceClose('focus') end
        if combatMoves_ and not combatMoves_.dead and combatMoves_.clip~='getup' then combatMoves_:Cancel('focus') end
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
-- Temporary PC-only controls; the settings task owns future menu entries.
local function DebugPointClear(pos)
    for _,height in ipairs({.4,1.0,1.7}) do
        local center=pos+Vector3(0,height,0)
        for _,axis in ipairs({Vector3(1,0,0),Vector3(0,0,1)}) do
            if CombatCast(center-axis*.4,center+axis*.4) then return false end
        end
    end
    return true
end
-- Debug-only measurements use character-owned sockets, never an assumed
-- shoulder-to-hand vector. Gameplay and shared socket transforms are untouched.
local function AppendHandDebug(lines,character,sample,legacy)
    local body=character.bones.body
    local targets=0
    for _,side in ipairs({'right','left'}) do
        local name='arm_'..side
        local result=sample and sample[name]
        local label=side=='right' and '右' or '左'
        if not legacy and result and result.target then
            local target=result.target
            targets=targets+1
            lines[#lines+1]=string.format('%s握点目标 (%.3f, %.3f, %.3f)m',label,target.x or target[1],target.y or target[2],target.z or target[3])
        end
        local palm=character:HandSocket(side)
        if body and palm then
            local actual=body:WorldToLocal(palm.worldPosition)
            lines[#lines+1]=string.format('%s握点实际 (%.3f, %.3f, %.3f)m',label,actual.x,actual.y,actual.z)
            local shoulder=character.bones[name]
            local elbow=character.bones['forearm_'..side]
            if shoulder and elbow then
                local at=body:WorldToLocal(elbow.worldPosition)
                local upper=(elbow.worldPosition-shoulder.worldPosition):Length()
                local lower=(palm.worldPosition-elbow.worldPosition):Length()
                lines[#lines+1]=string.format('%s肘 (%.3f, %.3f, %.3f)m',label,at.x,at.y,at.z)
                lines[#lines+1]=string.format('%s骨长 上臂%.3fm / 前臂%.3fm',label,upper,lower)
            elseif shoulder then
                lines[#lines+1]=string.format('%s单段臂长 %.3fm',label,(palm.worldPosition-shoulder.worldPosition):Length())
            end
        end
    end
    if targets==0 then lines[#lines+1]=legacy and '旧轨道对比：不显示残留IK目标' or '此片段未提供握点轨迹' end
end
local function DebugTransfer()
    if animPreview_.index>0 then CombatHUD.Say('先退出 F7 动画预览'); return end
    local index=debugDestination_%3+1
    local pos,anchor,label=CombatMoves.DebugDestination(combatEnemies_:GetEnemies(),Terrain,index,DebugPointClear)
    if not pos then CombatHUD.Say('没有找到安全传送点：'..label); return end
    combatMoves_:Cancel('debug-transfer'); combatArrows_:Clear(); TouchControls.Cancel()
    caster_.charging,caster_.charge,caster_.castAnim=false,0,0
    drag.buttons=0; combatInputBlocked,voidInputBlocked=true,true
    local yaw=math.deg(math.atan(anchor.x-pos.x,anchor.z-pos.z))
    if not nomi_:TeleportForCombatDebug(pos,yaw) then return end
    M.ride.pos=pos; M.ride.vy,M.ride.speed=0,0
    combatMoves_.invuln=math.max(combatMoves_.invuln,1)
    debugDestination_=index
    combatDebugText_,combatDebugUntil_='传送：'..label,time_+4
    print(string.format('Combat: debug teleport %s pos=(%.2f,%.2f,%.2f)',label,pos.x,pos.y,pos.z))
end
local function ToggleTrainingDummy()
    if trainingDummy_ then
        trainingDummy_:Destroy(); trainingDummy_=nil
        combatMoves_.target=nil
        CombatHUD.Say('训练木桩已移除'); return
    end
    local forward=nomi_.node.worldDirection
    local at=nomi_:Position()+Vector3(forward.x,0,forward.z):Normalized()*3
    local y=Terrain.GroundHeight(at.x,at.z)
    if not y or not Terrain.IsSafeGround(at.x,y,at.z) or not DebugPointClear(Vector3(at.x,y+.1,at.z)) then
        CombatHUD.Say('前方3米没有安全空地'); return
    end
    local pos=Vector3(at.x,y,at.z)
    local node=scene_:CreateChild('CombatTrainingDummy')
    node.position=pos+Vector3(0,.9,0); node.scale=Vector3(.75,1.8,.5)
    local model=node:CreateComponent('StaticModel')
    model:SetModel(cache:GetResource('Model','Models/Box.mdl'))
    local material=Material:new()
    material:SetTechnique(0,cache:GetResource('Technique','Techniques/PBR/PBRNoTexture.xml'))
    material:SetShaderParameter('MatDiffColor',Variant(Color(.45,.27,.12,1)))
    material:SetShaderParameter('Roughness',Variant(.95))
    model:SetMaterial(material); model.castShadows=true
    trainingDummy_=CombatMoves.NewTrainingDummy(pos,node)
    CombatHUD.Say('训练木桩 · 点按 Tab 切换 / 长按 Tab 选择')
end
local function StartCombatTest()
    if combatTest_ and combatTest_.active then return end
    if animPreview_.index>0 or CombatState.HasAggro() or not nomi_:CanSlide() then
        print('CombatTest: BEGIN FAIL leave F7/aggro and stand on safe ground'); return
    end
    local owned=trainingDummy_==nil
    if owned then Safe('Debug.F9',ToggleTrainingDummy) end
    if not trainingDummy_ then print('CombatTest: BEGIN FAIL no safe dummy location'); return end
    local origin=nomi_:Position()
    local safe,yaw,pitch=nomi_.safePos,nomi_.camYaw,nomi_.camPitch
    local weapon,wasCombat=CombatState.GetWeapon(),CombatState.InCombat()
    local forward=Vector3(nomi_.node.worldDirection.x,0,nomi_.node.worldDirection.z):Normalized()
    local rotation=Quaternion(math.deg(math.atan(forward.x,forward.z)),Vector3.UP)
    combatTest_=CombatTest.New({moves=combatMoves_,dummy=trainingDummy_,position=function() return nomi_:Position() end,
        direction=function(axis) return rotation*axis end,
        prepare=function(step)
            combatArrows_:Clear(); TouchControls.Cancel()
            local point=step.axis and origin or trainingDummy_.position-forward*(step.weapon=='bow' and 3 or 1.35)
            local y=Terrain.GroundHeight(point.x,point.z)
            if not y then return false end
            point=Vector3(point.x,y+.1,point.z)
            if not Terrain.IsSafeGround(point.x,point.y,point.z) or not DebugPointClear(point) then return false end
            if not nomi_:TeleportForCombatDebug(point,math.deg(math.atan(forward.x,forward.z))) then return false end
            CombatState.Enter('selftest'); CombatState.SetBusy(false); CombatState.FinishTransition()
            CombatState.SetWeapon(step.weapon); CombatState.FinishTransition(); CombatState.Activity(true)
            combatRig_:SetActive(step.weapon); combatRig_:SetPose('hand')
            combatMoves_.hitstop=0
            combatInputBlocked=false
            return true
        end,
        cleanup=function(reason)
            combatArrows_:Clear(); TouchControls.Cancel()
            if owned and trainingDummy_ then trainingDummy_:Destroy(); trainingDummy_=nil end
            combatMoves_.target=nil
            CombatState.SetBusy(false); CombatState.FinishTransition(); CombatState.SetWeapon(weapon); CombatState.FinishTransition()
            if not wasCombat and not CombatState.HasAggro() then CombatState.Exit('selftest-end') end
            if reason=='complete' and not CombatState.HasAggro() then nomi_:TeleportForCombatDebug(origin,yaw); nomi_.camPitch=pitch end
            nomi_.safePos=safe
            combatInputBlocked=true
        end})
end
local function HandleCombatDebugKeys(allowed)
    if not allowed or TouchInput.IsEnabled() or PlatformUtils.IsMobilePlatform() then return end
    if Press(KEY_F2) then
        local on=not CombatState.GetSetting('cameraShake')
        CombatState.SetSetting('cameraShake',on); CombatHUD.Say('镜头震动 · '..(on and '开' or '关'))
    end
    if Press(KEY_F3) then
        local on=not CombatState.GetSetting('cameraFov')
        CombatState.SetSetting('cameraFov',on); CombatHUD.Say('动作镜头 / FOV · '..(on and '开' or '关'))
    end
    if Press(KEY_F6) then
        local on=not CombatState.GetSetting('aimAssist')
        CombatState.SetSetting('aimAssist',on)
        CombatHUD.Say('辅助瞄准 · '..(on and '开' or '关'),1.2)
    end
    if Press(KEY_F5) then
        local on=not CombatState.GetSetting('damageNumbers')
        CombatState.SetSetting('damageNumbers',on)
        CombatHUD.Say('伤害数字 · '..(on and '开' or '关'),1.2)
    end
    if M.trainingMode then return end
    if Press(KEY_F11) then Safe('Debug.F11',StartCombatTest) end
    if Press(KEY_F8) then Safe('Debug.F8',DebugTransfer) end
    if Press(KEY_F9) and not Down(KEY_SHIFT) then Safe('Debug.F9',ToggleTrainingDummy) end
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
local aimTextCache={}
local AIM_STATE_NAMES={WHOLE="完整",SHATTERED="破碎中",FROZEN="已碎",REWIND="回溯中"}
local enemyAimHits,enemyAimPool,enemyAimShapes={},{},{}
local function UpdateAim(presentation)
    local aim = nomi_:Aim(60.0)
    if CombatState.InCombat() or CombatState.GetSelection()=='time' then
        local cam=nomi_:CameraNode()
        local a,b=cam.worldPosition,cam.worldPosition+cam.worldDirection*60
        local enemyHits=Hit.QueryZone(CombatEnemies(),{origin=a,source=a,forward=cam.worldDirection,
            radius=1.2,angle=40,low=-1.2,high=2.8},enemyAimHits,enemyAimPool,nil,enemyAimShapes)
        local enemy=enemyHits[1] and enemyHits[1].enemy or nil
        aim.enemy=enemy
        if enemy and enemyHits[1] then
            aim.hit=true;aim.pos=enemyHits[1].pos;aim.normal=enemyHits[1].normal
        end
    end
    if aim.hit then aim.object = aim.object or Puzzles.FindByVolume(aim.volume) end
    M.aim = aim
    if presentation==false then return aim end
    if CombatState.InCombat() then
        M.gateHoverTarget=0
        HUD.SetTarget('')
        return aim
    end
    local obj = aim.object --[[@as TimeObject?]]
    if DebugLog.enabled then
    local signature = obj and (obj.id .. ":" .. obj.state) or (aim.breakable and "breakable" or "none")
    if signature ~= M.lastAimSignature or time_ >= (M.nextAimLog or 0) then
        M.lastAimSignature = signature
        M.nextAimLog = time_ + 3
        local volume = aim.volume --[[@as VoxelVolume?]]
        local node = volume and volume:GetNode()
        DebugLog.Log("RuinsAim","target=%s assisted=%s origin=%s dir=%s hit=%s distance=%.3f volume=%s id=%s layer=%s voxel=%s player=%s yaw=%.2f pitch=%.2f",
            signature, tostring(aim.assisted == true), tostring(aim.origin), tostring(aim.dir), tostring(aim.pos),
            aim.distance or -1, node and node.name or "none", tostring(aim.volumeId),
            volume and tostring(volume.collisionLayer) or "none", tostring(aim.voxel),
            tostring(nomi_:Position()), nomi_.camYaw, nomi_.camPitch)
    end
    end -- opt-in aim diagnostics
    local gateAimed = obj == nil and aim.hit and aim.breakable and aim.volume == Puzzles.gateRubble
    M.gateHoverTarget = gateAimed and 1 or 0
    if obj ~= nil then
        obj.hoverTarget = 1
        -- 蓄力碎时或物件完整（只能碎）时为红；已碎可回溯时为黄
        local rewindable = obj.canRewind and (obj.state == "SHATTERED" or obj.state == "FROZEN")
        obj.hoverColor = (caster_.charging or not rewindable) and Spells.SHATTER_COLOR or Spells.REWIND_COLOR
        local label=obj.title or obj.id
        local c=aimTextCache
        if c.object~=obj or c.state~=obj.state or c.label~=label or c.rubble~=obj.rubble
            or c.shatter~=obj.canShatter or c.rewind~=obj.canRewind then
            c.object,c.state,c.label,c.rubble,c.shatter,c.rewind=obj,obj.state,label,obj.rubble,obj.canShatter,obj.canRewind
            local st=AIM_STATE_NAMES[obj.state] or ""
            if obj.state=="FROZEN" and not obj.rubble then st="冻结" end
            local actions=(obj.canShatter and "  [左键 碎时]" or "")..(obj.canRewind and "  [R 回溯]" or "")
            c.text=string.format("◆ %s · %s%s",label,st,actions)
        end
        HUD.SetTarget(c.text,obj)
    elseif aim.hit and aim.breakable then
        HUD.SetTarget(aim.volume == Puzzles.gateRubble and "◇ 碎石堆 · 左键碎时" or "◇ 可破坏 · 左键碎时", true)
    else
        HUD.SetTarget("")
    end
    return aim
end

local function HandleSpells(dt, aim)
    if foot_ and foot_:IsSprinting() then
        caster_.charging,caster_.charge,caster_.castAnim=false,0,0
        TouchInput.CancelAction('shatter')
        return
    end
    -- F7 owns number keys and pointer input; do not emit rejected-spell banners.
    if animPreview_.index>0 or M.mounted or voidInputBlocked then caster_.charging,caster_.charge=false,0; return end
    if not CombatState.CanUseTime() then
        caster_.charging,caster_.charge=false,0
        return
    end
    if combatInputBlocked then caster_.charging,caster_.charge=false,0; return end
    local testInput = M.fake ~= nil or M.fakePress ~= nil
    if not input.focus or input.minimized or WeaponWheel.IsBlocked() or ForgePanel.IsOpen() or SettingsMenu.IsBlocked()
        or M.debugOn or TouchControls.IsBlocked() or (not TouchInput.IsEnabled() and not pointer:IsEnabled() and not testInput) then
        caster_.charging,caster_.charge=false,0; return
    end
    if Press(KEY_E) then caster_:Cast('freeze',aim) end
    if Press(KEY_R) then caster_:Cast('rewind',aim) end
    local armed=CombatState.InCombat()
    if Press(KEY_Q) and time_>=(M.weaponSkillReadyAt or 0) then
        if armed then
            if combatMoves_:Action('heavy') then M.weaponSkillReadyAt=time_+4 end
        elseif caster_:Ready('shatter') then
            caster_.charge=1
            caster_:Cast('shatter',aim)
            caster_.charging,caster_.charge=false,0
            M.weaponSkillReadyAt=time_+4
        end
        return
    end
    if armed then caster_.charging,caster_.charge=false,0;return end
    local held=(M.fake and M.fake.shatter) or (not TouchInput.IsEnabled() and pointer:CanAttack() and input:GetMouseButtonDown(MOUSEB_LEFT)) or TouchInput.Down('shatter')
    if TouchInput.Press('shatter') and not held then caster_:HandleCharge(true,aim,true) end
    caster_:HandleCharge(held,aim,true)
end

-- Keyboard walk/run toggle (Ctrl). Default is run; Shift is the faster sprint.
M.walkMode=false

function Ruins_HandleSceneUpdate(eventType, eventData)
    -- 角色意图在物理步进之前写入（见 voxel-physics.md 铁规 1）
    local dt = eventData["TimeStep"]:GetFloat()
    if nomi_ == nil then return end
    if M.mounted or not OnFoot() then
        nomi_:SetPlayerTimeScale(1,dt)
        nomi_:ResetJump()
        if foot_ then foot_:Cancel('mounted') end
        return
    end
    if Training.blocked() then
        nomi_:SetPlayerTimeScale(1,dt)
        nomi_:Move(dt,0,0,false,false,false,{scale=0,motion=Vector3.ZERO,playerTimeScale=1})
        return
    end
    local playerTimeScale=PlayerTimeScale(nomi_:Position())
    nomi_:SetPlayerTimeScale(playerTimeScale,dt)
    nomi_:MeasureMotion(dt)
    local allowed=GameplayInputAllowed()
    if allowed and not combatInputBlocked and (Press(KEY_LCTRL) or Press(KEY_RCTRL) or Press(KEY_CTRL)) then
        M.walkMode=not M.walkMode
        CombatHUD.Say(M.walkMode and '步行' or '奔跑',1.0)
    end
    local f = (Down(KEY_W) and 1 or 0) - (Down(KEY_S) and 1 or 0)
    local r = (Down(KEY_D) and 1 or 0) - (Down(KEY_A) and 1 or 0)
    local tf,tr=TouchInput.MoveAxis()
    f,r=Clamp(f+tf,-1,1),Clamp(r+tr,-1,1)
    if animPreview_.index>0 then
        if foot_ then foot_:Cancel('preview') end
        nomi_:Move(dt,0,0,false,false,false,{scale=0,motion=Vector3.ZERO}); return
    end
    if combatMoves_ then
        local touch=TouchInput.IsEnabled()
        local attack=TouchInput.Down('attack') or (not touch and pointer:CanAttack() and input:GetMouseButtonDown(MOUSEB_LEFT))
        local heavy=TouchInput.Down('heavy') or (not touch and pointer:CanAttack() and input:GetMouseButtonDown(MOUSEB_RIGHT))
        local angle=math.rad(nomi_.camYaw)
        local axis=Vector3(math.sin(angle)*f+math.cos(angle)*r,0,math.cos(angle)*f-math.sin(angle)*r)
        if animPreview_.index==0 then
            local controls=combatControls
            controls.allowed,controls.selecting=allowed and not combatInputBlocked,weaponGesture_ and weaponGesture_:IsOpen()
            controls.attack,controls.heavy=attack,heavy
            controls.attackTap,controls.heavyTap=TouchInput.Press('attack') and not attack,TouchInput.Press('heavy') and not heavy
            local keyHeld=M.fake and M.fake[KEY_SHIFT]
            if keyHeld==nil then keyHeld=input:GetKeyDown(KEY_SHIFT) end
            local keyPress=input:GetKeyPress(KEY_SHIFT)
            if M.fakePress and M.fakePress[KEY_SHIFT] then keyPress=true;M.fakePress[KEY_SHIFT]=nil end
            TouchInput.SampleRun(controls,keyHeld,M.walkMode)
            -- Charging / casting slows to a walk unless the sprint key is held.
            if (caster_.charging or caster_.castAnim>0) and not controls.sprintIntent then controls.runIntent=false end
            controls.cancelled=(keyHeld or keyPress) and input:GetKeyDown(KEY_F9) -- debug chord consumes gesture first
            controls.axis=axis
            controls.jump=allowed and not combatInputBlocked and Press(KEY_SPACE)
            controls.onGround,controls.actualSpeed=nomi_.cc.onGround,nomi_.actualSpeed
            controls.travel,controls.motionSampleDt=nomi_.frameTravel,nomi_.actualDt
            controls.actualForwardSpeed=foot_ and foot_.direction and nomi_.actualVelocity:DotProduct(foot_.direction) or nil
            controls.normalSpeed=CombatState.Engaged() and 5 or 4.2
            controls.playerTimeScale=playerTimeScale
            if combatTest_ and combatTest_.active then
                local testOK,synthetic=Safe('Debug.F11Input',combatTest_.Input,combatTest_,dt,allowed and not CombatState.HasAggro() and not ForgePanel.IsOpen() and not SettingsMenu.IsBlocked())
                if synthetic then
                    synthetic.inputRevision,synthetic.onGround=controls.inputRevision,controls.onGround
                    synthetic.normalSpeed=controls.normalSpeed
                    controls=synthetic; f,r=0,0
                end
                if not testOK then
                    Safe('Debug.F11Stop',combatTest_.Stop,combatTest_,'input-error')
                    combatTest_.active=false;controls.allowed=false
                end
            end
            if not Safe('Combat.Moves',combatMoves_.Update,combatMoves_,dt,controls) then
                -- Do not repeat a stale lunge/hit window while moves are disabled.
                combatMoves_.motion=Vector3.ZERO
                combatMoves_.hitOpen,combatMoves_.hitPending=false,false
            end
        end
        if foot_ or CombatState.InCombat() or combatMoves_.dead or combatMoves_.clip=='getup' then
            local options=combatMoveOptions
            options.jumpAllowed=allowed and not combatInputBlocked and not combatMoves_.dead
            options.scale=allowed and not combatMoves_.motionChecked and combatMoves_:MoveScale() or 0
            options.motion=allowed and combatMoves_.motion or Vector3.ZERO
            options.explore=not CombatState.InCombat()
            local aiming=combatMoves_.clip=='bow_draw' or combatMoves_.clip=='bow_hold'
                or (options.explore and (caster_.charging or caster_.castAnim>0))
            options.baseSpeed=options.explore and (aiming and 4.2*.6 or 4.2) or 5
            options.playerTimeScale=playerTimeScale
            options.sprinting=foot_ and foot_:IsRunning()
            options.fast=foot_ and foot_:IsSprinting()
            options.facing,options.motionChecked=combatMoves_:Facing(),combatMoves_.motionChecked
            nomi_:Move(dt,allowed and f or 0,allowed and r or 0,allowed and not combatInputBlocked and combatControls.runIntent==true,
                combatControls.jump,
                aiming,options)
            return
        end
    end
    if not allowed or animPreview_.index>0 then nomi_:Move(dt,0,0,false,false,false,{scale=0}); return end
    nomi_:Move(dt, f, r, false, Press(KEY_SPACE), caster_.charging or caster_.castAnim > 0,
        {playerTimeScale=playerTimeScale})
end

local function UpdateCombatPreview(dt,combatAllowed)
    local previewAllowed=combatAllowed and not TouchInput.IsEnabled() and not PlatformUtils.IsMobilePlatform()
    local previewNext=previewAllowed and
        (Press(KEY_RIGHTBRACKET) or Press(KEY_RIGHT))
    local previewPrevious=previewAllowed and
        (Press(KEY_LEFTBRACKET) or Press(KEY_LEFT))
    local previewCycle=previewAllowed and Press(KEY_F7)
    if previewCycle or (animPreview_.index>0 and (previewNext or previewPrevious)) then
        local list=CombatAnim.DebugList()
        if previewCycle then animPreview_.index=(animPreview_.index+1)%(#list+1)
        else animPreview_.index=(animPreview_.index-1+(previewNext and 1 or -1))%#list+1 end
        animPreview_.view=animPreview_.view or 4; animPreview_.orbit=0
        animPreview_.t=0; animPreview_.text=nil; animPreview_.paused=false; animPreview_.events='—'
        combatMoves_:Cancel('animation-preview'); TouchControls.Cancel()
        combatArrows_:Clear()
        if animPreview_.index>0 then
            CombatState.Enter('preview')
            local clip=list[animPreview_.index]
            combatRig_:SetActive(clip.weaponType or CombatState.GetWeapon()); combatRig_:SetPose(animPreview_.params.weaponInHand==0 and 'back' or 'hand')
            combatAnim_:Play(clip.id,{fadeIn=0,params=animPreview_.params})
        else
            CombatState.Exit('preview-end'); combatRig_:SetActive(CombatState.GetWeapon())
            combatInputBlocked=true -- wait for held preview keys to release
        end
    end
    if animPreview_.index>0 then
        local clip=CombatAnim.DebugList()[animPreview_.index]
        if previewAllowed and Press(KEY_SPACE) then animPreview_.paused=not animPreview_.paused end
        CombatState.SetBusy(true)
        local params=animPreview_.params
        if params.weaponInHand==nil then params.weaponInHand=1 end
        params.aimPitch=Clamp(nomi_.camPitch,-35,35)
        if previewAllowed then
            for i,key in ipairs({KEY_1,KEY_2,KEY_3,KEY_4}) do
                if Press(key) then animPreview_.view,animPreview_.orbit=i,0 end
            end
        end
        local changed=false
        if previewAllowed and Press(KEY_O) then
            params.weaponInHand=params.weaponInHand==1 and 0 or 1;changed=true
        end
        combatRig_:SetPose(params.weaponInHand==1 and 'hand' or 'back')
        combatAnim_:SetParam('weaponInHand',params.weaponInHand)
        if previewAllowed and Press(KEY_P) then
            params.legacyPose=params.legacyPose==1 and 0 or 1; changed=true
        end
        if previewAllowed and clip.id=='bow_hold' then
            if Press(KEY_EQUALS) or Press(KEY_PLUS) or Press(KEY_KP_PLUS) then params.p=math.min(1,params.p+.1); changed=true end
            if Press(KEY_MINUS) or Press(KEY_KP_MINUS) then params.p=math.max(0,params.p-.1); changed=true end
        end
        local step=0
        if animPreview_.paused and previewAllowed then
            if Press(KEY_COMMA) then step=-1/30 elseif Press(KEY_PERIOD) then step=1/30 end
        end
        if step~=0 or changed then
            animPreview_.t,animPreview_.events=CombatMoves.SeekPreview(combatAnim_,clip.id,animPreview_.t+step,animPreview_.t,params)
        elseif not animPreview_.paused and combatAllowed then
            local previewDt=dt
            animPreview_.t=animPreview_.t+dt
            if animPreview_.t>=clip.dur+.35 then
                combatAnim_:Stop(nil,0); combatAnim_:Poll()
                combatAnim_:Play(clip.id,{fadeIn=0,params=params}); animPreview_.t=0
                previewDt=0
            end
            combatAnim_:SetParam('p',(clip.id=='bow_hold' or clip.id=='bow_release' or clip.id=='bow_cancel') and params.p or math.min(1,animPreview_.t/math.max(.01,clip.dur)))
            combatAnim_:Update(previewDt,previewDt)
            animPreview_.events=CombatMoves.PreviewEvents(combatAnim_:Poll(),-1,math.huge)
        else
            -- Apply has a base-animation-clock fallback. Explicit zero advance
            -- is required every paused/unfocused frame to keep the pose frozen.
            combatAnim_:Update(0,0)
        end
        animPreview_.text=string.format('F7 %s / %.3f / %s%s\n事件：%s\n空格 暂停 · , / . 逐帧 · 左右 切片段',clip.id,animPreview_.t,
            CombatMoves.PreviewPhase(clip.id,animPreview_.t),animPreview_.paused and ' · 暂停' or '',animPreview_.events or '—')
        animPreview_.text=animPreview_.text..string.format('\nIJKL 方向:%s · B:%s · +/- 拉弓:%.1f',animPreview_.direction,params.bow==1 and '弓' or '剑',params.p)..(params.weaponInHand==1 and ' · O 持手' or ' · O 背挂')
        animPreview_.text=animPreview_.text..'\nP 对比：'..(params.legacyPose==1 and '旧骨骼轨道 / IK关闭' or '路径驱动 / IK开启')
    end
end

local function UpdateCombatActions(combatAllowed,dt)
    -- External interruptions are independent of the wheel's own blocker.
    if weaponGesture_ and weaponGesture_:IsOpen() then
        if not weaponGesture_.o.canOpen() then weaponGesture_:ForceClose('interrupted')
        elseif not weaponGesture_.touch and not Down(KEY_TAB) then weaponGesture_:Confirm() end
        return
    end
    if weaponGesture_ and weaponGesture_.pending then
        weaponGesture_:UpdatePress(dt,Down(KEY_TAB),combatAllowed and not combatInputBlocked)
        return
    end
    if combatAllowed and animPreview_.index==0 and not combatMoves_.dead then
        if Press(KEY_G) or TouchInput.Press('forge') then OpenForge();return end
        if timeCatalyst_ and Press(KEY_5) then
            local mode=TimeCatalyst.SetFxMode(timeCatalyst_)
            CombatHUD.Say('法器特效 · '..(({pixel='像素粒子',off='关闭'})[mode] or tostring(mode))..'（5 切换）',1.4)
        end
        if not combatInputBlocked and Press(KEY_C) then
            combatMoves_:SelectLoadout(CombatState.InCombat() and 'time' or CombatState.GetWeapon())
        end
        if not combatInputBlocked then
            local touchSwap=TouchInput.Press('swap') or TouchInput.Press('sheath')
            if touchSwap then weaponGesture_:Open(true)
            elseif Press(KEY_TAB) then weaponGesture_:BeginPress()
            elseif Press(KEY_1) then combatMoves_:SelectLoadout('sword')
            elseif Press(KEY_2) then combatMoves_:SelectLoadout('bow')
            elseif Press(KEY_3) then combatMoves_:SelectLoadout('time') end
        end
    end
end

local function UpdateCombatPreviewText()
    if animPreview_.index>0 then
        local clip=CombatAnim.DebugList()[animPreview_.index]
        local legacy=animPreview_.params.legacyPose==1
        local sample=not legacy and combatAnim_.GetIKDebug and combatAnim_:GetIKDebug(clip.id) or nil
        if not sample and not legacy then
            local sampled=CombatAnim.DebugSample(clip.id,clip.id=='bow_hold' and animPreview_.params.p or animPreview_.t,animPreview_.params)
            sample=sampled and sampled._ik
        end
        local lines={animPreview_.text or '', '1 前 / 2 侧 / 3 背 / 4 斜 · 距离2.6m · 鼠标微调'}
        local audioLoaded,audioTotal=CombatAudio.PreloadProgress()
        lines[#lines+1]=string.format('音频预加载 %d/%d',audioLoaded,audioTotal)
        AppendHandDebug(lines,nomi_.nomi,sample,legacy)
        if foot_ and clip.id=='sprint_loop' and foot_.soles then
            local hip=nomi_.nomi.bones.body.worldPosition
            lines[#lines+1]=string.format('髋Y %.3f · root修正 %+.3fm · 支撑 %s',hip.y,foot_.groundDelta or 0,foot_.phase<.5 and '右' or '左')
            for i,sole in ipairs(foot_.soles) do
                lines[#lines+1]=string.format('%s%d 脚Y %.3f / 地Y %.3f',i<=4 and '右' or '左',(i-1)%4+1,sole.world.y,sole.ground or 0)
            end
        end
        animPreview_.text=table.concat(lines,'\n')
    end
end

local function UpdateCombatAnimationParams()
    local p,pitch=combatMoves_:BowParameters(nomi_.camPitch)
    Safe('Animation.Params',combatAnim_.SetParam,combatAnim_,'weaponInHand',combatMoves_:WeaponInHand() and 1 or 0)
    Safe('Animation.Params',combatAnim_.SetParam,combatAnim_,'aimPitch',pitch)
    Safe('Animation.Params',combatAnim_.SetParam,combatAnim_,'p',p)
    if foot_ and animPreview_.index==0 then
        if foot_.weight>0 and not combatAnim_:IsPlaying('sprint_loop') then
            local params=foot_.animOpts.params
            params.weaponInHand=combatMoves_:WeaponInHand() and 1 or 0
            params.sprintWeight,params.gaitPhase=foot_.weight,foot_.phase
            params.sprintAccel,params.bow=1,CombatState.GetWeapon()=='bow' and 1 or 0
            foot_.animHandle=combatAnim_:Play('sprint_loop',foot_.animOpts)
        end
        if foot_.weight<=0 and combatAnim_:IsPlaying('sprint_loop') then combatAnim_:Stop(foot_.animHandle,.04);foot_.animHandle=nil end
        combatAnim_:SetParam('sprintWeight',foot_.weight)
        combatAnim_:SetParam('gaitPhase',foot_.phase)
        combatAnim_:SetParam('sprintAccel',1)
        combatAnim_:SetParam('bow',CombatState.GetWeapon()=='bow' and 1 or 0)
    elseif animPreview_.index>0 then
        combatAnim_:SetParam('sprintWeight',1)
        combatAnim_:SetParam('gaitPhase',animPreview_.t/.38)
        combatAnim_:SetParam('sprintAccel',1)
    end
end

local function UpdateCombatRig(dt)
    if combatRig_ then
        if combatRig_.SetBowDraw then
            local p=(combatMoves_.clip=='bow_draw' or combatMoves_.clip=='bow_hold') and combatMoves_.charge or 0
            if combatMoves_.pendingFire then p=combatMoves_.pendingFire.u end
            if animPreview_.index>0 then
                local id=CombatAnim.DebugList()[animPreview_.index].id
                p=(id=='bow_hold' or id=='bow_draw') and animPreview_.params.p or 0
            end
            combatRig_:SetBowDraw(p)
        end
        local offset,euler=combatAnim_:GetWeaponPose()
        combatRig_:SetSwing(offset,euler)
        if combatRig_.SetTrail then combatRig_:SetTrail(not combatLowQuality_ and (CombatState.InCombat() or animPreview_.index>0)) end
        if combatRig_.SetCombatVisual then
            combatRig_:SetCombatVisual(CombatState.GetWeapon()=='sword' and (combatMoves_.hitOpen or combatMoves_.hitPending),nil)
        end
        combatRig_:SetAfterimages(combatLowQuality_ and emptyAfterimages_ or combatAnim_:GetAfterimages())
        Safe('Rig.Update',combatRig_.Update,combatRig_,dt)
        if combatRig_.PopEvents then
            for _,event in ipairs(combatRig_:PopEvents() or {}) do
                local name=type(event)=='string' and event or event.name
                if name=='blade_draw' or name=='blade_sheath' then
                    Safe('Audio.Play',CombatState.PerfCall,'audio',CombatAudio.Play,name,{pos=nomi_:Position()})
                    if not combatRig_.ArrivalFlash and combatRig_.Flash then combatRig_:Flash(name=='blade_draw' and 'draw' or 'sheath') end
                elseif name=='materialize' then
                    Safe('Audio.Play',CombatState.PerfCall,'audio',CombatAudio.Play,'blade_draw',{pos=nomi_:Position(),volume=.35})
                elseif name=='materialized' and not combatRig_.ArrivalFlash and combatRig_.Flash then
                    combatRig_:Flash('sheath')
                end
            end
        end
    end
end

function Ruins_HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    time_ = time_ + dt
    Safe('Touch.Update',TouchControls.Update,dt)
    if Training.update() then return end
    if M.housePanel and (M.housePanel.open or M.housePanel.contact) then
        if not M.housePanel.port.available() then M.housePanel:Close()
        else return end
    end
    if WorldMap.IsOpen() then
        if voidInputBlocked or combatMoves_.dead then WorldMap.Close()
        elseif WorldMap.StepClosing() then return
        elseif homeJob then AdvanceHomeTravel();return
        else return end
    end
    if combatInputBlocked then
        local held=input:GetMouseButtonDown(MOUSEB_LEFT) or input:GetMouseButtonDown(MOUSEB_RIGHT)
            or TouchInput.Down('shatter') or TouchInput.Down('attack') or TouchInput.Down('heavy')
        for _,key in ipairs({KEY_1,KEY_2,KEY_3,KEY_E,KEY_R,KEY_Q,KEY_TAB,KEY_SHIFT}) do held=held or Down(key) end
        if not held then combatInputBlocked=false end
    end
    if VoidRewind.IsActive() then Safe('FX.VoidRewind',VoidRewind.Update,dt) end
    if voidInputBlocked and not VoidRewind.IsActive() then
        local held=input:GetMouseButtonDown(MOUSEB_LEFT) or input:GetMouseButtonDown(MOUSEB_RIGHT) or input:GetMouseButtonDown(MOUSEB_MIDDLE)
        for _,key in ipairs({KEY_W,KEY_A,KEY_S,KEY_D,KEY_SHIFT,KEY_SPACE,KEY_1,KEY_2,KEY_3,KEY_E,KEY_R,KEY_Q,KEY_F,KEY_T,KEY_TAB,KEY_F10}) do
            held=held or Down(key)
        end
        if not held then voidInputBlocked=false end
    end
    if touchRevision~=TouchInput.revision then
        touchRevision=TouchInput.revision
        combatInputBlocked=true
        caster_.charging,caster_.charge=false,0
    end
    if not TouchInput.IsEnabled() then pointer:Update(input:GetMouseButtonDown(MOUSEB_LEFT)) end
    local tx,ty=TouchInput.ConsumeLook()
    if TouchInput.IsEnabled() and not WeaponWheel.IsBlocked() and not voidInputBlocked and not M.debugOn and not TouchControls.IsBlocked() then nomi_:Look(tx*.14,ty*.12,combatLookScale_) end
    if M.DEBUG_PANEL and not SettingsMenu.IsBlocked() and not ForgePanel.IsOpen() and Press(KEY_F10) then M.ToggleDebugPanel() end
    if not WeaponWheel.IsBlocked() and not voidInputBlocked and not SettingsMenu.IsBlocked() and not ForgePanel.IsOpen() and Press(KEY_Z) then farView = not farView end
    if not WeaponWheel.IsBlocked() and not Down(KEY_TAB)
        and not voidInputBlocked and not TouchInput.IsEnabled() and mouseLocked and pointer:CanLook(false) then
        local mm = input.mouseMove
        if animPreview_.index>0 then
            animPreview_.orbit=Clamp((animPreview_.orbit or 0)+mm.x*.12,-25,25)
        else nomi_:Look(mm.x, mm.y, 0.12*combatLookScale_) end
    end
    -- 龙
    if M.ride then
        M.ride.externalGround = nomi_.cc.onGround
        Safe('Dragon.Ride',M.ride.Update,M.ride,dt,nomi_.camYaw)
    end
    Resources.consumed=false
    -- Observe mounting in the same Update before rendering; do not clear the
    -- touch mount edge before DragonRide consumes it.
    Safe('Combat.MountState',CombatState.SetMounted,not OnFoot())
    Safe('Combat.State',CombatState.Update,dt)
    Safe('Audio.Listener',CombatAudio.SetListenerPosition,nomi_:Position()); Safe('Audio.Update',UpdateCombatAudio,dt)
    local combatAllowed=OnFoot() and GameplayInputAllowed()
    if combatTest_ and combatTest_.active and (not combatAllowed or ForgePanel.IsOpen() or SettingsMenu.IsBlocked()) then Safe('Debug.F11Stop',combatTest_.Stop,combatTest_,'blocked/menu') end
    Safe('Debug.Keys',HandleCombatDebugKeys,combatAllowed and not combatMoves_.dead)
    if not Safe('Debug.F7',UpdateCombatPreview,dt,combatAllowed) and animPreview_.index>0 then
        animPreview_.index,animPreview_.text=0,nil
        CombatState.SetBusy(false)
        Safe('Combat.Cancel',combatMoves_.Cancel,combatMoves_,'preview-error')
    end
    Safe('Combat.Actions',UpdateCombatActions,combatAllowed,dt)
    if combatEnemies_ and not voidInputBlocked and animPreview_.index==0 then Safe('Enemies.Update',combatEnemies_.Update,combatEnemies_,dt,nomi_:Position()) end
    if trainingDummy_ then Safe('Debug.Dummy',trainingDummy_.Update,trainingDummy_) end
    if combatArrows_ then Safe('Arrows.Update',combatArrows_.Update,combatArrows_,dt) end
    if bowArrowTrailFx_ then Safe('ArrowTrail.Update',BowArrowTrailFx.Update,bowArrowTrailFx_,dt) end
    if combatParticles_ then Safe('Particles.Update',combatParticles_.UpdateOwner,combatParticles_,hitParticleOwner_,dt) end
    if M.rig then
        local ctrl=M.ctrl
        Safe('Dragon.Pose',UpdateDragonPose,dt)
        if M.ride.mode=="mounted" then
            Safe('Dragon.SeatPose',M.ride.SeatPose,M.ride); Safe('Dragon.Saddle',M.ride.AttachToSaddle,M.ride)
            M.ride.pos=nomi_.node.worldPosition
        end
        if M.mounted then
            local a=nomi_:Aim(100)
            M.breath.aimTarget=a.hit and a.pos or a.far
            if TouchInput.IsEnabled() then HUD.SetTarget("按住【龙息】持续吐息 · 朝准星方向喷射")
            else HUD.SetTarget("长按破坏键持续吐息（左键/1）") end
        else M.breath.aimTarget=nil end
        Safe('Dragon.Breath',M.breath.Update,M.breath)
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
                M.ride.aiOff = M.region=='home'
            end
        end
        Safe('Dragon.SleepPose',ApplySleepPose,dt)
        Safe('Dragon.World',M.dragonWorld.Update,M.dragonWorld,dt)
    end
    -- 谜题 / 法术
    local aim = (not M.mounted) and UpdateAim(false) or { hit = false, dir = Vector3.FORWARD, far = Vector3.ZERO }
    Safe('Spells.Input',HandleSpells,dt,aim)
    Safe('Spells.Update',caster_.Update,caster_,dt)
    -- 法阵、手光读取本帧骨骼；不再先画特效再更新手臂。
    if OnFoot() then Safe('Animation.Base',nomi_.Animate,nomi_,combatMoves_.hitstop>0 and 0 or dt,caster_.charging or caster_.castAnim > 0 or combatMoves_:BaseArmed()) end
    if combatAnim_ and animPreview_.index==0 then
        Safe('Animation.BowParameters',UpdateCombatAnimationParams)
    end
    if combatAnim_ and (CombatState.InCombat() or combatMoves_.dead or combatMoves_.clip~=nil or (foot_ and foot_.weight>0) or animPreview_.index>0) then Safe('Animation.Apply',combatAnim_.Apply,combatAnim_) end
    if foot_ and OnFoot() then
        local preview=animPreview_.index>0 and CombatAnim.DebugList()[animPreview_.index].id
        Safe('Locomotion.Ground',nomi_.GroundFeet,nomi_,foot_,dt,
            foot_.weight>0 or preview=='sprint_loop')
    end
    if weaponGesture_ then Safe('WeaponSelect.Pose',weaponGesture_.Apply,weaponGesture_,dt) end
    if clothInertia_ and OnFoot() then Safe('Animation.Cloth',clothInertia_.Apply,clothInertia_,dt) end
    Safe('Debug.F7HUD',UpdateCombatPreviewText)
    Safe('Rig.Visuals',UpdateCombatRig,dt)
    if animPreview_.index==0 then
        nomi_:BeginQueryScope()
        Safe('Combat.AfterPose',combatMoves_.AfterPose,combatMoves_)
        nomi_:EndQueryScope()
    end
    -- 法阵只更新一次，在 PostUpdate 中使用本帧最终相机与施法方向。
    Safe('Puzzles.Update',Puzzles.Update,dt,true)
    Safe('Puzzles.Gate',Puzzles.CheckGate)
    Safe('Puzzles.Key',Puzzles.UpdateKey,time_,nomi_:Position())
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
    dn.fast = not voidInputBlocked and not SettingsMenu.IsBlocked() and not ForgePanel.IsOpen() and Down(KEY_T)
    Safe('Sky.DayNight',dn.Update,dn,dt)
    if M.atmosphere.active then
        local ground=M.region=='home' and HomeIsland.meadowMaterial or Terrain.groundMaterial
        Safe('Sky.Atmosphere',M.atmosphere.Update,M.atmosphere,dt,M.mounted and M.rig.root.worldPosition or nomi_.node.worldPosition,ground)
    end
    local clockMinute,clockPhase=math.floor(dn.hour*60),dn:PhaseName()
    if hudClockMinute~=clockMinute or hudClockPhase~=clockPhase then
        hudClockMinute,hudClockPhase=clockMinute,clockPhase
        HUD.SetClock(dn:ClockText())
    end
    -- 法阵灯：苏醒后常亮；夜里本来就有一点微光
    M.courtLight.brightness = 2.2 * M.runeK + 0.6 * (dn.nightK or 0)
    -- 草：诺米 / 龙脚下压开
    local playerFeet=nomi_:Position() -- VoxelCharacterController syncs the root to the foot of the capsule.
    Terrain.SetInteractor(0, playerFeet, 0.6)
    if M.rig then Terrain.SetInteractor(1,M.rig.root.worldPosition,(M.rig.size or 1)*2.2) end
    if Terrain.home then
        local walking=M.region=='home' and OnFoot() and not voidInputBlocked
        HomeIsland.SetWindowLightingActive(M.region=='home',CombatSettings.GetProfile().quality)
        HomeIsland.Update(dt,walking and playerFeet or nil,dn)
    end
    Build.UpdateFloaters(time_, 1.0)
    -- 特效 / 手光
    -- 碎石堆选中红光（平滑淡入淡出，量化后才写材质参数）
    local gm = Puzzles.gateMaterial
    if gm ~= nil then
        M.gateHover = (M.gateHover or 0) + ((M.gateHoverTarget or 0) - (M.gateHover or 0)) * (1 - math.exp(-12 * dt))
        local gq = math.floor(M.gateHover * 20 + 0.5) / 20
        if gq ~= M.lastGateHover then
            M.lastGateHover = gq
            gm:SetShaderParameter("hover", Variant(gq))
        end
    end
    local lastSpell = caster_.lastCast and Spells.BY_ID[caster_.lastCast]
    local glowCol = caster_.charging and Spells.SHATTER_COLOR
        or (caster_.castAnim > 0 and lastSpell and lastSpell.color) or Spells.WHITE
    local glow = caster_.charging and (0.4 + 0.6 * caster_.charge) or (caster_.castAnim > 0 and 1.0 or 0.28)
    if CombatState.InCombat() then fx_.handGlow=0 end
    glow=glow*CombatState.Glow()
    Safe('FX.Hand',CombatMoves.UpdateHandFX,fx_,handMotes_,dt,nomi_:HandPos(),glowCol,glow)
    if timeCatalyst_ then
        Safe('TimeCatalyst',function()
            TimeCatalyst.Step(timeCatalyst_)
            local active=CombatState.GetSelection()=='time' and not M.mounted and not (combatMoves_ and combatMoves_.dead)
                and not ForgeShowroom.Active()
            TimeCatalyst.Update(timeCatalyst_,dt,{active=active,position=nomi_:Position(),yaw=nomi_.yaw or 0,
                hand=nomi_:HandPos(),aiming=caster_.charging or caster_.castAnim>0,charge=caster_.charging and caster_.charge or 0,
                casting=caster_.castAnim>0})
        end)
    end
    M.combat.handEffect=M.combat.handEffect or {}
    local handEffect=M.combat.handEffect
    handEffect.requested,handEffect.glow=glow,fx_.handGlow
    handEffect.brightness,handEffect.particles=fx_.handL.brightness,handMotes_:Count()
    if handWasOn_~=(glow>0) then
        handWasOn_=glow>0
        CombatState.Log('hand-glow','Combat: hand glow state=%s requested=%.2f brightness=%.3f motes=%d',CombatState.Get(),glow,fx_.handL.brightness,handMotes_:Count())
    end
    -- HUD
    HUD.UpdateSlots(caster_.cool, caster_.charging and caster_.charge or 0,Spells.ShatterRadius(caster_.charge))
    if banner.t > 0 then
        banner.t = banner.t - dt
        if banner.t <= 0 then HUD.SetMessage(caster_.message) end
    else
        HUD.SetMessage(caster_.message)
    end
    if mouseLocked and M.ride then
        local h = M.ride.hint
        if M.ride.locked or OnFoot() and (h == nil or h:find("WASD")) then h = "" end
        HUD.SetHint(h)
    end
    Safe('Touch.Sync',TouchControls.Sync)
    -- 准星常驻，方便平时选中目标；调试面板打开时隐藏。
    HUD.SetCrossVisible(not M.debugOn)

end

local function UpdateBaseCamera(dt)
    if ForgeShowroom and ForgeShowroom.Active() then return end
    if animPreview_.index>0 and OnFoot() then
        nomi_:UpdateCombatPreview(dt,animPreview_.view or 4,animPreview_.orbit or 0)
    elseif M.mounted or not OnFoot() then
        nomi_:UpdateCamera(dt, "mounted", M.rig.bones.chest)
    else
        local mode = farView and "far" or ((caster_.charging or caster_.castAnim > 0) and "aim" or "normal")
        if CombatState.Engaged() and not farView then
            local target=M.combat.aimed or combatMoves_.target
            if target and (target.dead or target.active==false) then target=nil end
            local boss=false
            for _,enemy in ipairs(CombatEnemies()) do if enemy.boss and enemy.aggro and not enemy.dead then boss=true; target=target or enemy end end
            local focus=target and not target.dead and target.position or nil
            local drawing=combatMoves_.clip=='bow_draw' or combatMoves_.clip=='bow_hold'
            if drawing then focus=nil end -- keep the reticle ray stable while aiming
            nomi_:SetCombatCamera(focus,boss,drawing,false) -- charge envelope owns zoom, avoid double FOV
            mode='combat'
        end
        if M.forceCamMode ~= nil then mode = M.forceCamMode end
        nomi_:UpdateCamera(dt, mode, nomi_.node)
    end
end

local function UpdateCombatCamera(dt,cn)
        if ForgeShowroom and ForgeShowroom.Active() then return end
        combatCameraFrame_=combatCamera_:Update(dt,combatMoves_,CombatState.GetSetting('cameraFov'),CombatState.GetSetting('cameraShake'),not combatLowQuality_)
        if OnFoot() and animPreview_.index==0 then
            local action=combatCameraFrame_
            local offset=combatMoves_:ShakeOffset(cn.worldRight,cn.worldUp)+(action.impact or Vector3.ZERO)
            local impactLength=offset:Length()
            if impactLength>.03 then offset=offset*(.03/impactLength) end
            local footCamera=CombatState.Engaged() or (not Down(KEY_Z) and not caster_.charging
                and ((foot_ and foot_.weight>0) or (combatCamera_.sprint or 0)>0))
            if footCamera then offset=offset+action.focus-cn.worldDirection*action.distance end
            if footCamera or offset:LengthSquared()>0 then nomi_:ApplyCombatOffset(offset) end
            if footCamera then
                -- The base library resets fov each frame. Merge impacts by maximum,
                -- not addition, so heavy hits cannot double the authored +2 degrees.
                local impact=not combatLowQuality_ and combatMoves_:FovOffset() or 0
                nomi_:Camera().fov=nomi_:Camera().fov+math.min(0,action.fov)+math.max(0,action.fov,impact)
            end
        end
end

-- Hide obstructed boundary samples; never paint a promise through a wall or void.
local rangeRayPool={}
for i=1,16 do rangeRayPool[i]={} end
local rangeRayCount,rangeRevision=0,-1
---@param source Vector3
---@param point Vector3
local function CombatRangeClear(source,point)
    local delta=point-source --[[@as Vector3]]
    local length=delta:Length()
    if length<.001 then return true end
    if rangeRevision~=SwingPerf.revision then rangeRayCount=0;rangeRevision=SwingPerf.revision end
    local mask,layer=nomi_.cc.collisionMask,nomi_.cc.collisionLayer
    for i=1,rangeRayCount do
        local c=rangeRayPool[i]
        if c.sx==source.x and c.sy==source.y and c.sz==source.z and c.x==point.x and c.y==point.y and c.z==point.z
            and c.mask==mask and c.layer==layer and c.filter==nomi_.ignoreAimVolume then return c.clear end
    end
    if SwingPerf.rangeRays>=16 then return false end
    local hit=nomi_:SlideRay(Ray(source,delta/length),length,'range')
    local clear=not hit or hit.distance>=length-.02
    if rangeRayCount<16 then
        rangeRayCount=rangeRayCount+1
        local c=rangeRayPool[rangeRayCount]
        c.sx,c.sy,c.sz,c.x,c.y,c.z=source.x,source.y,source.z,point.x,point.y,point.z
        c.mask,c.layer,c.filter,c.clear=mask,layer,nomi_.ignoreAimVolume,clear
    end
    return clear
end
local function CombatRangeVisible(source,point)
    if not Terrain.HasGround(point.x,point.z,.05) then return false end
    local cn=nomi_:CameraNode()
    local p=cn.worldPosition;local f=cn.worldDirection
    if (point.x-p.x)*f.x+(point.y-p.y)*f.y+(point.z-p.z)*f.z<=0 then return false end
    return CombatRangeClear(source,point) and CombatRangeClear(p,point)
end

local hudAimHits,hudAimPool,hudNearHits,hudNearPool={},{},{},{}
for i=1,64 do hudAimPool[i]={};hudNearPool[i]={} end
-- Bow aim, two-sided assistance LOS, trajectory and range hints share 16 rays.
-- Grid fallback exhaustion is blocked/unknown, never a fabricated landing dot.
local function CombatBowCast(a,b)
    if SwingPerf.rangeRays>=16 then return 0,false end
    SwingPerf.rangeRays=SwingPerf.rangeRays+1
    local denied=SwingPerf.gridBudgetExceeded
    local hit=CombatCast(a,b,true)
    return hit,SwingPerf.gridBudgetExceeded==denied
end
---@param cn Node
local function UpdateCombatHUD(cn,dt)
        local enemies=CombatEnemies()
        local drawing=CombatState.InCombat() and (combatMoves_.clip=='bow_draw' or combatMoves_.clip=='bow_hold')
        local a,b=cn.worldPosition,cn.worldPosition+cn.worldDirection*(combatRig_:GetStats().range or 60)
        local hits=CombatHit.Query(enemies,a,b,.03,nil,hudAimHits,hudAimPool)
        local wall
        if drawing then wall=CombatBowCast(a,b) else wall=CombatCast(a,b,true) end
        local aimed=hits[1] and (not wall or hits[1].t<wall) and hits[1].enemy or nil
        M.combat.aimed=aimed
        combatLookScale_=CombatState.Engaged() and combatCameraFrame_ and combatCameraFrame_.look or 1
        local assisted=false
        local budget=math.max(0,16-SwingPerf.rangeRays)
        local launch=drawing and combatRig_:GetHit().origin or nil
        if drawing and CombatState.GetSetting('aimAssist') then
            local near=CombatHit.Query(enemies,a,b,2,nil,hudNearHits,hudNearPool)
            for _,candidate in ipairs(near) do
                local ray=candidate.shape.center-a
                local distance=ray:Length()
                local limit=candidate.enemy==bowAssistTarget and 3.5 or 2.5
                if distance>=8 and distance<=32 and ray:Normalized():DotProduct(cn.worldDirection)>=math.cos(math.rad(limit)) and budget>=2 then
                    budget=budget-2
                    if CombatHit.Visible(a,candidate.shape.center,CombatBowCast) and CombatHit.Visible(launch,candidate.shape.center,CombatBowCast) then
                        assisted=true;bowAssistTarget=candidate.enemy;break
                    end
                end
            end
        end
        if not assisted then bowAssistTarget=nil end
        bowAssistScale=bowAssistScale+((assisted and .8 or 1)-bowAssistScale)*(1-math.exp(-(dt or 0)/(assisted and .08 or .14)))
        combatLookScale_=combatLookScale_*bowAssistScale
        if drawing and CombatHUD.BOW_PREDICTION and budget>0 then
            local target=a+(b-a)*(hits[1] and (not wall or hits[1].t<wall) and hits[1].t or wall or 1)
            local tip=combatRig_:GetBowArrowTip()
            budget=budget-1
            local blocked=CombatBowCast(launch,tip)
            if blocked then bowPrediction.valid,bowPrediction.working=false,false
            else Projectile.Predict(bowPrediction,tip,(target-tip):Normalized(),combatMoves_.charge,
                combatRig_:GetStats(),time_,combatLowQuality_,math.min(budget,combatLowQuality_ and 8 or 16),CombatBowCast,enemies) end
        else bowPrediction.valid,bowPrediction.working=false,false end
        local hud=combatHUDData
        hud.rangeVisible=CombatRangeVisible
        hud.moves,hud.combat,hud.mounted=combatMoves_,CombatState.InCombat(),not OnFoot()
        hud.weapon,hud.charge=CombatState.GetWeapon(),combatMoves_.charge
        hud.aimed,hud.enemies,hud.camera,hud.cameraNode=aimed,enemies,nomi_:Camera(),cn
        hud.bowCameraCharge=combatCameraFrame_ and combatCameraFrame_.cross or 0
        hud.bowPrediction=bowPrediction
        hud.debug=animPreview_.text or (time_<combatDebugUntil_ and combatDebugText_ or nil)
        if hud.debug then
            hud.audioReady=CombatAudio.IsReady()
            hud.hitKernels=combatParticles_ and combatParticles_.kernels or 0
            hud.hitDropped=combatParticles_ and combatParticles_.dropped or 0
        end
        hud.preview=animPreview_.index>0
        CombatHUD.Set(hud)
end

function Ruins_HandlePostUpdate(eventType, eventData)
    if Training.blocked() then Resources.prompt.Clear(); return end
    local dt = eventData["TimeStep"]:GetFloat()
    nomi_:BeginQueryScope()
    Safe('Camera.Base',UpdateBaseCamera,dt)
    nomi_:EndQueryScope()
    local cn=nomi_:CameraNode()
    if combatMoves_ then SwingPerf.Invalidate() end
    nomi_:BeginQueryScope()
    if combatMoves_ then Safe('Camera.Combat',UpdateCombatCamera,dt,cn) end
    HomeTrees.UpdateView(cn.worldPosition,nomi_:Position()+Vector3(0,1.25,0),
        not ForgeShowroom.Active() and not WorldMap.IsOpen())
    if M.region=='home' and not ForgeShowroom.Active() and not WorldMap.IsOpen() then
        HomeIsland.UpdateReflection(dt,scene_,nomi_:Camera(),CombatSettings.GetProfile().quality,M.dayNight.sky.skybox)
    end
    -- 展示准星必须读取最终相机；不能把上一帧射线的结果画在当前帧视角。
    -- Update 的 aim 仍用于本帧技能输入，PostUpdate 再校准选中反馈与悬停材质。
    local aim=not M.mounted and UpdateAim() or {hit=false,far=nomi_:HandPos()+nomi_.node.worldDirection*60}
    Safe('Puzzles.Presentation',Puzzles.UpdatePresentation,dt)
    Safe('FX.Sigils',M.sigils.Update,M.sigils,dt,aim,nomi_:HandPos(),nomi_:CameraNode(),caster_,Spells.ShatterRadius(caster_.charge),not M.mounted and not M.debugOn and CombatState.CanUseTime(),CombatState.GetSelection()=='time')
    if combatMoves_ then Safe('HUD.Update',UpdateCombatHUD,cn,dt) end
    Safe('HUD.Material',Resources.present,cn)
    nomi_:EndQueryScope()
    if combatMoves_ and weaponGesture_ then Safe('WeaponSelect.Anchor',weaponGesture_.Update,weaponGesture_,dt,nomi_:Camera()) end
    Safe('FX.MotesB',fx_.motesB.Draw,fx_.motesB); Safe('FX.MotesG',fx_.motesG.Draw,fx_.motesG)
    Safe('FX.HandMotes',handMotes_.Draw,handMotes_)
    if timeCatalyst_ then Safe('TimeCatalyst.Draw',TimeCatalyst.Draw,timeCatalyst_) end
end

function M.Stop()
    if M.trainingStation then M.trainingStation:Destroy(); M.trainingStation=nil end
    Training.release=false
    Resources.prompt.Clear();Resources.consumed=false
    if Resources.live then Resources.live:Destroy();Resources.live=nil end
    TouchControls.onGatherHit,TouchControls.onGather=nil,nil
    if M.housePanel then M.housePanel:Close();M.housePanel=nil;TouchControls.housePanel=nil end
    if weaponGesture_ then weaponGesture_:ForceClose('stop'); weaponGesture_=nil end
    if combatTest_ and combatTest_.active then combatTest_:Stop('stop') end
    combatTest_=nil
    ForgePanel.Close(true)
    local forceClose=rawget(ForgePanel,'ForceClose')
    if type(forceClose)=='function' then forceClose() end
    if ForgeShowroom then ForgeShowroom.Exit() end -- teardown between panel fades
    if M.atmosphere then M.atmosphere:Stop() end
    DebugLog.RegisterProbe('Ruins',nil)
    WorldMap.Close(); TouchControls.onMap=nil
    if homeJob then homeJob:Cancel();homeJob=nil end
    HomeTrees.Stop()
    HomeIsland.Stop(); HomeIsland.GetHouseOccupants=nil; Terrain.home=nil; lastRuinsLanding=nil
    SettingsMenu.Stop()
    PerformanceHUD.Stop()
    CombatState.Stop()
    CombatSettings.RegisterQuality('combat-presentation',nil)
    CombatAudio.Dispose()
    combatAudioWarmup_ = nil
    combatCamera_,combatCameraFrame_=nil,nil
    for key in pairs(aimTextCache) do aimTextCache[key]=nil end
    for i=#combatEnemyView,1,-1 do combatEnemyView[i]=nil end
    for key in pairs(combatHUDData) do combatHUDData[key]=nil end
    if trainingDummy_ then trainingDummy_:Destroy(); trainingDummy_=nil end
    if handMotes_ then handMotes_:Clear(); handMotes_=nil end
    handWasOn_,combatDebugText_,combatDebugUntil_,debugDestination_=nil,nil,0,0
    if combatArrows_ then combatArrows_:Clear() end
    if bowArrowTrailFx_ then BowArrowTrailFx.Dispose(bowArrowTrailFx_);bowArrowTrailFx_=nil end
    if combatParticles_ then combatParticles_:ClearOwner(hitParticleOwner_); combatParticles_=nil end
    if combatEnemies_ then combatEnemies_:Destroy() end
    if combatAnim_ then combatAnim_:Stop(nil,0) end
    if foot_ then foot_:Cancel('scene-stop') end
    foot_,M.foot=nil,nil
    combatMoves_,combatAnim_,combatArrows_,combatEnemies_=nil,nil,nil,nil
    combatEnvironment_=nil
    for _,entry in pairs(arrowNodes_) do entry.node:Remove() end
    if arrowTailMaterial_ then arrowTailMaterial_:Dispose();arrowTailMaterial_=nil end
    arrowNodes_={}; animPreview_={index=0,t=0,params={moveX=0,moveZ=-1,bow=0,p=.5,weaponInHand=1},direction='后'}; CombatHUD.Set(nil)
    if combatRig_ and combatRig_.Dispose then combatRig_:Dispose() end
    combatRig_=nil
    if timeCatalyst_ then TimeCatalyst.Dispose(timeCatalyst_);timeCatalyst_=nil end
    VoidRewind.Stop() -- release images while the UI NanoVG context is still alive
    TouchControls.Stop()
    HUD.Stop()
    Safe('GC.Stop',StopSceneGC)
    UnsubscribeFromEvent("BeginFrame")
    UnsubscribeFromEvent("EndFrame")
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("PostUpdate")
    UnsubscribeFromEvent("SceneUpdate")
    UnsubscribeFromEvent("MouseButtonDown")
    UnsubscribeFromEvent("MouseButtonUp")
    UnsubscribeFromEvent("MouseMove")
    UnsubscribeFromEvent("MouseModeChanged")
    UnsubscribeFromEvent("KeyDown")
    UnsubscribeFromEvent("InputFocus")
    UnsubscribeFromEvent("EnemyAttackCue")
    pointer:Release("stop")
    if M.stream then M.stream:Stop(true) end
    Puzzles.Stop()
    Build.Stop()
    Terrain.Stop()
    Brush.materialFor=nil
    if scene_ then scene_:Clear() end
    scene_,world_,nomi_,caster_,fx_=nil,nil,nil,nil,nil
    clothInertia_=nil
    sleepBase.valid=false
    for _,key in ipairs({'scene','world','puzzles','nomiCtl','caster','fx','rig','ctrl','ride','breath',
        'dragonWorld','nomi','nomiNode','stream','sigils','atmosphere','surfaceMaterials',
        'sun','zone','courtLight','combat','foot','dayNight','aim'}) do M[key]=nil end
    if rawget(_G,'RUINS')==M then rawset(_G,'RUINS',nil) end
end

return M
