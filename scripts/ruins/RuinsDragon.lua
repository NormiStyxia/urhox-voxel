-- Scene adapter: kinematic collision, safe dismount, bounded breath damage / frost.
local Stream = require("dragon.DragonStream")
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
        time=0,nextDamage=0,nextMaterial=0,patches={},touched={},cast=-1},D)
    host.ctrl.resolveMotion=function(c,pos,yaw,alt) self:ResolveMotion(c,pos,yaw,alt) end
    host.ride.resolveDismount=function() return self:DismountPoint() end
    host.breath:OnHit(function(info) self:Hit(info) end)
    -- A variant without a breath root (e.g. the hatchling) has no ordinary stream.
    if host.breath.root then host.stream=Stream.New(host.breath.root.parent,host.breath) end
    self.rideMode=host.ride.mode
    return self
end
---@param c table
---@param oldPos Vector3
---@param oldYaw number
---@param oldAlt number
function D:ResolveMotion(c,oldPos,oldYaw,oldAlt)
    local L,rig=c.loco,c.rig
    local newPos = L.pos --[[@as Vector3]]
    local translation = newPos - oldPos
    local delta=translation+Vector3(0,L.alt-oldAlt,0)
    if delta:LengthSquared() < 1e-12 and math.abs(L.yaw-oldYaw) < 1e-8 then return end
    local q=Quaternion(L.yaw-oldYaw,Vector3.UP)
    local fraction=1
    for _,def in ipairs(BODY) do
        local node=rig.bones[def[1]] --[[@as Node?]]
        if node then
            local root = rig.root --[[@as Node]]
            local offset=node.worldPosition-root.worldPosition
            local move=delta+q*offset-offset --[[@as Vector3]]
            local distance=move:Length()
            if distance>.0001 then
                local hit=self.world:SphereCast(Sphere(node.worldPosition,def[2]*rig.size*.85),move:Normalized(),distance+.06)
                if hit.hit and hit.normal:DotProduct(move)<-.0001 then
                    fraction=math.min(fraction,Clamp((hit.distance-.06)/distance,0,1))
                end
            end
        end
    end
    -- Grounded dragons cannot step onto a wall / cross the chasm in one stride.
    if not L.airborne and translation:LengthSquared()>.00001 then
        local a=c:GroundHeight(oldPos.x,oldPos.z)
        local b=c:GroundHeight(L.pos.x,L.pos.z)
        if b-a>0.65*rig.size or a-b>1.4*rig.size then fraction=0 end
    end
    if fraction<1 then
        L.pos=oldPos+(L.pos-oldPos)*fraction
        L.yaw=oldYaw+(L.yaw-oldYaw)*fraction
        L.alt=oldAlt+(L.alt-oldAlt)*fraction
        L.speed,L.yawRate=0,0; L.vel=Vector3.ZERO
        if math.abs(delta.y)>.001 then L.vy=0; L.altTarget=L.alt end
    end
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
            if ground.hit and ground.normal.y>.65 and math.abs(ground.position.y-root.y)<1.5 then
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
