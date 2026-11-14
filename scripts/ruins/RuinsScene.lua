-- ====================================================================
-- RuinsScene.lua — 时之遗迹：场景装配、输入、相机、谜题流程、龙看守者
--
-- 模块：
--   RuinsTerrain  地形（主岛 / 环形虚空 / 遗迹外环）     RuinsBuild   静态建筑与景观
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
local SkyAtmosphere = require("ruins.SkyAtmosphere")
local Terrain = require("ruins.RuinsTerrain")
local Build = require("ruins.RuinsBuild")
local Puzzles = require("ruins.RuinsPuzzles")
local Spells = require("ruins.TimeSpells")
local Sigil = require("ruins.TimeSigil")
local RuinsDragon = require("ruins.RuinsDragon")
local Nomi = require("ruins.NomiController")
local HUD = require("ruins.RuinsHUD")
local VoidRewind = require("ruins.VoidRewind")
local TouchInput = require("ui.TouchInput")
local TouchControls = require("ui.TouchControls")
local SettingsMenu = require("ui.SettingsMenu")
local PerformanceHUD = require("ui.PerformanceHUD")
local DebugLog = require("ruins.DebugLog")
local CombatState = require("combat.CombatState")
local Safe=CombatState.Isolated
local CombatMoves = require('combat.CombatMoves')
local CombatAnim = require('combat.CombatAnim')
local CombatHit = require('combat.Hit')
local CombatAudio = require('combat.CombatAudio')
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
local WeaponRig = require('combat.WeaponRig')
local EnemySpawner = require('combat.enemies.Spawner')
local CombatHUD = require('ui.CombatHUD')
local ForgePanel = require('ui.ForgePanel')
local ForgeShowroom = require('combat.ForgeShowroom')
local combatMoves_,combatAnim_,combatArrows_,combatEnemies_
local combatParticles_
local hitParticleOwner_={position=Vector3.ZERO,radius=0,age=0,config={height=0,hover=0}}
local combatLookScale_=1
local combatHUDData={}
local hudClockMinute,hudClockPhase
local CombatCamera=require('combat.CombatCamera')
local combatCamera_,combatCameraFrame_
local arrowNodes_={}
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
local combatInputBlocked = false
local combatNoticeAt = 0
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
local M = {}

-- Optional pacing, scoped to this scene. Never switch to generational GC.
-- GetSystemTime 是静态绑定，三个计时点都必须传 Time 类表而不是实例。
M.gcEnabled=true
M.gcDebug=false
local gcState={running=false,configured=false,steps=0,cycles=0,skipped=0,maxMs=0,reclaimed=0}
function M.SetGCEnabled(enabled)
    M.gcEnabled=enabled==true
    if M.gcEnabled and gcState.running and not gcState.configured then
        gcState.pause=collectgarbage('setpause',110)
        gcState.stepmul=collectgarbage('setstepmul',300)
        collectgarbage('incremental',110,300)
        gcState.configured=true
    elseif not M.gcEnabled and gcState.configured then
        collectgarbage('setpause',gcState.pause)
        collectgarbage('setstepmul',gcState.stepmul)
        gcState.configured=false
    end
end
local function StartSceneGC()
    gcState.running=true
    gcState.steps,gcState.cycles,gcState.skipped,gcState.maxMs,gcState.reclaimed=0,0,0,0,0
    gcState.frameStart=nil
    gcState.at=Time:GetSystemTime()
    gcState.heap=collectgarbage('count')
    M.SetGCEnabled(M.gcEnabled)
end
function Ruins_HandleGCBeginFrame()
    if gcState.running then gcState.frameStart=Time:GetSystemTime() end
end
local function StepSceneGC()
    if not gcState.running then return end
    M.SetGCEnabled(M.gcEnabled) -- direct debug flag changes also restore pacing
    local now=Time:GetSystemTime()
    if M.gcEnabled and gcState.frameStart then
        if now-gcState.frameStart<=12 and now>=gcState.frameStart then
            local before=M.gcDebug and collectgarbage('count') or 0
            local t=M.gcDebug and os.clock() or 0
            local completed=collectgarbage('step',8)
            gcState.steps=gcState.steps+1
            if completed then gcState.cycles=gcState.cycles+1 end
            if M.gcDebug then
                gcState.maxMs=math.max(gcState.maxMs,(os.clock()-t)*1000)
                gcState.reclaimed=gcState.reclaimed+math.max(0,before-collectgarbage('count'))
            end
        else gcState.skipped=gcState.skipped+1 end
    end
    gcState.frameStart=nil -- at most one explicit step per frame
    if now-gcState.at>=1000 then
        local heap=collectgarbage('count')
        if M.gcDebug then
            print(string.format('RuinsGC: heapKB=%.1f deltaKB=%+.1f steps=%d completed=%d skipped=%d stepReclaimedKB=%.1f maxStepCPUms=%.3f',
                heap,heap-gcState.heap,gcState.steps,gcState.cycles,gcState.skipped,gcState.reclaimed,gcState.maxMs))
        end
        gcState.at,gcState.heap=now,heap
        gcState.steps,gcState.cycles,gcState.skipped,gcState.maxMs,gcState.reclaimed=0,0,0,0,0
    end
end
function Ruins_HandleGCEndFrame()
    Safe('GC.Step',StepSceneGC)
    Safe('Perf.Flush',CombatState.FlushSwapPerf)
end
local function StopSceneGC()
    local enabled=M.gcEnabled
    M.SetGCEnabled(false)
    M.gcEnabled=enabled
    gcState.running=false;gcState.frameStart=nil
end


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
    bridge = { "修复断桥", "桥体残片悬在裂隙中。站在岸边，瞄准带金色符脉的悬空桥片，按 Q 施放「回溯」。" },
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
    M.atmosphere = SkyAtmosphere.New(scene_, M.dayNight)
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
    ride.controlsEnabled = function() return not voidInputBlocked and not M.debugOn and not TouchControls.IsBlocked()
        and not (combatMoves_ and combatMoves_.dead) and animPreview_.index==0 and input.focus and not input.minimized
        and (TouchInput.IsEnabled() or pointer:IsEnabled() or M.fake~=nil) end
    ride.onNotice = function(text) caster_:Say(text) end
    ride.onMount = function()
        CombatState.SetMounted(true)
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
        WakeDragon()
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

-- Independent ray safeguard: even a misconfigured native layer cannot let the
-- equipped model, sword afterimages or trail particles occlude aim/projectiles.
local function IsCombatVisualVolume(volume)
    local rig=combatRig_
    if not rig then return false end
    for _,entry in pairs(rig.entries) do if entry.mesh.volume==volume then return true end end
    for _,item in ipairs(rig.trails) do if item.volume==volume then return true end end
    for _,item in ipairs(rig.images) do if item.volume==volume then return true end end
    for _,item in ipairs(rig.bowImages or {}) do if item.volume==volume then return true end end
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
-- Reuse Nomi's exact grid-query repair. Geometry, including terrain, blocks
-- combat rays but is never damaged by them.
---@param a Vector3
---@param b Vector3
local function CombatCast(a,b)
    local delta=b-a
    local length=delta:Length()
    if length<.0001 then return nil end
    local hit=nomi_:GridHit(Ray(a,delta/length),length)
    return hit.hit and Clamp(hit.distance/length,0,1) or nil
end
local function CombatFeedback(event)
    if not combatParticles_ or event.killed then return end
    -- W3 owns real enemy particles at successful settlement. The same shared
    -- scene pool handles player and training impacts only, never a duplicate.
    if not event.player and event.enemy and event.enemy.particles then return end
    hitParticleOwner_.position,hitParticleOwner_.age=event.pos,time_
    combatParticles_:Emit(hitParticleOwner_,event)
end
local function CombatHasAggro()
    for _,enemy in ipairs(CombatEnemies()) do if enemy.active and enemy.aggro and not enemy.dead then return true end end
    return false
end
local function CanOpenForge()
    if not nomi_ or not M.ride or M.ride.mode~='free' or CombatState.InCombat() or CombatHasAggro()
        or combatMoves_.dead or voidInputBlocked or SettingsMenu.IsBlocked() or animPreview_.index>0 then return false end
    local p=nomi_:Position()
    return nomi_.cc.onGround and Terrain.IsSafeGround(p.x,p.y,p.z)
end
local function OpenForge()
    if not CanOpenForge() then caster_:Say('请在安全地面、脱离警戒后锻造',1.2); return end
    ForgePanel.Open({rig=combatRig_,canOpen=CanOpenForge,
        onOpen=function()
            pointer:Release('forge'); pointer:SetBlocked(true)
            TouchControls.Cancel(); drag.buttons=0
            caster_.charging,caster_.charge=false,0
        end,
        onClose=function()
            TouchControls.Cancel(); pointer:SetBlocked(M.debugOn or SettingsMenu.IsBlocked())
            pointer:Release('forge-close')
        end})
end
local function StartCombat()
    CombatAudio.New(scene_)
    combatAudioWarmup_ = 0
    combatCamera_=CombatCamera.New()
    local hasDustStreak=false
    for _,event in ipairs(require('combat.AnimClips').Clips.dodge_slide.events) do
        if event[1]=='dust_streak' then hasDustStreak=true; break end
    end
    combatAnim_=CombatAnim.New(nomi_.nomi,nomi_.node)
    combatMoves_=CombatMoves.New({anim=combatAnim_,rig=combatRig_,state=CombatState,
        position=function() return nomi_:Position() end,forward=function() return nomi_.node.worldDirection end,
        enemies=CombatEnemies,cast=CombatCast,feedback=CombatFeedback,audio=combatAudioPort,camera=combatCamera_,
        slideStart=function() return nomi_:CanSlide() end,
        slideMotion=function(motion) return nomi_:ClipSlideMotion(motion) end,
        attackMotion=function(motion) return nomi_:ClipAttackMotion(motion) end,
        dustStreak=function(direction)
            if not nomi_.cc.onGround then return end
            CombatMoves.EmitDustStreak(combatParticles_,hitParticleOwner_,nomi_:Position(),direction,
                function(at) return nomi_:SlideGround(at) end)
        end,
        dust=function(count,direction)
            if hasDustStreak or not nomi_.cc.onGround then return end -- §20 shared-pool streak replaces old motes
            local pos=nomi_:Position()+Vector3(0,.04,0)
            for i=1,count do
                local side=Vector3(direction.z,0,-direction.x)*((i-(count+1)*.5)*.06)
                fx_.motesB:Spawn{pos=pos+side,vel=-direction*.35+side+Vector3(0,.18,0),
                    life=.12+.04*(i%3),size=.025+.01*(i%3),colors={Color(.48,.46,.40)}}
            end
        end,
        aimPitch=function()return nomi_.camPitch end,
        intent=function() local a=math.rad(nomi_.camYaw);return Vector3(math.sin(a),0,math.cos(a)) end,
        assist=function(intent,selectTarget)
            return nomi_:AssistMelee(CombatEnemies(),CombatCast,intent,selectTarget and CombatState.GetSetting('aimAssist'))
        end,
        protected=function() return M.ride.mode~='free' or voidInputBlocked or animPreview_.index>0 end,
        fire=function(charge,stats,forceCrystal)
            local hit=combatRig_:GetHit()
            local cn=nomi_:CameraNode()
            local a=cn.worldPosition
            local b=a+cn.worldDirection*(stats.range or 36)
            local wall=CombatCast(a,b)
            local contacts=CombatHit.Query(CombatEnemies(),a,b,0)
            local reach=wall or 1
            if contacts[1] and contacts[1].t<reach then reach=contacts[1].t end
            local target=a+(b-a)*reach
            local shotStats=stats
            if forceCrystal then
                shotStats={}; for key,value in pairs(stats) do shotStats[key]=value end
                shotStats.crystalRadius=.8; shotStats.crystalDamageMultiplier=.25
            end
            if combatTest_ and combatTest_.active and trainingDummy_ then
                target=trainingDummy_:GetHurtShapes()[1].center -- synthetic aim, real swept projectile collision
            end
            local fired,shot=combatArrows_:Fire(hit.origin,(target-hit.origin):Normalized(),charge,shotStats)
            if fired and combatTest_ and combatTest_.active then combatTest_:Arrow(shot) end
        end,
        respawn=function()
            -- Use the established safe-point/fallback and camera snap; puzzle
            -- progress is untouched. Avoid starting the cinematic void path.
            nomi_:ReturnFromVoid()
            combatArrows_:Clear()
            combatEnemies_:Reset()
            caster_:Say('时之印记 · 生命已恢复',1.2)
        end})
    local arrowMaterial=Material:new()
    arrowMaterial:SetTechnique(0,cache:GetResource('Technique','Techniques/PBR/PBRNoTexture.xml'))
    arrowMaterial:SetShaderParameter('MatDiffColor',Variant(Color(.76,.65,.4,1)))
    arrowMaterial:SetShaderParameter('Roughness',Variant(.85))
    local tailMaterial=Material:new()
    tailMaterial:SetTechnique(0,cache:GetResource('Technique','Techniques/NoTextureUnlit.xml'))
    tailMaterial:SetShaderParameter('MatDiffColor',Variant(Color(.65,.70,.65,1)))
    for i=1,12 do
        local node=scene_:CreateChild('CombatArrow_'..i)
        node.enabled=false
        local body=node:CreateChild('shaft')
        local model=body:CreateComponent('StaticModel')
        model:SetModel(cache:GetResource('Model','Models/Box.mdl')); model:SetMaterial(arrowMaterial)
        body.scale=Vector3(.03,.03,.42)
        local tails={}
        for j=1,4 do
            local tail=node:CreateChild('tail_'..j)
            local mesh=tail:CreateComponent('StaticModel')
            mesh:SetModel(cache:GetResource('Model','Models/Box.mdl')); mesh:SetMaterial(tailMaterial)
            tail.scale=Vector3(.022-(j-1)*.004,.022-(j-1)*.004,.09)
            tail.position=Vector3(0,0,-.26-(j-1)*.11); tails[j]=tail
        end
        arrowNodes_[i]={node=node,tails=tails}
    end
    combatArrows_=Projectile.New({enemies=CombatEnemies,cast=CombatCast,log=CombatState.Log,audio=combatAudioPort,
        hit=function(...) combatMoves_:Feedback(...) end,wallHit=CombatFeedback,
        draw=function(p,visible)
            local entry=arrowNodes_[p.index]
            entry.node.enabled=visible
            if visible then
                entry.node.position=p.pos; entry.node:SetDirection(p.vel:Normalized())
                for _,tail in ipairs(entry.tails) do tail.enabled=not p.embedded end
            end
        end})
    combatEnemies_=EnemySpawner.New(scene_,world_,Terrain,{
        PlayerPos=function() return nomi_:Position() end,
        DamagePlayer=function(info)
            if ForgePanel.IsOpen() then ForgePanel.Close(true) end
            return CombatHit.Apply(combatMoves_,info)
        end,
        OnEnemyAggro=function(id)
            if ForgePanel.IsOpen() then ForgePanel.Close(true) end
            if animPreview_.index==0 then CombatState.OnEnemyAggro(id) end
        end,
        OnEnemyDead=function(enemy) combatMoves_.target=enemy end})
    M.combat={state=CombatState,moves=combatMoves_,enemies=combatEnemies_,anim=combatAnim_,arrows=combatArrows_}
    combatParticles_=combatEnemies_:GetParticlePool()
    CombatSettings.RegisterQuality('combat-presentation',function(profile)
        combatLowQuality_=profile.quality=='low'
        combatParticles_:SetLimit(combatLowQuality_ and 32 or 64)
        CombatAudio.SetQuality(combatLowQuality_ and 'low' or 'mid')
    end)
end
local function AttachTouchControls()
    local touchState={}
    local cooldown = {}
    for _,sp in ipairs(Spells.SPELLS) do cooldown[sp.id]=sp.cooldown end
    TouchControls.Attach(HUD.root,function()
        local ride,ctrl=M.ride,M.ctrl
        touchState.mounted,touchState.mounting=ride.mode~="free",ride.mode=="mounting"
        touchState.airborne,touchState.gliding=ctrl.loco.airborne,ctrl.state=="GLIDE"
        touchState.blocked=M.debugOn or voidInputBlocked or ForgePanel.IsOpen()
        touchState.breathActive=M.stream and M.stream.active
        touchState.noSpells=not CombatState.CanUseTime()
        touchState.readyFlash,touchState.aggro=CombatState.ReadyFlash(),CombatHasAggro()
        touchState.combat,touchState.weapon=CombatState.InCombat(),CombatState.GetWeapon()
        touchState.combatCharge=combatMoves_ and combatMoves_.charge or 0
        touchState.canMount=M.dragonAwake and not ride.locked and ride.mode=="free" and ride.onGround and ride:NearDragon()<3.6
        touchState.cool,touchState.cooldown,touchState.charging=caster_.cool,cooldown,caster_.charging
        touchState.charge=caster_.charging and caster_.charge or 0
        return touchState
    end,function(on)
        pointer:Release("touch-mode")
        drag.buttons=0
        caster_.charging,caster_.charge=false,0
    end,function()
        combatInputBlocked=true
        if combatMoves_ and not combatMoves_.dead and combatMoves_.clip~='getup' then combatMoves_:Cancel('touch-clear') end
        caster_.charging,caster_.charge=false,0
        if M.stream then M.stream:Stop(true) end
    end)
    VoidRewind.Attach(HUD.root)
    DebugLog.RegisterProbe('Ruins',function()
        local pieces=0
        for _,object in ipairs(Puzzles.list) do pieces=pieces+#object.pieces end
        return {volumes=world_:GetVolumeCount(),pieces=pieces,particles=fx_.motesB:Count()+fx_.motesG:Count(),awake=M.dragonAwake}
    end)
    PerformanceHUD.Attach(HUD.root)
    SettingsMenu.Attach(HUD.root,function(blocked)
        pointer:SetBlocked(blocked or M.debugOn==true)
        TouchControls.Cancel()
        drag.buttons=0
        caster_.charging,caster_.charge=false,0
        if M.stream then M.stream:Stop(true) end
    end)
end

-- ---------------------------------------------------------------- 启动
function M.Start()
    hudClockMinute,hudClockPhase=nil,nil
    CombatState.ResetIsolation()
    Safe('GC.Start',StartSceneGC)
    voidInputBlocked=false
    combatInputBlocked=false
    combatNoticeAt=0
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
    -- 碎石堆独立材质也要接收霜冻等全局材质参数
    if Puzzles.gateMaterial ~= nil then M.surfaceMaterials.gateRubble = Puzzles.gateMaterial end
    world_:OptimizeBroadPhase()
    Puzzles.On(OnPuzzle)

    nomi_ = Nomi.New(scene_, world_, M.SPAWN, 0)
    if not ForgeShowroom.Active() then renderer:SetViewport(0, Viewport:new(scene_, nomi_:Camera())) end
    fx_ = Spells.NewFX(scene_, nomi_:CameraNode())
    handMotes_=require('dragon.VoxelFX').WorldMotes(fx_.root,'CombatHandMotes',32,'square',true,nomi_:CameraNode())
    M.sigils=Sigil.New(scene_)
    caster_ = Spells.NewCaster({ world = world_, puzzles = Puzzles, scene = scene_, fx = fx_, sigils = M.sigils,
        handPos = function() return nomi_:HandPos() end,
        prepareCast = function(aim) nomi_:PrepareCast(aim) end }) -- 同帧转身与抬手
    combatRig_=WeaponRig.New(scene_,world_,nomi_)
    nomi_.ignoreAimVolume=IsCombatVisualVolume
    CombatState.Configure({rig=combatRig_,weapon=combatRig_.active,aggro=CombatHasAggro,
        cancel=function(reason)
            if reason=='manual' or reason=='aggro' or reason=='quiet' or reason=='weapon' or reason=='attack' then
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
    SetupDragon()
    StartCombat()
    nomi_.onVoidReturn=function(pos)
        CombatState.Exit('void')
        TouchControls.Cancel()
        caster_.charging,caster_.charge=false,0
        drag.buttons=0
        voidInputBlocked=true -- PC 仍物理按住的键必须松开，不能返回后自动施法/继续跑落崖
        M.ride.pos=pos
        M.ride.vy,M.ride.speed=0,0
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
        TouchControls.Cancel()
        Safe('Touch.Sync',TouchControls.Sync)
        caster_.charging,caster_.charge=false,0
        drag.buttons=0
        if M.stream then M.stream:Stop(true) end
        return true
    end

    sleepBase.valid = false
    -- 龙体是纯视觉部件，不让瞄准 Grid 把它当成可破坏场景。
    for _, part in pairs(M.rig.parts) do
        if part.volume then part.volume.collisionLayer = 2; part.volume.collisionMask = 0 end
    end
    nomi_.aimMask = 0xffffffff & ~2
    HUD.Build(Spells.SPELLS)
    AttachTouchControls()
    SetStage("gate")
    HUD.SetHint(resumeHint .. "  ·  F10 设置 · H 隐藏说明")
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
    if VoidRewind.IsActive() then return end
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
    if voidInputBlocked or SettingsMenu.IsBlocked() or ForgePanel.IsOpen() or TouchInput.IsEnabled() then return end
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
    if voidInputBlocked or SettingsMenu.IsBlocked() or ForgePanel.IsOpen() or TouchInput.IsEnabled() then return end
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
    if SettingsMenu.IsBlocked() or ForgePanel.IsOpen() then return end
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
    if combatTest_ and combatTest_.active and eventData:GetInt('Key')~=KEY_F11 then
        Safe('Debug.F11Stop',combatTest_.Stop,combatTest_,'key') -- deliberately continue dispatching the original key
    end
    if ForgePanel.IsOpen() then return end -- ForgePanel owns Escape and its release latch.
    local menuKey=eventData:GetInt("Key")
    if menuKey==KEY_F10 and not M.DEBUG_PANEL then
        if not eventData:GetBool("Repeat") and not voidInputBlocked then SettingsMenu.Toggle() end
        return
    end
    if menuKey==KEY_ESCAPE and SettingsMenu.IsOpen() then SettingsMenu.Close(); return end
    if SettingsMenu.IsBlocked() then return end
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
        if combatTest_ and combatTest_.active then Safe('Debug.F11Stop',combatTest_.Stop,combatTest_,'focus') end
        combatInputBlocked=true
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
    CombatHUD.Say('训练木桩 · C 拔刃后攻击')
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
            combatMoves_.dodgeCool,combatMoves_.hitstop=0,0
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
local function UpdateAim()
    local aim = nomi_:Aim(60.0)
    if aim.hit then aim.object = aim.object or Puzzles.FindByVolume(aim.volume) end
    M.aim = aim
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
            local actions=(obj.canShatter and "  [左键 碎时]" or "")..(obj.canRewind and "  [Q 回溯]" or "")
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
    -- F7 owns number keys and pointer input; do not emit rejected-spell banners.
    if animPreview_.index>0 or M.mounted or voidInputBlocked then caster_.charging,caster_.charge=false,0; return end
    if not CombatState.CanUseTime() then
        caster_.charging,caster_.charge=false,0
        -- Q is reserved for weapon swap in combat; E/1/2/3 remain rejected spells.
        if time_>=combatNoticeAt and (Press(KEY_E) or Press(KEY_1) or Press(KEY_2) or Press(KEY_3)) then
            caster_:Say(CombatState.InCombat() and '战斗中无法使用时间之力' or '时间之力恢复中',1.2)
            combatNoticeAt=time_+1.2
        end
        return
    end
    if combatInputBlocked then caster_.charging,caster_.charge=false,0; return end
    local testInput = M.fake ~= nil or M.fakePress ~= nil
    if voidInputBlocked or M.debugOn or TouchControls.IsBlocked() or (not TouchInput.IsEnabled() and not pointer:IsEnabled() and not testInput) then
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
    local allowed=not voidInputBlocked and not M.debugOn and not TouchControls.IsBlocked()
        and input.focus and not input.minimized
        and (TouchInput.IsEnabled() or pointer:IsEnabled() or M.fake~=nil)
    local f = (Down(KEY_W) and 1 or 0) - (Down(KEY_S) and 1 or 0)
    local r = (Down(KEY_D) and 1 or 0) - (Down(KEY_A) and 1 or 0)
    local tf,tr=TouchInput.MoveAxis()
    f,r=Clamp(f+tf,-1,1),Clamp(r+tr,-1,1)
    if animPreview_.index>0 then
        nomi_:Move(dt,0,0,false,false,false,{scale=0,motion=Vector3.ZERO}); return
    end
    if combatMoves_ then
        local touch=TouchInput.IsEnabled()
        local attack=TouchInput.Down('attack') or (not touch and pointer:CanAttack() and input:GetMouseButtonDown(MOUSEB_LEFT))
        local heavy=TouchInput.Down('heavy') or (not touch and pointer:CanAttack() and input:GetMouseButtonDown(MOUSEB_RIGHT))
        local angle=math.rad(nomi_.camYaw)
        local axis=Vector3(math.sin(angle)*f+math.cos(angle)*r,0,math.cos(angle)*f-math.sin(angle)*r)
        if animPreview_.index==0 then
            local controls={allowed=allowed and not combatInputBlocked,attack=attack,heavy=heavy,
                attackTap=TouchInput.Press('attack') and not attack,
                heavyTap=TouchInput.Press('heavy') and not heavy,
                dodge=CombatState.InCombat() and (Press(KEY_SHIFT) or TouchInput.Press('dodge')),axis=axis}
            if combatTest_ and combatTest_.active then
                local testOK,synthetic=Safe('Debug.F11Input',combatTest_.Input,combatTest_,dt,allowed and not CombatState.HasAggro() and not ForgePanel.IsOpen() and not SettingsMenu.IsBlocked())
                if synthetic then controls=synthetic; f,r=0,0 end
                if not testOK then
                    Safe('Debug.F11Stop',combatTest_.Stop,combatTest_,'input-error')
                    combatTest_.active=false;controls.allowed=false
                end
            end
            if not Safe('Combat.Moves',combatMoves_.Update,combatMoves_,dt,controls) then
                -- Do not repeat a stale lunge/hit window while moves are disabled.
                combatMoves_.motion=Vector3.ZERO
                combatMoves_.hitOpen,combatMoves_.hitPending,combatMoves_.iframe=false,false,false
            end
        end
        if CombatState.InCombat() or combatMoves_.dead or combatMoves_.clip=='getup' then
            nomi_:Move(dt,allowed and f or 0,allowed and r or 0,false,
                allowed and not combatInputBlocked and Press(KEY_SPACE),
                combatMoves_.clip=='bow_draw' or combatMoves_.clip=='bow_hold',
                {scale=allowed and not combatMoves_.slideMotionFrame and combatMoves_:MoveScale() or 0,motion=allowed and combatMoves_.motion or Vector3.ZERO,
                    facing=combatMoves_:Facing(),slideChecked=combatMoves_.slideMotionFrame})
            return
        end
    end
    if not allowed or animPreview_.index>0 then nomi_:Move(dt,0,0,false,false,false); return end
    nomi_:Move(dt, f, r, Down(KEY_SHIFT), Press(KEY_SPACE), caster_.charging or caster_.castAnim > 0)
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
        if previewAllowed and clip.id=='dodge_slide' then
            if Press(KEY_I) then params.moveX,params.moveZ,animPreview_.direction=0,1,'前'; changed=true end
            if Press(KEY_K) then params.moveX,params.moveZ,animPreview_.direction=0,-1,'后'; changed=true end
            if Press(KEY_J) then params.moveX,params.moveZ,animPreview_.direction=-1,0,'左'; changed=true end
            if Press(KEY_L) then params.moveX,params.moveZ,animPreview_.direction=1,0,'右'; changed=true end
            if Press(KEY_B) then params.bow=params.bow==1 and 0 or 1; changed=true end
            combatRig_:SetActive(params.bow==1 and 'bow' or 'sword'); combatRig_:SetPose(params.weaponInHand==1 and 'hand' or 'back')
        elseif previewAllowed and clip.id=='bow_hold' then
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

local function UpdateCombatActions(combatAllowed)
    if combatAllowed and animPreview_.index==0 and not combatMoves_.dead then
        if not CombatState.InCombat() and (Press(KEY_G) or TouchInput.Press('forge')) then OpenForge() end
        if Press(KEY_C) or TouchInput.Press('sheath') then
            if CombatState.InCombat() then CombatState.Exit('manual') else CombatState.Enter('manual') end
        end
        if CombatState.InCombat() and not combatInputBlocked then
            if Press(KEY_Q) or TouchInput.Press('swap') then
                Safe('Combat.Swap',combatMoves_.Swap,combatMoves_)
                CombatState.EndSwapPerf()
            end
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
        animPreview_.text=table.concat(lines,'\n')
    end
end

local function UpdateCombatAnimationParams()
    local p,pitch=combatMoves_:BowParameters(nomi_.camPitch)
    Safe('Animation.Params',combatAnim_.SetParam,combatAnim_,'weaponInHand',combatMoves_:WeaponInHand() and 1 or 0)
    Safe('Animation.Params',combatAnim_.SetParam,combatAnim_,'aimPitch',pitch)
    Safe('Animation.Params',combatAnim_.SetParam,combatAnim_,'p',p)
end

local function UpdateCombatRig(dt)
    if combatRig_ then
        if combatRig_.SetBowDraw then
            local p=(combatMoves_.clip=='bow_draw' or combatMoves_.clip=='bow_hold') and combatMoves_.charge or 0
            if animPreview_.index>0 then
                local id=CombatAnim.DebugList()[animPreview_.index].id
                p=(id=='bow_hold' or id=='bow_draw') and animPreview_.params.p or 0
            end
            combatRig_:SetBowDraw(p)
        end
        local offset,euler=combatAnim_:GetWeaponPose()
        combatRig_:SetSwing(offset,euler)
        local slidePosition,slideRotation
        if combatRig_.GetAfterimagePose then slidePosition,slideRotation=combatRig_:GetAfterimagePose() end
        local slideImages=combatMoves_:SlideAfterimages(slidePosition,slideRotation)
        if combatRig_.SetTrail then combatRig_:SetTrail(not combatLowQuality_ and (CombatState.InCombat() or animPreview_.index>0)) end
        if combatRig_.SetCombatVisual then
            combatRig_:SetCombatVisual(CombatState.GetWeapon()=='sword' and combatMoves_.hitOpen,
                combatMoves_.clip=='sword_heavy_charge' and combatMoves_.charge or nil)
        end
        combatRig_:SetAfterimages(combatLowQuality_ and emptyAfterimages_ or (#slideImages>0 and slideImages or combatAnim_:GetAfterimages()))
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
    if combatInputBlocked then
        local held=input:GetMouseButtonDown(MOUSEB_LEFT) or input:GetMouseButtonDown(MOUSEB_RIGHT)
            or TouchInput.Down('shatter') or TouchInput.Down('attack') or TouchInput.Down('heavy')
        for _,key in ipairs({KEY_1,KEY_2,KEY_3,KEY_E,KEY_Q,KEY_SHIFT}) do held=held or Down(key) end
        if not held then combatInputBlocked=false end
    end
    if VoidRewind.IsActive() then Safe('FX.VoidRewind',VoidRewind.Update,dt) end
    if voidInputBlocked and not VoidRewind.IsActive() then
        local held=input:GetMouseButtonDown(MOUSEB_LEFT) or input:GetMouseButtonDown(MOUSEB_RIGHT) or input:GetMouseButtonDown(MOUSEB_MIDDLE)
        for _,key in ipairs({KEY_W,KEY_A,KEY_S,KEY_D,KEY_SHIFT,KEY_SPACE,KEY_1,KEY_2,KEY_3,KEY_E,KEY_Q,KEY_F,KEY_T,KEY_TAB,KEY_F10}) do
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
    if TouchInput.IsEnabled() and not voidInputBlocked and not M.debugOn and not TouchControls.IsBlocked() then nomi_:Look(tx*.14,ty*.12,combatLookScale_) end
    if M.DEBUG_PANEL and not SettingsMenu.IsBlocked() and not ForgePanel.IsOpen() and Press(KEY_F10) then M.ToggleDebugPanel() end
    if not voidInputBlocked and not SettingsMenu.IsBlocked() and not ForgePanel.IsOpen() and Press(KEY_TAB) then farView = not farView end
    if not voidInputBlocked and not TouchInput.IsEnabled() and mouseLocked and pointer:CanLook(false) then
        local mm = input.mouseMove
        if animPreview_.index>0 then
            animPreview_.orbit=Clamp((animPreview_.orbit or 0)+mm.x*.12,-25,25)
        else nomi_:Look(mm.x, mm.y, 0.12*combatLookScale_) end
    end
    -- 龙
    local ctrl = M.ctrl
    M.ride.externalGround = nomi_.cc.onGround
    Safe('Dragon.Ride',M.ride.Update,M.ride,dt,nomi_.camYaw)
    -- Observe mounting in the same Update before rendering; do not clear the
    -- touch mount edge before DragonRide consumes it.
    Safe('Combat.MountState',CombatState.SetMounted,M.ride.mode~='free')
    Safe('Combat.State',CombatState.Update,dt)
    Safe('Audio.Listener',CombatAudio.SetListenerPosition,nomi_:Position()); Safe('Audio.Update',UpdateCombatAudio,dt)
    local combatAllowed=M.ride.mode=='free' and not voidInputBlocked and not M.debugOn
        and not TouchControls.IsBlocked() and input.focus and not input.minimized
        and (TouchInput.IsEnabled() or pointer:IsEnabled() or M.fake~=nil)
    if combatTest_ and combatTest_.active and (not combatAllowed or ForgePanel.IsOpen() or SettingsMenu.IsBlocked()) then Safe('Debug.F11Stop',combatTest_.Stop,combatTest_,'blocked/menu') end
    Safe('Debug.Keys',HandleCombatDebugKeys,combatAllowed and not combatMoves_.dead)
    if not Safe('Debug.F7',UpdateCombatPreview,dt,combatAllowed) and animPreview_.index>0 then
        animPreview_.index,animPreview_.text=0,nil
        CombatState.SetBusy(false)
        Safe('Combat.Cancel',combatMoves_.Cancel,combatMoves_,'preview-error')
    end
    Safe('Combat.Actions',UpdateCombatActions,combatAllowed)
    if combatEnemies_ and not voidInputBlocked and animPreview_.index==0 then Safe('Enemies.Update',combatEnemies_.Update,combatEnemies_,dt,nomi_:Position()) end
    if trainingDummy_ then Safe('Debug.Dummy',trainingDummy_.Update,trainingDummy_) end
    if combatArrows_ then Safe('Arrows.Update',combatArrows_.Update,combatArrows_,dt) end
    if combatParticles_ then Safe('Particles.Update',combatParticles_.UpdateOwner,combatParticles_,hitParticleOwner_,dt) end
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
            M.ride.aiOff = false
        end
    end
    Safe('Dragon.SleepPose',ApplySleepPose,dt)
    Safe('Dragon.World',M.dragonWorld.Update,M.dragonWorld,dt)
    -- 谜题 / 法术
    local aim = (not M.mounted) and UpdateAim() or { hit = false, dir = Vector3.FORWARD, far = Vector3.ZERO }
    Safe('Spells.Input',HandleSpells,dt,aim)
    Safe('Spells.Update',caster_.Update,caster_,dt)
    -- 法阵、手光读取本帧骨骼；不再先画特效再更新手臂。
    if M.ride.mode == "free" then Safe('Animation.Base',nomi_.Animate,nomi_,combatMoves_.hitstop>0 and 0 or dt,caster_.charging or caster_.castAnim > 0 or combatMoves_:WeaponInHand()) end
    if combatAnim_ and animPreview_.index==0 then
        Safe('Animation.BowParameters',UpdateCombatAnimationParams)
    end
    if combatAnim_ and (CombatState.InCombat() or combatMoves_.dead or combatMoves_.clip=='getup' or animPreview_.index>0) then Safe('Animation.Apply',combatAnim_.Apply,combatAnim_) end
    Safe('Debug.F7HUD',UpdateCombatPreviewText)
    Safe('Rig.Visuals',UpdateCombatRig,dt)
    if animPreview_.index==0 then Safe('Combat.AfterPose',combatMoves_.AfterPose,combatMoves_) end
    -- 法阵只更新一次，在 PostUpdate 中使用本帧最终相机与施法方向。
    Safe('Puzzles.Update',Puzzles.Update,dt)
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
        Safe('Sky.Atmosphere',M.atmosphere.Update,M.atmosphere,dt,M.mounted and M.rig.root.worldPosition or nomi_.node.worldPosition,Terrain.groundMaterial)
    end
    local clockMinute,clockPhase=math.floor(dn.hour*60),dn:PhaseName()
    if hudClockMinute~=clockMinute or hudClockPhase~=clockPhase then
        hudClockMinute,hudClockPhase=clockMinute,clockPhase
        HUD.SetClock(dn:ClockText())
    end
    -- 法阵灯：苏醒后常亮；夜里本来就有一点微光
    M.courtLight.brightness = 2.2 * M.runeK + 0.6 * (dn.nightK or 0)
    -- 草：诺米 / 龙脚下压开
    Terrain.SetInteractor(0, nomi_:Position(), 0.6)
    Terrain.SetInteractor(1, M.rig.root.worldPosition, (M.rig.size or 1) * 2.2)
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
    if mouseLocked then
        local h = M.ride.hint
        if M.ride.locked or M.ride.mode == "free" and (h == nil or h:find("WASD")) then h = "" end
        HUD.SetHint(h)
    end
    Safe('Touch.Sync',TouchControls.Sync)
    -- 准星常驻，方便平时选中目标；调试面板打开时隐藏。
    HUD.SetCrossVisible(not M.debugOn)

end

local function UpdateBaseCamera(dt)
    if ForgeShowroom and ForgeShowroom.Active() then return end
    if animPreview_.index>0 and M.ride.mode=='free' then
        nomi_:UpdateCombatPreview(dt,animPreview_.view or 4,animPreview_.orbit or 0)
    elseif M.mounted or M.ride.mode ~= "free" then
        nomi_:UpdateCamera(dt, "mounted", M.rig.bones.chest)
    else
        local mode = farView and "far" or ((caster_.charging or caster_.castAnim > 0) and "aim" or "normal")
        if CombatState.InCombat() and not farView then
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
        combatCameraFrame_=combatCamera_:Update(dt,combatMoves_,CombatState.GetSetting('cameraFov'),CombatState.GetSetting('cameraShake'))
        if M.ride.mode=='free' and animPreview_.index==0 then
            local action=combatCameraFrame_
            local offset=combatMoves_:ShakeOffset()
            if CombatState.InCombat() then offset=offset+action.focus-cn.worldDirection*action.distance end
            if CombatState.InCombat() or offset:LengthSquared()>0 then nomi_:ApplyCombatOffset(offset) end
            if CombatState.InCombat() then
                -- The base library resets fov each frame. Merge impacts by maximum,
                -- not addition, so heavy hits cannot double the authored +2 degrees.
                local impact=not combatLowQuality_ and combatMoves_:FovOffset() or 0
                nomi_:Camera().fov=nomi_:Camera().fov+math.min(0,action.fov)+math.max(0,action.fov,impact)
            end
        end
end

-- Hide obstructed boundary samples; never paint a promise through a wall or void.
local function CombatRangeClear(source,point)
    local delta=point-source
    local length=delta:Length()
    if length<.001 then return true end
    local hit=nomi_:SlideRay(Ray(source,delta/length),length)
    return not hit or hit.distance>=length-.02
end
local function CombatRangeVisible(source,point)
    if not Terrain.HasGround(point.x,point.z,.05) then return false end
    local cn=nomi_:CameraNode()
    local p=cn.worldPosition;local f=cn.worldDirection
    if (point.x-p.x)*f.x+(point.y-p.y)*f.y+(point.z-p.z)*f.z<=0 then return false end
    return CombatRangeClear(source,point) and CombatRangeClear(p,point)
end

local function UpdateCombatHUD(cn)
        local enemies=CombatEnemies()
        local a,b=cn.worldPosition,cn.worldPosition+cn.worldDirection*60
        local hits=CombatHit.Query(enemies,a,b,.03)
        local wall=CombatCast(a,b)
        local aimed=hits[1] and (not wall or hits[1].t<wall) and hits[1].enemy or nil
        M.combat.aimed=aimed
        combatLookScale_=CombatState.InCombat() and combatCameraFrame_ and combatCameraFrame_.look or 1
        if CombatState.InCombat() and (combatMoves_.clip=='bow_draw' or combatMoves_.clip=='bow_hold') and CombatState.GetSetting('aimAssist') and CombatState.GetSetting('cameraFov') then
            local near=CombatHit.Query(enemies,a,b,.6)
            for _,candidate in ipairs(near) do
                if CombatHit.Visible(a,candidate.shape.center,CombatCast) then combatLookScale_=math.min(combatLookScale_,.65); break end
            end
        end
        local hud=combatHUDData
        hud.rangeVisible=CombatRangeVisible
        hud.moves,hud.combat,hud.mounted=combatMoves_,CombatState.InCombat(),M.ride.mode~='free'
        hud.weapon,hud.charge=CombatState.GetWeapon(),combatMoves_.charge
        hud.aimed,hud.enemies,hud.camera,hud.cameraNode=aimed,enemies,nomi_:Camera(),cn
        hud.bowCameraCharge=combatCameraFrame_ and combatCameraFrame_.cross or 0
        hud.debug=animPreview_.text or (time_<combatDebugUntil_ and combatDebugText_ or nil)
        hud.preview=animPreview_.index>0
        CombatHUD.Set(hud)
end

function Ruins_HandlePostUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    Safe('Camera.Base',UpdateBaseCamera,dt)
    local aim = M.aim or {hit=false,far=nomi_:HandPos()+nomi_.node.worldDirection*60}
    Safe('FX.Sigils',M.sigils.Update,M.sigils,dt,aim,nomi_:HandPos(),nomi_:CameraNode(),caster_,Spells.ShatterRadius(caster_.charge),not M.mounted and not M.debugOn and CombatState.CanUseTime())
    if combatMoves_ then
        local cn=nomi_:CameraNode()
        Safe('Camera.Combat',UpdateCombatCamera,dt,cn)
        Safe('HUD.Update',UpdateCombatHUD,cn)
    end
    Safe('FX.MotesB',fx_.motesB.Draw,fx_.motesB); Safe('FX.MotesG',fx_.motesG.Draw,fx_.motesG)
    Safe('FX.HandMotes',handMotes_.Draw,handMotes_)
end

function M.Stop()
    if combatTest_ and combatTest_.active then combatTest_:Stop('stop') end
    combatTest_=nil
    ForgePanel.Close(true)
    local forceClose=rawget(ForgePanel,'ForceClose')
    if type(forceClose)=='function' then forceClose() end
    if ForgeShowroom then ForgeShowroom.Exit() end -- teardown between panel fades
    if M.atmosphere then M.atmosphere:Stop() end
    DebugLog.RegisterProbe('Ruins',nil)
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
    if combatParticles_ then combatParticles_:ClearOwner(hitParticleOwner_); combatParticles_=nil end
    if combatEnemies_ then combatEnemies_:Destroy() end
    if combatAnim_ then combatAnim_:Stop(nil,0) end
    combatMoves_,combatAnim_,combatArrows_,combatEnemies_=nil,nil,nil,nil
    for _,entry in pairs(arrowNodes_) do entry.node:Remove() end
    arrowNodes_={}; animPreview_={index=0,t=0,params={moveX=0,moveZ=-1,bow=0,p=.5,weaponInHand=1},direction='后'}; CombatHUD.Set(nil)
    if combatRig_ and combatRig_.Dispose then combatRig_:Dispose() end
    combatRig_=nil
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
end

return M
