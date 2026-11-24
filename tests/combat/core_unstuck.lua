-- Rubble left by the player can pinch the capsule between several narrow faces.
-- The controller may then keep reporting ground contact while the slide solver
-- makes no horizontal progress. A plain wall must never be mistaken for that
-- crevice, otherwise holding forward against a wall turns into an auto hop.
local S=dofile('tests/combat/core_support.lua')
local file=assert(io.open('scripts/ruins/NomiController.lua'));local source=file:read('*a');file:close()
local function slice(from,to)
    local a=assert(source:find(from,1,true))
    local b=to and assert(source:find(to,a+1,true)) or #source
    return source:sub(a,b-1)
end
local body=slice('function N:ResetJump','local wedgeDirs')
    ..slice('local wedgeDirs','function N:Move')
    ..slice('function N:Move','function N:SlideRay')
local N={}
local env=setmetatable({N=N,WALK=4.2,RUN=7.2,SPRINT=10,AIR_CONTROL=.35,
    COYOTE_TIME=.12,JUMP_BUFFER=.12,JUMP=6.4,
    Clamp=function(v,a,b)return math.max(a,math.min(b,v))end,
    WrapDeg=function(a)return (a+180)%360-180 end,
    Quaternion=function()return{}end,
    Terrain={HasGround=function()return true end},
    Ray=function(origin,direction)return{origin=origin,direction=direction}end},{__index=_G})
assert(load(body,'actual Nomi unstuck','t',env))()

-- sides: E (+X), W (-X), N (+Z), S (-Z) short hits at hip height.
-- solid=false marks a volume whose mask rejects the character (decorative).
local function New(sides,opts)
    opts=opts or {}
    local state={escapes=0,frames=0}
    local cc={onGround=opts.onGround~=false,radius=.32,collisionLayer=1,
        collisionMask=0xfffffffd,desiredVelocity=Vector3.ZERO,linear=Vector3.ZERO}
    function cc:Jump() error('the escape must not use the native jump') end
    function cc:GetLinearVelocity() return self.linear end
    function cc:SetLinearVelocity(v) self.linear=v;state.escapes=state.escapes+1 end
    local world={Raycast=function(_,ray,distance,mask)
        local d=ray.direction
        local key=(d.x>.5 and 'E') or (d.x<-.5 and 'W') or (d.z>.5 and 'N') or 'S'
        local solid=sides[key]
        if solid==false then return {{hit=true,distance=.29,volume={collisionMask=0}}} end
        if solid then return {{hit=true,distance=.29,volume={collisionMask=0xffffffff}}} end
        return {}
    end}
    local n=setmetatable({cc=cc,camYaw=0,yaw=0,vel=Vector3.ZERO,
        node={worldPosition=Vector3.ZERO},actualSpeed=0,frameTravel=0,
        UpdateSafety=function()return false end,world=world},{__index=N})
    return n,state
end

local opts={scale=1,motion=Vector3.ZERO,motionChecked=true}
local function step(n,dt,travel,speed)
    n.frameTravel,n.actualSpeed=travel,speed or 0
    n:Move(dt,1,0,false,false,false,opts)
end
local function blocked(n,dt,seconds)
    local frames=0
    for _=1,math.ceil(seconds/dt) do step(n,dt,.001,.05);frames=frames+1 end
    return frames
end

-- 1) Single wall, and a two-sided corner: staying a wall, no impulse at all.
for _,sides in ipairs({{E=true},{N=true},{E=true,N=true},{E=true,S=true}}) do
    local n,state=New(sides)
    blocked(n,1/60,1.5)
    assert(state.escapes==0,'a wall or corner must not launch the player')
end
-- Decorative volumes that the capsule mask rejects do not count as a pinch.
do
    local n,state=New({E=false,W=false})
    blocked(n,1/60,1.5)
    assert(state.escapes==0,'masked-out volumes are not real blockers')
end
-- 2) Opposite faces and three of four: a crevice earns exactly one impulse.
for _,sides in ipairs({{E=true,W=true},{N=true,S=true},{E=true,W=true,N=true},{E=true,W=true,N=true,S=true}}) do
    local n,state=New(sides)
    local frames,escaped=0,nil
    for i=1,120 do
        step(n,1/60,.001,.05)
        if state.escapes>0 then frames,escaped=i,true;break end
    end
    assert(escaped,'a real crevice must free the capsule')
    -- grace 0.35s, sampled at 60Hz
    assert(frames>=20 and frames<=24,'grace must stay ~0.35s, got frame '..frames)
    S.near(n.cc.linear.y,2.4)
    S.near(n.cc.linear.x,0);S.near(n.cc.linear.z,0)
    -- Second impulse only after the cooldown, never every frame.
    for _=1,30 do step(n,1/60,.001,.05) end
    assert(state.escapes==1,'cooldown must suppress repeats')
    for _=1,30 do step(n,1/60,.001,.05) end
    assert(state.escapes==2,'a still-stuck capsule may escape again after the cooldown')
end
-- 3) Unrelated states never escape, even inside a crevice.
do
    local n,state=New({E=true,W=true},{onGround=false})
    blocked(n,1/60,1.2);assert(state.escapes==0,'airborne is not a pinch')
    n,state=New({E=true,W=true})
    blocked(n,1/60,1.2)
    assert(state.escapes>0,'control: same setup on the ground does escape')
    n,state=New({E=true,W=true})
    for _=1,90 do step(n,1/60,.05,4.2) end
    assert(state.escapes==0,'normal walking progress is never blocked')
    n,state=New({E=true,W=true})
    opts.scale=0
    for _=1,90 do step(n,1/60,.001,.05) end
    opts.scale=1
    assert(state.escapes==0,'a frozen attack pose must not launch')
    n,state=New({E=true,W=true})
    n.frameTravel,n.actualSpeed=.001,.05
    n:Move(1/60,0,0,false,false,false,opts)
    assert(state.escapes==0,'no input, no escape')
end
-- 4) Same hand-off at 30/60/120Hz: the grace duration is time based.
for _,hz in ipairs({30,60,120}) do
    local dt=1/hz
    local n,state=New({E=true,W=true})
    local t=0
    for _=1,hz*2 do
        step(n,dt,.001,.05);t=t+dt
        if state.escapes>0 then break end
    end
    assert(state.escapes==1,'escape must fire at '..hz..'Hz')
    assert(t>.34 and t<.43,tostring(hz)..'Hz grace drifted to '..t..'s')
end
print('PASS rubble pinch escape: wall/corner stay solid, crevice hops once per cooldown, time based at 30/60/120Hz')
