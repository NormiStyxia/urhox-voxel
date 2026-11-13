-- Scene adapter: kinematic collision, safe dismount, bounded breath damage / frost.
local Stream = require("dragon.DragonStream")
local Collision = require("dragon.DragonCollision")
local M = {}
---@class RuinsFrostPatch
---@field pos Vector3
---@field radius number
---@field age number

---@class RuinsDragonAdapter
---@field host table
---@field nomi NomiController
---@field world VoxelPhysicsWorld
---@field puzzles table
---@field terrain table
---@field patches RuinsFrostPatch[]
---@field hadFrost boolean|nil
---@field hull DragonHullBall[]
---@field motionPos Vector3|nil
---@field motionEpoch number|nil
---@field safeMotion {pos:Vector3,yaw:number,airborne:boolean}|nil
---@field recoveryClock number
---@field nextRecovery number
---@field wasAirborne boolean|nil
local D = {}; D.__index = D
local BODY = {{'pelvis',1.0},{'waist',.95},{'chest',1.0},{'neck2',.55},{'head',.75},{'tail1',.6},{'tail3',.5}}
local PLAYER_BODY={}
for _,d in ipairs(BODY) do PLAYER_BODY[#PLAYER_BODY+1]=d end
for _,side in ipairs({'R','L'}) do
    for _,joint in ipairs({'armL_','hand_','legL_','legM_','foot_'}) do
        PLAYER_BODY[#PLAYER_BODY+1]={joint..side,.28}
    end
end
local function Clamp(x,a,b) return math.max(a,math.min(b,x)) end
function M.New(host,world,nomi,puzzles,terrain)
    local self=setmetatable({host=host,world=world,nomi=nomi,puzzles=puzzles,terrain=terrain,
        time=0,nextDamage=0,nextMaterial=0,patches={},touched={},cast=-1,
        hull=Collision.Hull(host.rig),recoveryClock=0,nextRecovery=0},D)
    host.ctrl.queryGround=function(x,z)
        local ref=host.ctrl.groundRef or terrain.RING_Y or 0
        -- Probe near the feet, not six metres above them (which found roofs).
        local rise=host.ctrl.loco.airborne and .05 or (.65*host.rig.size+.05)
        local hit=world:RaycastSingle(Ray(Vector3(x,ref+rise,z),Vector3.DOWN),
            math.max(40,ref-(terrain.Y_BASE or -20)+rise),Collision.MASK)
        if hit.hit and hit.normal.y>.6 then return hit.position.y end
        return nil
    end
    host.ctrl.canLand=function(x,z)
        -- 大龙需完整永久岛面；修桥残块不构成降落坪。
        if not terrain.HasGround(x,z,2.5*host.rig.size) then return false end
        local y=host.ctrl.queryGround(x,z)
        if y==nil then return false end
        -- Certify the torso at the proposed landing point. Unknown is unsafe.
        return Collision.Clear(world,self.hull,Vector3(x,y,z),host.ctrl.loco.yaw,{left=6000})==true
    end
    host.ctrl.onNoLanding=function()
        if host.ride.onNotice then host.ride.onNotice("下方没有安全落点，请飞到开阔岛面再降落") end
    end
    host.ctrl.prepareMotion=function(c) self:PrepareMotion(c) end
    host.ctrl.resolveMotion=function(c,pos,yaw,alt,dt) self:ResolveMotion(c,pos,yaw,alt,dt) end
    host.ride.resolveDismount=function() return self:DismountPoint() end
    host.breath:OnHit(function(info) self:Hit(info) end)
    -- A variant without a breath root (e.g. the hatchling) has no ordinary stream.
    if host.breath.root then host.stream=Stream.New(host.breath.root.parent,host.breath) end
    self.rideMode=host.ride.mode
    return self
end
-- Keep absolute altitude as the terrain underneath changes. Relative alt still
-- drives flight/landing, but a new floor reference cannot lift the root for free.
function D:PrepareMotion(c)
    local L=c.loco
    if self.motionPos==nil or self.motionEpoch~=c.motionEpoch then
        self.motionEpoch=c.motionEpoch
        self.motionPos=Vector3(L.pos.x,c:GroundHeight(L.pos.x,L.pos.z)+L.alt,L.pos.z)
        self.safeMotion=nil
        self.nextRecovery=0
    end
    self.wasAirborne=L.airborne
    if L.airborne then
        local below=c.queryGround(L.pos.x,L.pos.z)
        if below~=nil and below<=self.motionPos.y+.05 then
            local oldFloor=c.airFloor or (self.motionPos.y-L.alt)
            L.alt=math.max(0,self.motionPos.y-below)
            L.altTarget=math.max(0,(L.altTarget or L.alt)+oldFloor-below)
            c.airFloor=below
        end
    end
end

---@param c table
---@param p Vector3
---@param airborne boolean
function D:Supported(c,p,airborne)
    if airborne then return true end
    local y=c.queryGround(p.x,p.z)
    return y~=nil and math.abs(y-p.y)<.10
        and self.terrain.HasGround(p.x,p.z,.65*self.host.rig.size)
end

-- A recreated time object or moving fragment may overlap a stationary dragon.
-- Check exact occupancy at 5 Hz, with a shared voxel budget and no unsafe fallback.
---@param c table
---@param pos Vector3
---@param yaw number
---@param dt number
---@return Vector3, number, boolean
function D:Recover(c,pos,yaw,dt)
    self.recoveryClock=self.recoveryClock+dt
    if self.recoveryClock<self.nextRecovery then return pos,yaw,false end
    self.nextRecovery=self.recoveryClock+.20
    local budget={left=12000}
    local clear,normal,depth=Collision.Clear(self.world,self.hull,pos,yaw,budget)
    if clear==true then
        if self:Supported(c,pos,c.loco.airborne) then
            self.safeMotion={pos=pos,yaw=yaw,airborne=c.loco.airborne}
        end
        return pos,yaw,false
    end
    if clear==false and normal and depth and normal:LengthSquared()>.5 then
        -- Only accept a bounded, fully clear escape, not repeated blind pushes.
        local push=normal*math.min(depth+.05,.30*self.host.rig.size)
        if not c.loco.airborne then push=Vector3(push.x,0,push.z) end
        local candidate=Collision.Slide(self.world,self.hull,pos,yaw,push)
        if self:Supported(c,candidate,c.loco.airborne)
            and Collision.Clear(self.world,self.hull,candidate,yaw,budget)==true then
            return candidate,yaw,true
        end
    end
    local safe=self.safeMotion
    if clear==false and safe and safe.airborne==c.loco.airborne
        and (safe.pos-pos):Length()<6*self.host.rig.size and self:Supported(c,safe.pos,safe.airborne)
        and Collision.Clear(self.world,self.hull,safe.pos,safe.yaw,budget)==true then
        return safe.pos,safe.yaw,true
    end
    return pos,yaw,false
end

---@param c table
---@param oldPos Vector3
---@param oldYaw number
---@param oldAlt number
---@param dt number|nil
function D:ResolveMotion(c,oldPos,oldYaw,oldAlt,dt)
    dt=dt or 1/60
    if self.motionPos==nil then self:PrepareMotion(c) end
    local L,rig=c.loco,c.rig
    local start=self.motionPos --[[@as Vector3]]
    local requestedYaw=L.yaw
    local wanted=Vector3(L.pos.x,start.y+L.alt-oldAlt,L.pos.z)
    local unsupported=false
    local landing=self.wasAirborne and not L.airborne
    if not L.airborne then
        local ground=c.queryGround(wanted.x,wanted.z)
        if ground==nil or (not landing and (ground-start.y>.65*rig.size or start.y-ground>1.4*rig.size)) then
            wanted=start; unsupported=true -- Still allow a checked turn away from the edge.
        else wanted=Vector3(wanted.x,ground,wanted.z) end
    end
    local pos,freeMove=Collision.Slide(self.world,self.hull,start,oldYaw,wanted-start)
    if not L.airborne then
        -- Sliding changes x/z: validate support at the resolved position.
        local ground=c.queryGround(pos.x,pos.z)
        if ground==nil or (not landing and (ground-start.y>.65*rig.size or start.y-ground>1.4*rig.size)) then
            pos=start; unsupported=true
        else
            local settled=Collision.Slide(self.world,self.hull,pos,oldYaw,Vector3(0,ground-pos.y,0))
            if math.abs(settled.y-ground)<.02 then pos=settled
            elseif not landing then pos=start; unsupported=true end
        end
    end
    local yaw=Collision.Turn(self.world,self.hull,pos,oldYaw,requestedYaw)
    local recovered
    pos,yaw,recovered=self:Recover(c,pos,yaw,dt)
    local actual=pos-start
    local desired=wanted-start
    local horizontal=Vector3(actual.x,0,actual.z)
    local freeHorizontal=Vector3(freeMove.x,0,freeMove.z)
    local requested=Vector3(desired.x,0,desired.z)
    if requested:LengthSquared()>1e-10 then
        L.speed=L.speed*Clamp(freeHorizontal:Length()/requested:Length(),0,1)
    end
    if unsupported then L.speed=0 end
    L.vel=horizontal/math.max(dt,1e-6)
    if math.abs(Collision.Angle(yaw-requestedYaw))>.001 then L.yawRate=0 end
    L.pos,L.yaw=Vector3(pos.x,0,pos.z),yaw
    if landing then
        local ground=c.queryGround(pos.x,pos.z)
        if ground==nil or math.abs(pos.y-ground)>.08 then
            -- LAND may have marked touchdown before the sweep hit an obstacle.
            L.airborne=true; c.touchT=nil; c.impactS=nil; c.ikTarget=0; c.ikFrontTarget=0
        end
    end
    local floor=L.airborne and (c.airFloor or start.y-oldAlt) or pos.y
    L.alt=math.max(0,pos.y-floor)
    if math.abs(actual.y-desired.y)>.001 then L.vy=0; L.altTarget=L.alt end
    if recovered then L.speed=0; L.vel=Vector3.ZERO; L.vy=0; L.altTarget=L.alt end
    c.airFloor=floor
    c.motionY,c.groundRef=pos.y,pos.y
    self.motionPos=pos
end
function D:OutsideBody(pos,padding)
    local rig=self.host.rig
    for _,def in ipairs(PLAYER_BODY) do
        local node=rig.bones[def[1]]
        if node then
            local c=node.worldPosition; local r=def[2]*rig.size+padding
            local y=Clamp(c.y,pos.y+.32,pos.y+1.33)
            if (Vector3(pos.x,y,pos.z)-c):Length()<r then return false end
        end
    end
    return true
end
function D:DismountPoint()
    local h=self.host; local c=h.ctrl
    if c.loco.airborne or c.state=='TAKEOFF' or c.state=='LAND' then
        return nil,'先按 L 降落，落稳后再按 F 下龙'
    end
    local origin=h.rig.bones.chest.worldPosition
    local root=h.rig.root.worldPosition
    for _,dist in ipairs({2.0,2.7,3.4}) do
        for _,angle in ipairs({90,-90,135,-135,180}) do
            local a=math.rad(c.loco.yaw+angle)
            local p=root+Vector3(math.sin(a),0,math.cos(a))*dist*h.rig.size
            local ground=self.world:RaycastSingle(Ray(Vector3(p.x,root.y+2,p.z),Vector3.DOWN),5)
            if ground.hit and ground.normal.y>.65 and math.abs(ground.position.y-root.y)<1.5
                and self.terrain.IsSafeGround(p.x,ground.position.y,p.z) then
                p=ground.position+Vector3(0,.08,0)
                local clear=self.world:SphereCast(Sphere(p+Vector3(0,.4,0),.34),Vector3.UP,1.15)
                local path=p+Vector3(0,1,0)-origin
                local wall=self.world:RaycastSingle(Ray(origin,path:Normalized()),path:Length())
                if not clear.hit and not wall.hit and self:OutsideBody(p,.4) then return p end
            end
        end
    end
    return nil,'旁边没有安全落脚点，移动到开阔地再下龙'
end
function D:PushPlayer()
    if self.host.ride.mode~='free' then return end
    local p=self.nomi:Position(); local start=p; local rig=self.host.rig
    -- Two passes resolve overlaps at adjoining body joints without a full rigid body rig.
    for _=1,2 do for _,def in ipairs(PLAYER_BODY) do
        local node=rig.bones[def[1]]
        if node then
            local c=node.worldPosition; local r=def[2]*rig.size+.34
            local y=Clamp(c.y,p.y+.32,p.y+1.33); local dy=y-c.y
            if math.abs(dy)<r then
                local rad=math.sqrt(r*r-dy*dy)
                local d=Vector3(p.x-c.x,0,p.z-c.z); local len=d:Length()
                if len<rad then
                    local direction=len<.001 and rig.root.worldRotation*Vector3.RIGHT or d/len
                    local move=direction*(rad-len+.015); local n=move:Length()
                    local allowed=n
                    for _,height in ipairs({.34,1.3}) do
                        local hit=self.world:SphereCast(Sphere(p+Vector3(0,height,0),.32),move:Normalized(),n+.02)
                        if hit.hit then allowed=math.min(allowed,math.max(0,hit.distance-.02)) end
                    end
                    p=p+move:Normalized()*allowed
                end
            end
        end
    end end
    if (p-start):LengthSquared()>.000001 then
        self.nomi.cc:Teleport(p); self.nomi.node.worldPosition=p; self.host.ride.pos=p
    end
end
---@param pos Vector3
---@param radius number
function D:AddIce(pos,radius)
    ---@type RuinsFrostPatch|nil
    local patch
    for _,p in ipairs(self.patches) do
        if math.abs(p.pos.y-pos.y)<.6 and (p.pos-pos):Length()<math.max(1,p.radius*.65) then patch=p; break end
    end
    if not patch then
        patch={pos=pos,radius=.2,age=0}
        if #self.patches>=6 then table.remove(self.patches,1) end
        self.patches[#self.patches+1]=patch
    end
    patch.age=0; patch.radius=math.min(radius,patch.radius+.22)
end
function D:Hit(info)
    if self.cast~=info.cast then self.cast=info.cast; self.touched={} end
    if self.time<self.nextDamage then return end
    self.nextDamage=self.time+.12
    local obj=self.puzzles.FindByVolume(info.volume)
    if obj then
        if not self.touched[obj] and obj.state~='REWIND' then
            if info.ordinary and obj.canShatter then obj:Shatter({level=1,point=info.pos,dir=info.dir,power=.7,radius=info.radius})
            elseif info.element=='frost' then obj:Freeze(8)
            elseif obj.canShatter then obj:Shatter({level=2,point=info.pos,dir=info.dir,power=1.4,radius=info.radius}) end
            self.touched[obj]=true
        end
    elseif info.volume and info.volume.destructible then
        -- Target only the struck volume: do not drill through walls or damage rewind snapshots.
        local removed=self.world:ApplyDamage(info.volume,info.pos,math.min(info.radius,3.5),info.ordinary and info.power or 3.0)
        if removed>0 then self.world:ApplyRadialImpulse(info.pos,info.radius,350) end
    end
    if info.normal.y>.5 then self:AddIce(info.pos,math.min(info.radius*1.5,5.5)) end
end
function D:Update(dt)
    self.time=self.time+dt
    for i=#self.patches,1,-1 do
        local p=self.patches[i]; p.age=p.age+dt
        if p.age>=18 then table.remove(self.patches,i) end
    end
    self:PushPlayer()
    local h=self.host
    if h.stream then
        local held,allowed
        if h.readStreamInput then held,allowed=h.readStreamInput()
        else
            held=input:GetMouseButtonDown(MOUSEB_LEFT) or input:GetKeyDown(KEY_1)
            allowed=h.ride.controlsEnabled==nil or h.ride.controlsEnabled()
        end
        if self.rideMode~=h.ride.mode then
            self.rideMode=h.ride.mode
            h.stream:Stop(true)
        end
        h.stream:Update(dt,held,h.breath.aimTarget,allowed and h.ride.mode=="mounted")
    end
    if #self.patches == 0 and not self.hadFrost then return end
    if self.time<self.nextMaterial then return end
    self.nextMaterial=self.time+.1
    self.hadFrost = #self.patches > 0
    local mats={}
    if self.terrain.groundMaterial then mats[#mats+1]=self.terrain.groundMaterial end
    for _,m in pairs(self.host.surfaceMaterials or {}) do mats[#mats+1]=m end
    for _,m in ipairs(mats) do for i=1,6 do
        local p=self.patches[i]
        m:SetShaderParameter('frost_patch'..i,Variant(p and Vector4(p.pos.x,p.pos.y,p.pos.z,p.radius) or Vector4(0,0,0,0)))
        m:SetShaderParameter('frost_weight'..i,Variant(p and Clamp((18-p.age)/5,0,1) or 0.0))
    end end
end
return M
