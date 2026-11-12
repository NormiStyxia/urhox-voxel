-- Ordinary held breath. Does not enter BREATH or replace walking/flight states.
local VoxelFX=require('dragon.VoxelFX')
local Pose=require('dragon.DragonPose')
local M={RANGE=18.0,POWER=1.8}
---@class DragonStream
---@field breath DragonBreath
---@field ctrl DragonAnimationController
---@field world VoxelPhysicsWorld
---@field active boolean
---@field strength number
---@field time number
---@field castId number
---@field particles number
---@field ringAt number
---@field pitch number
---@field yaw number
---@field requiresRelease boolean
---@field root Node|nil
---@field node Node
---@field mat Material
---@field motes VoxelFXMotes
local S={}; S.__index=S
local function Clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function Wrap(a) return (a+180)%360-180 end
---@param scene Scene
---@param breath DragonBreath
---@return DragonStream
function M.New(scene,breath)
    local self=setmetatable({breath=breath,ctrl=breath.ctrl,world=breath.world,active=false,
        strength=0,time=0,castId=0,particles=0,ringAt=0,pitch=0,yaw=0,requiresRelease=false},S)
    local root=scene:CreateChild('OrdinaryDragonBreath')
    self.root=root
    self.node=root:CreateChild('FrostRibbon')
    local g=self.node:CreateComponent('CustomGeometry')
    g:BeginGeometry(0,TRIANGLE_LIST)
    for side=0,2 do
        local a=side*math.pi/3
        -- Three crossing tapered ribbons, 18 vertices total; no new geometry per frame.
        for _,p in ipairs({{0,-1},{1,-1},{1,1},{0,-1},{1,1},{0,1}}) do
            local u,v=p[1],p[2]; local radius=.12+.88*u
            g:DefineVertex(Vector3(math.cos(a)*v*radius,math.sin(a)*v*radius,u))
            g:DefineNormal(Vector3(-math.sin(a),math.cos(a),0))
            g:DefineTexCoord(Vector2(u,(v+1)*.5))
        end
    end
    g:Commit();g.castShadows=false
    self.mat=Material:new()
    assert(self.mat:SetSurfaceShader('Shaders/BLGL/DragonStream.shader'),'DragonStream shader unavailable')
    g:SetMaterial(self.mat);self.node.enabled=false
    self.motes=VoxelFX.Motes(root,'FrostFlecks',96,'square',false)
    self.ctrl.stream=self
    self.ctrl.overlayPose=function(_,pose) self:OverlayPose(pose) end
    return self
end
---@param pose {j: table<string, number[]>, body: number[]}
function S:OverlayPose(pose)
    local w=self.strength
    Pose.AddTo(pose,'neck3',self.pitch*.3*w,self.yaw*.3*w,0)
    Pose.AddTo(pose,'head',self.pitch*.7*w,self.yaw*.7*w,0)
    Pose.AddTo(pose,'jaw',18*w,0,0)
end
---@param requireRelease boolean|nil
function S:Stop(requireRelease)
    self.active=false;self.strength=0;self.pitch,self.yaw=0,0
    if requireRelease then self.requiresRelease=true end
    if self.node then self.node.enabled=false end
end
-- allowed=false is a cancellation, not a release-to-fire action.
-- A cancelled held input must be released before it can start again.
---@param dt number
---@param held boolean
---@param target Vector3|nil
---@param allowed boolean|nil
function S:Update(dt,held,target,allowed)
    dt=math.min(math.max(dt,0),.1)
    self.time=self.time+dt
    self.motes:Update(dt)
    if not held then self.requiresRelease=false end
    if allowed==false or self.ctrl.state=='BREATH' then
        self:Stop(held)
        return
    end
    if not held or self.requiresRelease then self:Stop();return end
    if not self.active then
        self.active=true;self.castId=self.castId+1;self.ringAt=self.time
        self.pitch,self.yaw=0,0
    end
    self.strength=math.min(1,self.strength+dt/0.14)
    local origin,dir=self.breath:MouthFrame()
    if target then
        local desired=target-origin
        if desired:LengthSquared()>.01 then
            local yaw=math.deg(math.atan(desired.x,desired.z))
            local currentYaw=math.deg(math.atan(dir.x,dir.z))
            local pitch=math.deg(math.atan(-desired.y,math.sqrt(desired.x^2+desired.z^2)))
            local currentPitch=math.deg(math.atan(-dir.y,math.sqrt(dir.x^2+dir.z^2)))
            self.yaw=Clamp(self.yaw+Wrap(yaw-currentYaw)*math.min(1,dt*5),-40,40)
            self.pitch=Clamp(self.pitch+(pitch-currentPitch)*math.min(1,dt*5),-45,55)
        end
    end
    local hit=self.breath:TraceSurface(origin,dir,M.RANGE)
    local length=hit.hit and math.max(.05,hit.distance) or M.RANGE
    local scale=math.sqrt(self.breath.S or 1)
    local radius=math.min(1.1,.45+length*.025)*math.min(1.4,scale)
    self.node.enabled=true
    self.node.worldPosition=origin
    self.node.worldRotation=Quaternion(Vector3.FORWARD,dir)
    self.node.scale=Vector3(radius,radius,length)
    self.mat:SetShaderParameter('strength',Variant(self.strength))
    -- Bounded particles complement the ribbon; the ordinary attack has no cinematic crystal forest.
    self.particles=self.particles+dt*26
    while self.particles>=1 do
        self.particles=self.particles-1
        local travel=math.max(.01,length-.2)
        local along=math.random()*travel
        self.motes:Spawn({pos=origin+dir*along,vel=dir*7,
            life=math.min(.22,math.max(.01,(travel-along)/7)),size=.045+.045*math.random(),
            colors={Color(.7,.95,1,.7),Color(.25,.65,.85,.3)},drag=1.2})
    end
    if hit.hit and self.strength>.2 then
        local info={pos=hit.position,normal=hit.normal,volume=hit.volume,origin=origin,dir=dir,
            radius=radius,power=M.POWER,element='frost',ordinary=true,cast='stream:'..self.castId}
        for _,fn in ipairs(self.breath.listeners) do fn(info) end
        if self.time>=self.ringAt then
            self.ringAt=self.time+.4
            self.breath:SpawnRing(hit.position,radius*2.8,.42,hit.normal)
        end
    end
end
function S:Destroy()
    self:Stop()
    if self.ctrl.stream==self then self.ctrl.overlayPose=nil;self.ctrl.stream=nil end
    if self.root then self.root:Remove();self.root=nil end
end
return M
