-- Run the actual controller methods; native ports are spies, not a physics sim.
local S=dofile('tests/combat/core_support.lua')
local file=assert(io.open('scripts/ruins/NomiController.lua'))
local source=file:read('*a');file:close()
local N={}
local env=setmetatable({N=N,Terrain={HasGround=function()return true end},
    Clamp=function(v,a,b)return math.max(a,math.min(b,v))end,
    WrapDeg=function(a)return (a+180)%360-180 end,
    Quaternion=function()return {} end}, {__index=_G})
local constants=assert(source:match('(local WALK, RUN.-)\nlocal function Clamp'))
local methods=assert(source:match('(function N:ResetJump%(.+)\n%-%- Probe actual'))
assert(load(constants..'\n'..methods,'actual jump controller','t',env))()
local function New(grounded)
    local cc={onGround=grounded,nativeJumps=0,airLaunches=0,velocity=Vector3(2,-1,3)}
    function cc:Jump(speed)self.nativeJumps=self.nativeJumps+1;S.near(speed,6.4)end
    function cc:GetLinearVelocity()return self.velocity end
    function cc:SetLinearVelocity(v)self.velocity=v;self.airLaunches=self.airLaunches+1 end
    local n=setmetatable({cc=cc,camYaw=0,yaw=0,vel=Vector3.ZERO,
        node={worldPosition=Vector3.ZERO},UpdateSafety=function()return false end},{__index=N})
    n:ResetJump()
    return n,cc
end
local function Step(n,dt,press,options)n:Move(dt,0,0,false,press,false,options)end
for _,hz in ipairs({30,60,120}) do
    local dt=1/hz
    -- Walk off, press 100ms later: one launch, same height/speed, X/Z intact.
    local n,cc=New(true);Step(n,dt,false);cc.onGround=false
    for _=1,math.floor(.1*hz)-1 do Step(n,dt,false) end
    Step(n,dt,true)
    assert(cc.airLaunches==1 and cc.nativeJumps==0)
    S.near(cc.velocity.x,2);S.near(cc.velocity.y,6.4);S.near(cc.velocity.z,3)
    Step(n,dt,true);assert(cc.airLaunches==1,'no second air jump')
    -- The same edge press after 150ms must fail.
    n,cc=New(true);Step(n,dt,false);cc.onGround=false
    Step(n,.15,true);assert(cc.airLaunches==0)
    -- Press before first landing: buffered input fires once on real support.
    n,cc=New(false);Step(n,dt,true);Step(n,.06,false)
    cc.onGround=true;Step(n,dt,false);assert(cc.nativeJumps==1)
    Step(n,dt,false);assert(cc.nativeJumps==1)
end
-- A stale grounded report after queuing Jump cannot grant another jump.
do
    local n,cc=New(true);Step(n,.016,true)
    assert(cc.nativeJumps==1 and not n.onGround)
    Step(n,.016,true);assert(cc.nativeJumps==1)
    cc.onGround=false;Step(n,.016,false);Step(n,.2,false)
    Step(n,.016,true);cc.onGround=true;Step(n,.016,false)
    assert(cc.nativeJumps==2,'fresh press before a real landing is buffered')
end
-- An expired early press, or merely holding after takeoff, never auto-bounces.
do
    local n,cc=New(true);Step(n,.016,true)
    Step(n,.13,false);assert(cc.nativeJumps==1,'blocked takeoff cannot auto-retry')
    Step(n,.016,true);assert(cc.nativeJumps==2,'low ceiling cannot lock jumping forever')
end
do
    local n,cc=New(false);Step(n,.016,true);Step(n,.13,false)
    cc.onGround=true;Step(n,.016,false);assert(cc.nativeJumps==0)
    Step(n,.016,true);cc.onGround=false;Step(n,.3,false)
    cc.onGround=true;Step(n,.016,false);assert(cc.nativeJumps==1)
end
-- UI/focus locks, attack locks, plunge and safety must discard pending input.
for _,options in ipairs({{scale=1,jumpAllowed=false},{scale=0},
    {scale=1,plungeVelocity=Vector3(0,-9,0)}}) do
    local n,cc=New(false);Step(n,.016,true)
    Step(n,.016,false,options);cc.onGround=true;Step(n,.016,false)
    assert(cc.nativeJumps==0,'blocked buffer must not launch on release')
    Step(n,.016,true,options);Step(n,.016,false)
    assert(cc.nativeJumps==0,'blocked press must not be queued')
end
do
    local n,cc=New(true);Step(n,.016,false);cc.onGround=false
    n:ResetJump();Step(n,.016,true);assert(cc.airLaunches==0,'teleport/mount clears grace')
    n.UpdateSafety=function()return true end;Step(n,.016,false)
    assert(n.jumpBuffer==0 and n.jumpCoyote==0)
end
print('PASS jump grace: edge/expiry/buffer/one-shot/landing/locks/reset at 30/60/120Hz; native physics not simulated')
