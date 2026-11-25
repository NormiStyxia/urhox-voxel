-- Ordinary held breath. Does not enter BREATH or replace walking/flight states.
local VoxelFX=require('dragon.VoxelFX')
local Pose=require('dragon.DragonPose')
local ShaderWarmup=require('dragon.DragonShaderWarmup') -- W6: independent warmup hook
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
---@field contact DragonStreamContact
---@field pitch number
---@field yaw number
---@field requiresRelease boolean
---@field root Node|nil
---@field node Node
---@field mat Material
---@field motes VoxelFXMotes
---@field shaderWarmup DragonShaderWarmup
local S={}; S.__index=S
-- W6 预热默认关闭：Windows 实测克隆代理在异常时每帧泄漏几何体并中断更新；冷启动 HLSL 错误已确认属于云层着色器。
S.ENABLE_SHADER_WARMUP=false
local function Clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function Wrap(a) return (a+180)%360-180 end
-- A mist wave keeps the frame of the surface where it was born. Waves already
-- spreading across the floor therefore stay there when the beam sweeps onto a wall.
local WAVE_INTERVAL, WAVE_LIFE = .16, .72
local LOBES = 6
local TAU = math.pi * 2

---@param root Node
---@param material Material
---@param count integer
local function SurfaceSprites(root, name, material, count)
    local node = root:CreateChild(name)
    local sprites = node:CreateComponent('BillboardSet')
    sprites:SetMaterial(material)
    sprites:SetRelative(true)
    sprites:SetFaceCameraMode(FC_NONE)
    sprites:SetNumBillboards(count)
    sprites.castShadows = false
    for i = 0, count - 1 do sprites:GetBillboard(i).enabled = true end
    sprites:Commit()
    node.enabled = false
    return {node=node, sprites=sprites, age=WAVE_LIFE, radius=0, angle=0}
end

---@param root Node
local function NewContact(root)
    local smoke = Material:new()
    assert(smoke:SetSurfaceShader('Shaders/BLGL/ParticleSmokeSoft.shader'), 'Frost mist shader unavailable')
    ---@class DragonStreamContact
    local contact = {
        core=SurfaceSprites(root, 'FrostContactGlow', smoke, 1),
        waves={}, nextWave=1, mistAt=0, burstAt=0, idleBurstAt=0, coreStrength=0, coreAt=0,
        lastPos=nil, lastNormal=nil, lastVolume=nil,
        chips=VoxelFX.Motes(root, 'ContactIce', 32, 'star', true),
        chipColors={},
    }
    for i = 1, math.ceil(WAVE_LIFE / WAVE_INTERVAL) do
        contact.waves[i] = SurfaceSprites(root, 'FrostMist' .. i, smoke, LOBES + 1)
    end
    for i = 1, 12 do
        local u = (i-1)/11
        local glint = math.max(0, 1 - 3*u)
        contact.chipColors[i] = Color(.27+.72*glint, .74+.26*glint, 1, 1-u*u)
    end
    return contact
end

---@param c DragonStreamContact
local function AgeContact(c, dt, time)
    c.chips:Update(dt)
    if c.core.node.enabled then
        local opacity = c.coreStrength * math.max(0, 1 - (time - c.coreAt) / .34)
        local b = c.core.sprites:GetBillboard(0)
        local pulse = .90 + .10 * math.sin(time * 11)
        local size = c.core.radius * pulse
        b.size = Vector2(size, size)
        b.color = Color(.84, .97, 1, .78 * opacity * pulse)
        c.core.sprites:Commit()
        c.core.node.enabled = opacity > 0
    end
    for _, wave in ipairs(c.waves) do
        if wave.node.enabled then
            wave.age = math.min(WAVE_LIFE, wave.age + dt)
            local u = wave.age / WAVE_LIFE
            wave.node.enabled = u < 1
            local sweep = u*(2-u)
            local spread = wave.radius * (.24 + 1.02*sweep)
            local size = wave.radius * (.58 + .86*sweep)
            local fade = (1-u)^1.55

            -- A continuous thin sheet moves with the softer crests, including
            -- after release when the anchored core has already faded out.
            local sheet = wave.sprites:GetBillboard(LOBES)
            local sheetSize = spread + .77*size
            sheet.size = Vector2(sheetSize, sheetSize)
            sheet.rotation = math.deg(wave.angle)
            sheet.color = Color(.31, .70, .89, .30*fade)
            local crestColor = Color(.46+.14*u, .80+.07*u, .98, .35*fade)
            for i = 0, LOBES-1 do
                local a = wave.angle + TAU*i/LOBES + .25*u
                local b = wave.sprites:GetBillboard(i)
                b.position = Vector3(math.cos(a)*spread, math.sin(a)*spread, .04*u)
                b.size = Vector2(size, size*(.86+.07*math.sin(a)))
                b.rotation = math.deg(a) + 90
                b.color = crestColor
            end
            wave.sprites:Commit()
        end
    end
end

---@param c DragonStreamContact
---@param dir Vector3
local function EmitContact(c, hit, dir, radius, time, strength)
    local normal = hit.normal
    if normal:LengthSquared() < .0001 then normal = -dir end
    normal = normal:Normalized()
    local rotation = Quaternion(Vector3.FORWARD, normal)
    local pos = hit.position + normal*.042
    c.core.node.worldPosition = pos
    c.core.node.worldRotation = rotation
    c.core.radius = radius * .90
    c.coreAt, c.coreStrength = time, strength
    c.core.node.enabled = true

    if time >= c.mistAt then
        c.mistAt = time + WAVE_INTERVAL
        local wave = c.waves[c.nextWave]
        c.nextWave = c.nextWave % #c.waves + 1
        wave.age, wave.radius, wave.angle = 0, radius, math.random()*TAU
        wave.node.worldPosition = pos
        wave.node.worldRotation = rotation
        wave.node.enabled = true
    end

    if time < c.burstAt then return end
    local swept = not c.lastPos or (hit.position-c.lastPos):LengthSquared() > (.65*radius)^2
        or normal:DotProduct(c.lastNormal) < .8 or hit.volume ~= c.lastVolume
    if not swept and time < c.idleBurstAt then return end
    c.burstAt, c.idleBurstAt = time + .12, time + .29
    c.lastPos, c.lastNormal, c.lastVolume = hit.position, normal, hit.volume
    local count = swept and 7 or 3
    local phase = math.random()*TAU
    for i = 1, count do
        local angle = phase + (i + .4*math.random())*TAU/count
        local tangent = rotation * Vector3(math.cos(angle), math.sin(angle), 0)
        c.chips:Spawn({pos=pos+tangent*.22*radius,
            vel=tangent*((3.5+math.random()*2.4)*radius) + normal*(.35+.85*math.random()),
            life=.30+.16*math.random(), size=.068+.063*math.random(), drag=1.7, colors=c.chipColors})
    end
end

---@param scene Scene
---@param breath DragonBreath
---@return DragonStream
function M.New(scene,breath)
    local self=setmetatable({breath=breath,ctrl=breath.ctrl,world=breath.world,active=false,
        strength=0,time=0,castId=0,particles=0,pitch=0,yaw=0,requiresRelease=false},S)
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
    self.contact = NewContact(root)
    -- W6: clone only visual sources; real breath/pool state stays untouched.
    self.shaderWarmup=S.ENABLE_SHADER_WARMUP and ShaderWarmup.New(root,self.node,self.motes.bb,breath.rings and breath.rings[1] and breath.rings[1].node or nil) or nil
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
    if not self.root then return end
    self.contact.lastPos, self.contact.lastNormal, self.contact.lastVolume = nil, nil, nil
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
    if not self.root then return end
    if self.shaderWarmup then
        local ok,err=pcall(self.shaderWarmup.Update,self.shaderWarmup,dt,held or self.ctrl.state=='BREATH')
        if not ok then
            print('DragonShaderWarmup disabled after error: '..tostring(err))
            pcall(self.shaderWarmup.Destroy,self.shaderWarmup)
            self.shaderWarmup=nil
        end
    end -- W6 warmup: guarded, never interrupts the frame update
    dt=math.min(math.max(dt,0),.1)
    self.time=self.time+dt
    self.motes:Update(dt)
    if not held then self.requiresRelease=false end
    local cancelled = allowed==false or self.ctrl.state=='BREATH'
    if cancelled or not held or self.requiresRelease then
        self:Stop(cancelled and held)
        AgeContact(self.contact, dt, self.time)
        return
    end
    if not self.active then
        self.active=true;self.castId=self.castId+1
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
        EmitContact(self.contact, hit, dir, radius, self.time, self.strength)
    else
        self.contact.lastPos, self.contact.lastNormal, self.contact.lastVolume = nil, nil, nil
    end
    AgeContact(self.contact, dt, self.time)
end
function S:Destroy()
    if not self.root then return end
    if self.shaderWarmup then pcall(self.shaderWarmup.Destroy,self.shaderWarmup); self.shaderWarmup=nil end -- W6: cleanup before the owning root disappears
    self:Stop()
    if self.ctrl.stream==self then self.ctrl.overlayPose=nil;self.ctrl.stream=nil end
    self.root:Remove()
    self.root, self.contact, self.node, self.mat, self.motes = nil, nil, nil, nil, nil
end
return M
