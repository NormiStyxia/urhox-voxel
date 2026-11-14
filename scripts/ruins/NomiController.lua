-- ====================================================================
-- NomiController.lua — 遗迹里的诺米：体素物理角色控制器 + 第三人称瞄准
--
-- 移动走 VoxelCharacterController（能站在冻结碎块、桥、台阶上，被墙挡住）。
-- 相机：越肩第三人称（ThirdPersonCamera 库），鼠标控制 yaw / pitch；屏幕中心十字准星即瞄准方向。
-- 瞄准射线：从相机出发打向世界（跳过诺米自己），得到命中点；施法起点是诺米右手。
-- 骑龙时由 DragonRide 接管（本模块只负责步行状态，DragonRide.Update 的 free 模式被替换）。
-- ====================================================================

require "urhox-libs.Camera.ThirdPersonCamera"
local BlockCharacter = require("game.BlockCharacter")
local NomiVoxelData = require("game.NomiVoxelData")
local TimeObject = require("ruins.TimeObject")
local DebugLog = require("ruins.DebugLog")
local Terrain = require("ruins.RuinsTerrain")
local Perf=require("combat.SwingPerf")

local M = {}

local WALK, RUN = 4.2, 7.2
local JUMP = 6.4
local AIR_CONTROL = 0.35

local function Clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
local function WrapDeg(a)
    while a > 180 do a = a - 360 end
    while a < -180 do a = a + 360 end
    return a
end

---@class NomiController
---@field node Node
---@field nomi table
---@field cc VoxelCharacterController
---@field cam ThirdPersonCameraInstance
---@field yaw number
---@field camYaw number
---@field camPitch number
---@field aimMask integer
---@field fallbackPos Vector3
---@field safePos Vector3
---@field safeT number
---@field onVoidReturn fun(pos:Vector3)|nil
---@field onVoidFall fun(pos:Vector3, forced:boolean):boolean|nil
---@field voidReturning boolean|nil
---@field castSocket Node
---@field combatFocus Vector3|nil
---@field ignoreAimVolume fun(volume:VoxelVolume):boolean|nil
local N = {}
N.__index = N

---@param scene Scene
---@param world VoxelPhysicsWorld
function M.New(scene, world, spawn, spawnYaw)
    local self = setmetatable({}, N)
    self.scene, self.world = scene, world
    self.node = scene:CreateChild("Nomi")
    self.node.worldPosition = spawn
    self.nomi = BlockCharacter.CreateVoxel(self.node, NomiVoxelData, BlockCharacter.SLENDER)
    -- Character owns the calibrated palm (±19,33,-.75), including its parent.
    -- Reuse it read-only: arm for legacy data, forearm for elbow data.
    self.castSocket = assert(self.nomi:HandSocket("right"), "Nomi right palm is unavailable")
    local cc = self.node:CreateComponent("VoxelCharacterController")
    cc.height = 1.65
    cc.radius = 0.32
    cc.supportRadius = 0.26
    -- 0.5m 石阶 + 5cm 余量；不放大步高，否则会把塔壁/时停跳台当普通台阶。
    cc.stepHeight = 0.55
    -- 合并台阶后仍有体素三角网格内部边，使用引擎接触剔除，不加每帧 Lua 探针。
    cc.enhancedInternalEdgeRemoval = true
    cc.maxSlopeAngle = 55
    cc.mass = 55
    cc.maxStrength = 60
    -- 非默认 mask 启用双向过滤，让飞行台阶的 mask=0 真正不阻挡角色。
    cc.collisionMask = 0xffffffff & ~2
    self.cc = cc
    self.yaw = spawnYaw or 0
    self.camYaw = spawnYaw or 0
    self.camPitch = 12
    self.speed = 0
    self.vel = Vector3(0, 0, 0)
    self.enabled = true
    self.fallbackPos = Vector3(spawn.x,spawn.y,spawn.z)
    self.safePos = Vector3(spawn.x,spawn.y,spawn.z)
    self.safeT = 0
    self.cam = ThirdPersonCamera.Create(scene, {
        modes = {
            normal = { distance = 4.6, offset = Vector3(0.55, 1.65, 0), fov = 55.0 },
            aim = { distance = 3.0, offset = Vector3(0.75, 1.6, 0), fov = 46.0 },
            combat = { distance = 5.0, offset = Vector3(.55,1.65,0), fov = 55 },
            combatBoss = { distance = 6.5, offset = Vector3(.55,1.65,0), fov = 55 },
            combatBow = { distance = 5.0, offset = Vector3(.85,1.65,0), fov = 55 },
            combatBossBow = { distance = 6.5, offset = Vector3(.85,1.65,0), fov = 55 },
            combatBowZoom = { distance = 5.0, offset = Vector3(.85,1.65,0), fov = 52 },
            combatBossBowZoom = { distance = 6.5, offset = Vector3(.85,1.65,0), fov = 52 },
            mounted = { distance = 13.0, offset = Vector3(0, 3.2, 0), fov = 55.0 },
            far = { distance = 26.0, offset = Vector3(0, 6.0, 0), fov = 55.0 },
        },
        transitionSpeed = 6.0,
        farClip = 600.0,
    })
    self.camTarget = scene:CreateChild("CamTarget")
    self.camTarget.position = spawn
    self.node.rotation = Quaternion(self.yaw, Vector3.UP)
    print(string.format("NomiController: spawn %.1f %.1f %.1f", spawn.x, spawn.y, spawn.z))
    self:InitSlideProbes()
    return self
end

function N:Camera() return self.cam:GetCamera() end
function N:CameraNode() return self.cam:GetNode() end
function N:Position() return self.node.worldPosition end

-- 右手掌心位置；与骨骼动画和角色世界变换保持一致。
function N:HandPos()
    return self.castSocket.worldPosition
end

-- 单次 E/Q 也先面向目标并摆好手臂，再读取同帧掌心发射点。
---@param aim table
function N:PrepareCast(aim)
    local target = aim.hit and aim.pos or aim.far --[[@as Vector3]]
    local delta = target - self.node.worldPosition
    if delta.x * delta.x + delta.z * delta.z > .001 then
        self.yaw = math.deg(math.atan(delta.x, delta.z))
        self.node.worldRotation = Quaternion(self.yaw, Vector3.UP)
    end
    self.nomi.armed = 1
    self:Animate(0, true)
end

-- 鼠标视角
function N:Look(dx, dy, sens)
    if math.abs(dx)+math.abs(dy)>.001 then self.combatLookQuiet=.25 end
    self.camYaw = self.camYaw + dx * sens
    self.camPitch = Clamp(self.camPitch + dy * sens, -55, 70)
end

-- Read after the previous physics step, before writing the next intention.
-- Run phase/blocked detection follow actual displacement, never desired speed.
function N:MeasureMotion(dt)
    local p=self.node.worldPosition
    local delta=self.measuredPosition and p-self.measuredPosition or Vector3.ZERO
    self.actualDt=math.max(.001,self.measuredDt or dt)
    self.actualVelocity=delta/self.actualDt
    self.actualSpeed=Vector3(self.actualVelocity.x,0,self.actualVelocity.z):Length()
    self.frameTravel=Vector3(delta.x,0,delta.z):Length()
    self.measuredPosition,self.measuredDt=p,dt
end

-- 移动输入（f, r ∈ [-1,1]）
function N:Move(dt, f, r, run, jump, aiming, combat)
    if self:UpdateSafety(dt) then return end
    local cc = self.cc
    local rad = math.rad(self.camYaw)
    local fwd = Vector3(math.sin(rad), 0, math.cos(rad))
    local right = Vector3(math.cos(rad), 0, -math.sin(rad))
    local dir = fwd * f + right * r
    local moveAmount = math.min(1,dir:Length())
    local moving = dir:LengthSquared() > 0.01
    if moving then dir = dir:Normalized() end
    local target = moving and ((run and not aiming) and RUN or (aiming and WALK * 0.6 or WALK)) or 0
    if combat then target=moving and (combat.baseSpeed or 5)*(combat.scale or 1) or 0 end
    local onGround = cc.onGround
    local want = dir * target * moveAmount
    if combat and combat.runDistance~=nil then
        want=(combat.runDirection or dir)*(combat.runDistance/math.max(.001,dt))
    end
    if jump and onGround and combat and combat.sprintJump then
        local carry=self.actualVelocity or self.vel
        want=Vector3(carry.x,0,carry.z) -- preserve takeoff; subsequent air frames use AIR_CONTROL
    end
    local k = onGround and (1 - math.exp(-12 * dt)) or (1 - math.exp(-12 * AIR_CONTROL * dt))
    self.vel = self.vel:Lerp(want, k)
    cc.desiredVelocity = Vector3(self.vel.x, 0, self.vel.z)
    if combat then
        -- Animation supplies metres, never teleports the actor. The controller
        -- still resolves walls/steps. Sample the entire path, not only its end.
        self.vel=onGround and (not combat.explore or combat.runDistance~=nil or combat.scale==0 or combat.sprintJump) and want or self.vel
        local motion=combat.motion or Vector3.ZERO
        local length=motion:Length()
        local p=self.node.worldPosition
        local fraction=1
        local steps=combat.slideChecked and 0 or math.max(1,math.ceil(length/.12))
        for i=1,steps do
            local q=p+motion*(i/steps)
            if not Terrain.HasGround(q.x,q.z,.4) then fraction=(i-1)/steps; break end
        end
        cc.desiredVelocity=self.vel+motion*(fraction/math.max(dt,.001))
    end
    if jump and onGround and (not combat or combat.scale>0) then cc:Jump(JUMP) end
    -- 朝向：瞄准时面朝相机方向；否则面朝移动方向
    local wantYaw = self.yaw
    if aiming then wantYaw = self.camYaw
    elseif moving then wantYaw = math.deg(math.atan(dir.x, dir.z)) end
    if combat and combat.facing then wantYaw=math.deg(math.atan(combat.facing.x,combat.facing.z)) end
    if combat and combat.sprinting then
        self.yaw=self.yaw+Clamp(WrapDeg(wantYaw-self.yaw),-540*dt,540*dt)
    else self.yaw = self.yaw + WrapDeg(wantYaw - self.yaw) * (1 - math.exp(-14 * dt)) end
    self.node.rotation = Quaternion(self.yaw, Vector3.UP)
    self.speed = Vector3(self.vel.x, 0, self.vel.z):Length()
    self.onGround = onGround
end

-- Probe actual collision surfaces (including rebuilt bridge), not the aim
-- resolver's expensive per-volume repair path. Both sides' masks match the CC.
function N:SlideRay(ray,distance,purpose)
    if purpose=='range' then Perf.rangeRays=Perf.rangeRays+1 else Perf.motionRays=Perf.motionRays+1 end
    local nearest=nil ---@type VoxelRaycastResult|nil
    for _,hit in ipairs(self.world:Raycast(ray,distance,self.cc.collisionMask)) do
        local volume=hit.volume
        if hit.hit and volume and (volume.collisionMask & self.cc.collisionLayer)~=0
            and not (self.ignoreAimVolume and self.ignoreAimVolume(volume))
            and (not nearest or hit.distance<nearest.distance) then nearest=hit end
    end
    return nearest
end
-- Closures and fixed query records are created once per controller, not per move.
function N:InitSlideProbes()
    if self.slideGroundPort then return end
    self.groundPool={};self.sweepPool={}
    for i=1,256 do self.groundPool[i]={} end
    for i=1,24 do self.sweepPool[i]={} end
    self.slideGroundPort=function(p) return self:SlideGround(p) end
    self.slideClearPort=function(a,b,margin) return self:SlideClear(a,b,margin) end
end
function N:SlideGround(p)
    local pool=self.groundScope and self.groundPool or nil
    for i=1,pool and (self.groundCount or 0) or 0 do
        local c=pool[i]
        if c.x==p.x and c.y==p.y and c.z==p.z then return c.h,c.n end
    end
    local hit=self:SlideRay(Ray(p+Vector3(0,.35,0),Vector3(0,-1,0)),.75)
    local h,n=hit and hit.position.y,hit and hit.normal.y
    local index=(self.groundCount or 0)+1
    if pool and pool[index] then
        local c=pool[index];c.x,c.y,c.z,c.h,c.n=p.x,p.y,p.z,h,n
        self.groundCount=index
    end
    return h,n
end
function N:CanSlide()
    if not self.cc.onGround then return false end
    self:InitSlideProbes();self.groundCount=0;self.groundScope=true
    local C=require('combat.CombatMoves')
    local supported=C.SlideFootprint(self.node.worldPosition,self.cc.radius,self.slideGroundPort)~=nil
    self.groundCount=0;self.groundScope=false
    return supported
end
---@param a Vector3
---@param b Vector3
---@param margin number
function N:SlideClear(a,b,margin)
    local delta=b-a --[[@as Vector3]]
    local length=delta:Length()
    if length<1e-8 then return true end
    local direction=delta/length
    local start=self.sweepStart
    local along=(a-start):DotProduct(self.sweepDirection)
    -- Only straight, level subsegments can share the longer ray. Steps/slopes
    -- use the original 24 probes at their actual height/direction.
    local flat=a.y==b.y and direction:DotProduct(self.sweepDirection)>1-1e-10
    for i=0,7 do
        local angle=i*math.pi/4
        local offset=Vector3(math.sin(angle)*margin,0,math.cos(angle)*margin)
        for level=1,3 do
            local h=level==1 and .25 or (level==2 and self.cc.height*.5 or self.cc.height-.10)
            local origin=a+offset+Vector3(0,h,0)
            local c=self.sweepPool[i*3+level]
            local distance
            -- Scope is a single synchronous ClipSlidePath, with no world edits
            -- or callbacks other than these probes; never cache across frames.
            if flat and c.y==origin.y and c.from and along>=c.from and along+length<=c.to+1e-7
                and (not c.hit or c.hit>=along-1e-7) then
                distance=c.hit and c.hit-along
            else
                local reach=flat and math.max(length,self.sweepLength-along) or length
                local hit=self:SlideRay(Ray(origin,direction),reach)
                distance=hit and hit.distance
                if flat then
                    c.y,c.from,c.to,c.hit=origin.y,along,along+reach,distance and along+distance
                else c.from=nil end
            end
            if distance and distance<=length then return false end
        end
    end
    return true
end
function N:ClipSlideMotion(motion,maxSteps)
    maxSteps=maxSteps or 24 -- full authored 2.2m slide fits; melee uses eight
    local C=require('combat.CombatMoves')
    self:InitSlideProbes()
    self.groundScope=true;self.groundCount=0
    for _,c in ipairs(self.sweepPool) do c.from=nil end
    self.sweepStart=self.node.worldPosition
    local flat=Vector3(motion.x,0,motion.z)
    self.sweepLength=math.min(flat:Length(),(maxSteps or math.huge)*.10)
    self.sweepDirection=flat:LengthSquared()>1e-16 and flat:Normalized() or Vector3.FORWARD
    local moved,blocked,debt=C.ClipSlidePath(self.sweepStart,motion,self.cc.radius,
        self.slideGroundPort,self.slideClearPort,maxSteps)
    self.groundScope=false;self.groundCount=0 -- external probes never observe this call's snapshots
    return moved,blocked,debt
end

-- Snap before hit_on; camera yaw stays untouched even for a full body turn.
function N:AssistMelee(enemies,cast,intent,enabled)
    local direction,target=intent,nil
    if enabled then direction,target=require('combat.CombatMoves').SelectMeleeTarget(self:Position(),intent,enemies,cast) end
    self.yaw=math.deg(math.atan(direction.x,direction.z))
    self.node.rotation=Quaternion(self.yaw,Vector3.UP)
    return direction,target
end

-- 仅 Scene 的徒步路径调用；骑乘/上下龙过渡不作坠落判定。
---@return boolean recovered
function N:UpdateSafety(dt)
    if self.voidReturning then return true end -- transition owns movement until reveal finishes
    local p=self.node.worldPosition
    local inVoid=not Terrain.HasGround(p.x,p.z)
    local stranded=inVoid and self.cc.onGround and p.y<Terrain.RING_Y-2
    local forced=stranded or p.y<Terrain.ISLAND.hardFallY or (p.y<Terrain.ISLAND.fallY and inVoid)
    if (inVoid or forced) and self.onVoidFall and self.onVoidFall(p,forced) then
        self.voidReturning=true
        self.vel=Vector3.ZERO
        self.cc.desiredVelocity=Vector3.ZERO
        return true
    end
    if forced then
        self:ReturnFromVoid()
        return true
    end
    if self.cc.onGround and Terrain.IsSafeGround(p.x,p.y,p.z) then
        self.safeT=self.safeT+dt
        if self.safeT>=.4 then
            self.safePos=Vector3(p.x,p.y+.04,p.z)
            self.safeT=0
        end
    else self.safeT=0 end
    return false
end

-- Original safety result, shared by immediate fallback and the black-screen callback.
function N:ReturnFromVoid()
    local safe=self.safePos
    if not safe or not Terrain.IsSafeGround(safe.x,safe.y,safe.z) then safe=self.fallbackPos end
    self.cc.desiredVelocity=Vector3.ZERO
    self.cc:SetLinearVelocity(Vector3.ZERO)
    self.cc:Teleport(safe)
    self.vel=Vector3.ZERO
    self.speed,self.safeT,self.onGround=0,0,false
    self.camTarget.position=Vector3(safe.x,safe.y,safe.z)
    self:UpdateCamera(1,"normal",self.node)
    if self.onVoidReturn then self.onVoidReturn(safe) end
end

-- Debug-only caller supplies a terrain- and building-validated permanent point.
function N:TeleportForCombatDebug(pos,yaw)
    if not Terrain.IsSafeGround(pos.x,pos.y,pos.z) then return false end
    self.cc.desiredVelocity=Vector3.ZERO
    self.cc:SetLinearVelocity(Vector3.ZERO)
    self.cc:Teleport(pos)
    self.vel=Vector3.ZERO; self.speed,self.safeT,self.onGround=0,0,false
    self.safePos=Vector3(pos.x,pos.y,pos.z)
    self.yaw,self.camYaw,self.camPitch=yaw,yaw,12
    self.node.rotation=Quaternion(yaw,Vector3.UP)
    self.camTarget.position=pos
    self:UpdateCamera(1,'normal',self.node)
    return true
end

function N:GroundFeet(foot,dt,active)
    if not self.soleGroundPort then
        self.soleGroundPort=function(world)
            return self:SlideGround(Vector3(world.x,self.node.worldPosition.y,world.z))
        end
    end
    foot:Ground(dt,self.soleGroundPort,active,self.cc.onGround)
end

function N:Animate(dt, casting)
    self.nomi:Update(dt, { moveSpeed = self.onGround and (self.actualSpeed or self.speed) or 0, onGround = self.onGround, armed = casting, aiming = casting,
        aimPitch = self.camPitch })
end

-- Only framing changes; player yaw/pitch are never steered toward an enemy.
function N:SetCombatCamera(target,boss,bow,zoom)
    self.combatFocus=target
    self.combatCameraMode=(boss and 'combatBoss' or 'combat')..(bow and ('Bow'..(zoom and 'Zoom' or '')) or '')
end
-- Isolated F7 orbit through the same camera library and voxel obstruction guard.
-- Gameplay yaw/pitch and follow state are preserved for the next normal frame.
function N:UpdateCombatPreview(dt,view,orbit)
    self.cam:SetModeConfig('combatPreview',{distance=2.6,offset=Vector3(0,1.2,0),fov=45})
    self.cam:SetTransitionSpeed(1000); self.cam:SetMode('combatPreview')
    local saved=self.camTarget.position
    self.camTarget.position=self.node.worldPosition
    local angle=({180,90,0,135})[view or 4] or 135
    self.cam:Update(dt,self.camTarget,self.yaw+angle+(orbit or 0),6)
    self.camTarget.position=saved
    self.combatCameraOrigin=self.node.worldPosition+Vector3(0,1.2,0)
    self:ApplyCombatOffset(Vector3.ZERO)
end
function N:ClipAttackMotion(motion)
    if not self.cc.onGround then return Vector3.ZERO end
    -- Rebuilt bridges are real collision ground even inside Terrain's void mask.
    -- Use the same <=.10m footprint/slope/wall sweep as the accepted slide.
    return self:ClipSlideMotion(motion,8)
end
function N:ApplyCombatOffset(offset)
    local cn=self:CameraNode()
    local origin=self.combatCameraOrigin
    if not origin then return end
    local delta=cn.position+offset-origin
    local length=delta:Length()
    if length<.001 then return end
    local hit=self:GridHit(Ray(origin,delta/length),length)
    if hit.hit and hit.distance<length then
        cn.position=origin+delta*(math.max(0,hit.distance-.3)/length)
    else cn.position=cn.position+offset end
end
function N:UpdateCamera(dt, mode, followNode)
    local fighting=mode=='combat'
    if fighting then mode=self.combatCameraMode or 'combat' end
    self.cam:SetTransitionSpeed(fighting and 1/.18 or 6)
    self.cam:SetMode(mode or "normal")
    local tgt = followNode or self.node
    -- 相机目标平滑跟随（避免台阶上颠）
    local p = tgt.worldPosition
    self.combatLookQuiet=math.max(0,(self.combatLookQuiet or 0)-dt)
    local focus=Vector3.ZERO
    if fighting and self.combatFocus and self.combatLookQuiet<=0 then
        local toward=self.combatFocus-p --[[@as Vector3]]
        -- Ignore offscreen/remote targets instead of pulling framing behind the player.
        local forward=Quaternion(self.camYaw,Vector3.UP)*Vector3.FORWARD
        if toward:Length()<20 and toward:DotProduct(forward)>0 then focus=toward*.3 end
    end
    self.combatFocusOffset=(self.combatFocusOffset or Vector3.ZERO):Lerp(focus,1-math.exp(-dt/.25))
    if fighting then p=p+self.combatFocusOffset end
    local cur = self.camTarget.position
    local k = 1 - math.exp(-14 * dt)
    local ny = cur.y + (p.y - cur.y) * (1 - math.exp(-8 * dt))
    self.camTarget.position = Vector3(cur.x + (p.x - cur.x) * k, ny, cur.z + (p.z - cur.z) * k)
    self.cam:Update(dt, self.camTarget, self.camYaw, self.camPitch)
    -- 体素世界里的相机防穿墙（库只查 Bullet PhysicsWorld，这里补一条体素射线）
    local cn = self.cam:GetNode()
    local aimPoint = self.camTarget.position + Quaternion(self.camYaw, Vector3.UP) * ((mode == "aim") and Vector3(0.75, 1.6, 0) or Vector3(0.55, 1.65, 0))
    if fighting and mode:find('Bow',1,true) then aimPoint=self.camTarget.position+Quaternion(self.camYaw,Vector3.UP)*Vector3(.85,1.65,0) end
    self.combatCameraOrigin=aimPoint
    if mode == "mounted" then aimPoint = self.camTarget.position + Vector3(0, 3.2, 0) end
    local d = cn.position - aimPoint
    local len = d:Length()
    if len > 0.3 then
        local hit = self.world:RaycastSingle(Ray(aimPoint, d * (1.0 / len)), len)
        if hit.hit and hit.distance < len then
            cn.position = aimPoint + d * (math.max(0.4, hit.distance - 0.3) / len)
        end
    end
end

-- 从当前 Grid 核对真实实心格，不把空气包围盒或动态凸包当成遮挡。
-- 相机 -> [空气 | 实心格]；高坐标面负向进入时属于 n-1，不属于网格外的 n。
-- 入口/步进用 Lua 标量保留精度；不靠微小世界位移选格，也不把越界格强行夹回网格。
-- 整数边界按方向归属，棱角同时跨轴；空洞及旋转体积仍按当前 Grid。
local function GridSlab(o,d,n,axis,enter,exit,entryAxis,entrySign)
    if math.abs(d)<1e-8 then return enter,exit,entryAxis,entrySign,o>=0 and o<n end
    local a,b=-o/d,(n-o)/d
    local sign=-1
    if a>b then a,b=b,a;sign=1 end
    if a>enter then enter,entryAxis,entrySign=a,axis,sign end
    exit=math.min(exit,b)
    return enter,exit,entryAxis,entrySign,enter<=exit
end
local function GridFirstCell(o,d,n,axis,entryAxis,enter)
    local boundary=d>0 and -o or n-o
    if axis==entryAxis or (math.abs(d)>=1e-8 and boundary/d==enter) then return d>0 and 0 or n-1 end
    local p=o+d*enter
    return d<0 and math.ceil(p)-1 or math.floor(p)
end
local function GridNext(o,d,i,step)
    if math.abs(d)<1e-8 then return math.huge end
    return (i+(step>0 and 1 or 0)-o)/d
end
---@param volume VoxelVolume
---@param ray Ray
---@param maxDist number
---@param cellLimit number|nil
---@return VoxelRaycastResult|nil, boolean|nil exhausted
local function TraceVolume(volume, ray, maxDist, cellLimit)
    local node,grid=volume:GetNode(),volume:GetGrid()
    if node==nil or grid==nil then return nil end
    local size=volume.voxelSize
    if size<=0 then return nil end
    local localOrigin=node:WorldToLocal(ray.origin)
    -- 方向用逆旋转/缩放，不对两个世界坐标作差；远离原点时会丢失微小斜率。
    local rotated=node.worldRotation:Inverse()*ray.direction
    local scale=node.worldScale
    if math.abs(scale.x)<1e-8 or math.abs(scale.y)<1e-8 or math.abs(scale.z)<1e-8 then return nil end
    local ox,oy,oz=localOrigin.x/size,localOrigin.y/size,localOrigin.z/size
    local vx,vy,vz=rotated.x/scale.x/size,rotated.y/scale.y/size,rotated.z/scale.z/size
    local dims=grid:GetDimensions()
    local enter,exit=0,maxDist
    local entryAxis,sign,valid=0,0,true
    enter,exit,entryAxis,sign,valid=GridSlab(ox,vx,dims.x,1,enter,exit,entryAxis,sign)
    if not valid then return nil end
    enter,exit,entryAxis,sign,valid=GridSlab(oy,vy,dims.y,2,enter,exit,entryAxis,sign)
    if not valid then return nil end
    enter,exit,entryAxis,sign,valid=GridSlab(oz,vz,dims.z,3,enter,exit,entryAxis,sign)
    if not valid then return nil end
    local normal=Vector3(entryAxis==1 and sign or 0,entryAxis==2 and sign or 0,entryAxis==3 and sign or 0)
    local x,y,z=GridFirstCell(ox,vx,dims.x,1,entryAxis,enter),GridFirstCell(oy,vy,dims.y,2,entryAxis,enter),GridFirstCell(oz,vz,dims.z,3,entryAxis,enter)
    local sx,sy,sz=vx>0 and 1 or -1,vy>0 and 1 or -1,vz>0 and 1 or -1
    local tx,ty,tz=GridNext(ox,vx,x,sx),GridNext(oy,vy,y,sy),GridNext(oz,vz,z,sz)
    local dx,dy,dz=math.abs(1/vx),math.abs(1/vy),math.abs(1/vz)
    local distance=enter
    for i=1,dims.x+dims.y+dims.z+3 do
        if x<0 or y<0 or z<0 or x>=dims.x or y>=dims.y or z>=dims.z or distance>exit then break end
        if cellLimit and Perf.cells>=cellLimit then return nil,true end
        Perf.cells=Perf.cells+1
        if grid:IsSolid(x,y,z) then
            local result=VoxelRaycastResult:new()
            result.hit,result.volume,result.volumeId=true,volume,volume.volumeId
            result.distance,result.position=distance,ray.origin+ray.direction*distance
            result.normal=node.worldRotation*normal
            result.voxel=IntVector3(x,y,z)
            result.material=math.floor(grid:GetVoxelMaterial(x,y,z))
            result.paletteDomain=volume:GetPaletteDomain()
            return result
        end
        local nextDistance=math.min(tx,ty,tz)
        distance=nextDistance
        -- 同时跨越角/棱上的轴，不把仅擦过的格当成有厚度的墙。
        if tx<=nextDistance+1e-6 then x=x+sx; tx=tx+dx; normal=Vector3(-sx,0,0) end
        if ty<=nextDistance+1e-6 then y=y+sy; ty=ty+dy; normal=Vector3(0,-sy,0) end
        if tz<=nextDistance+1e-6 then z=z+sz; tz=tz+dz; normal=Vector3(0,0,-sz) end
    end
    return nil
end

---@param hit VoxelRaycastResult
---@param ray Ray
local function EmptyOriginHit(hit,ray)
    if not hit.hit or hit.distance>.001 then return false end
    local volume=hit.volume
    local grid=volume:GetGrid()
    if grid==nil then return true end
    local node=volume:GetNode()
    if node==nil or volume.voxelSize<=0 then return true end
    local p=node:WorldToLocal(ray.origin+ray.direction*.0001)/volume.voxelSize
    local dims=grid:GetDimensions()
    local x,y,z=math.floor(p.x),math.floor(p.y),math.floor(p.z)
    return x<0 or y<0 or z<0 or x>=dims.x or y>=dims.y or z>=dims.z or not grid:IsSolid(x,y,z)
end

-- Cache is opt-in for synchronous read-only batches. World mutation has no
-- exposed engine revision, so callers must end the scope before hit callbacks,
-- physics, rebuilding terrain, or spawning/removing volumes. Default: uncached.
function N:BeginQueryScope()
    self.queryScope=true;self.queryCount=0;self.queryRevision=Perf.revision
    if not self.queryPool then
        self.queryPool={}
        for i=1,32 do self.queryPool[i]={} end
    end
end
function N:EndQueryScope() self.queryScope=false;self.queryCount=0 end
---@param ray Ray
---@param maxDist number
---@param decorative boolean|nil Budget rejection is opaque/blocked, never clear.
---@return VoxelRaycastResult
function N:GridHit(ray,maxDist,decorative)
    local start=Perf.Begin()
    local mask=self.aimMask or 0xffffffff
    local o,d=ray.origin,ray.direction
    if self.queryRevision~=Perf.revision then self.queryCount=0;self.queryRevision=Perf.revision end
    if self.queryScope then
        for i=1,self.queryCount do
            local c=self.queryPool[i]
            if c.ox==o.x and c.oy==o.y and c.oz==o.z and c.dx==d.x and c.dy==d.y and c.dz==d.z
                and c.distance==maxDist and c.mask==mask and c.world==self.world
                and c.filter==self.ignoreAimVolume then
                Perf.Finish('GridHit',start);return c.result
            end
        end
    end
    Perf.gridCalls=Perf.gridCalls+1
    local first=self.world:RaycastGridSingle(ray,maxDist,mask)
    local ignored=first.hit and self.ignoreAimVolume and self.ignoreAimVolume(first.volume)
    local emptyOrigin=not ignored and EmptyOriginHit(first,ray)
    local timeTarget=not ignored and first.hit and TimeObject.FindByVolume(first.volume)~=nil
    local nearest=first
    if ignored or emptyOrigin or timeTarget then
        Perf.fallbackReason=ignored and 'ignored' or (emptyOrigin and 'emptyOrigin' or 'timeTarget')
        -- Gameplay LOS remains exact. Only optional HUD queries can be denied;
        -- reporting the overrun is preferable to silently missing a real hit.
        local denied=decorative and (Perf.fallbacks>=4 or Perf.cells>=4096)
        if denied then
            nearest=VoxelRaycastResult:new();nearest.hit=true;nearest.distance=0
            Perf.gridBudgetExceeded=Perf.gridBudgetExceeded+1
            Perf.Finish('GridHit',start);return nearest -- never cache a budget denial
        end
        Perf.fallbacks=Perf.fallbacks+1
        local reach=not ignored and not emptyOrigin and math.min(maxDist,first.distance+.001) or maxDist
        nearest=VoxelRaycastResult:new()
        for i=0,self.world:GetVolumeCount()-1 do
            local volume=self.world:GetVolume(i)
            if volume~=nil and (volume.collisionLayer & mask)~=0
                and not (self.ignoreAimVolume and self.ignoreAimVolume(volume)) then
                if decorative and Perf.volumes>=128 then
                    nearest.hit,nearest.distance=true,0
                    Perf.gridBudgetExceeded=Perf.gridBudgetExceeded+1
                    Perf.Finish('GridHit',start);return nearest
                end
                Perf.volumes=Perf.volumes+1
                local limit=nearest.hit and math.min(reach,nearest.distance) or reach
                local actual,exhausted=TraceVolume(volume,ray,limit,decorative and 4096 or nil)
                if decorative and exhausted then
                    nearest.hit,nearest.distance=true,0
                    Perf.gridBudgetExceeded=Perf.gridBudgetExceeded+1
                    Perf.Finish('GridHit',start);return nearest
                end
                if actual and actual.hit and (not nearest.hit or actual.distance<nearest.distance) then nearest=actual end
            end
        end
    end
    if self.queryScope and self.queryCount<32 then
        self.queryCount=self.queryCount+1
        local c=self.queryPool[self.queryCount]
        c.ox,c.oy,c.oz,c.dx,c.dy,c.dz=o.x,o.y,o.z,d.x,d.y,d.z
        c.distance,c.mask,c.world,c.filter,c.result=maxDist,mask,self.world,self.ignoreAimVolume,nearest
    end
    Perf.Finish('GridHit',start)
    return nearest
end

-- 瞄准只查询实心体素，不把动态碎块的近似凸包当作可见表面。
-- 相机 ---- 中心射线 ---- 最近实心格（墙也会遮挡）
--                  \\ 半径 0.12m 容错，仅接受无遮挡的可操作目标
-- 回溯的 mask=0 体积仍可被 Grid 选中，但不会阻挡角色。
---@param ray Ray
---@param maxDist number
function N:AimRay(ray, maxDist)
    local hit = self:GridHit(ray, maxDist)
    local res = { hit = false, dir = ray.direction, origin = ray.origin, mask = self.aimMask or 0xffffffff,
        far = ray.origin + ray.direction * maxDist }
    local obj = hit.hit and TimeObject.FindByVolume(hit.volume) or nil
    local actionable = hit.hit and (obj ~= nil or hit.volume.destructible)
    if not actionable then
        -- 容错不得穿过中心射线上的墙；命中点还需单独检查可见性。
        local reach = hit.hit and math.min(maxDist, hit.distance + 0.12) or maxDist
        local near = self.world:SphereCast(Sphere(ray.origin, 0.12), ray.direction, reach, self.aimMask or 0xffffffff)
        if near.hit then
            local owner = TimeObject.FindByVolume(near.volume)
            if owner ~= nil or near.volume.destructible then
                local delta = near.position - ray.origin --[[@as Vector3]]
                local length = delta:Length()
                if length > 0.001 then
                    local visible = self:GridHit(Ray(ray.origin, delta / length), length + 0.08)
                    if visible.hit and (visible.volume == near.volume or (owner ~= nil and TimeObject.FindByVolume(visible.volume) == owner)) then
                        hit = visible
                        obj = owner
                        res.assisted = true
                    end
                end
            end
        end
    end
    if hit.hit then
        res.hit, res.pos, res.normal, res.volume = true, hit.position, hit.normal, hit.volume
        res.distance, res.voxel, res.volumeId = hit.distance, hit.voxel, hit.volumeId
        res.object = obj
        res.breakable = obj ~= nil and obj.canShatter or hit.volume.destructible
    end
    return res
end

-- 全屏中心准星对应相机的世界正前方，不依赖逆投影的深度约定。
-- 保留近裁剪面起点，不跳过相机与角色之间可见的物件。
function N:Aim(maxDist)
    local camera, node = self:Camera(), self:CameraNode()
    local direction = node.worldDirection:Normalized()
    if DebugLog.enabled and not self.aimLogged then
        self.aimLogged = true
        local projected = camera:GetScreenRay(.5, .5)
        print(string.format("RuinsAim: center-forward dot=%.4f viewport=%dx%d dpr=%.2f",
            projected.direction:DotProduct(direction), graphics:GetWidth(), graphics:GetHeight(), graphics:GetDPR()))
    end
    return self:AimRay(Ray(node.worldPosition + direction * camera.nearClip, direction), maxDist)
end

function N:SetVisible(v) self.node:SetDeepEnabled(v) end

return M
