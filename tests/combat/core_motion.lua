local S=dofile('tests/combat/core_support.lua')
local file=assert(io.open('scripts/ruins/NomiController.lua')); local source=file:read('*a');file:close()
local body=source:match('(function N:Move.-)\n%-%- 仅 Scene')
assert(body)
local N={}
local env=setmetatable({N=N,WALK=4.2,RUN=7.2,AIR_CONTROL=.35,JUMP=6.4,
    WrapDeg=function(a) return a end,Quaternion=function() return {} end,
    Clamp=function(v,a,b) return math.max(a,math.min(b,v)) end,
    Terrain={HasGround=function(x,z,margin) return x<1 or x>2 end}}, {__index=_G})
assert(load(body,'actual Nomi Move','t',env))()
local n=setmetatable({vel=Vector3.ZERO,node={worldPosition=Vector3.ZERO},camYaw=0,yaw=0,
    cc={onGround=true,Jump=function() error('must not jump during roll') end},UpdateSafety=function() return false end},{__index=N})
n:Move(.1,0,0,false,true,true,{scale=0,motion=Vector3(3,0,0)})
assert(n.cc.desiredVelocity.x*.1<1,'dodge must stop before gap even when endpoint is solid')
n:Move(.1,1,0,true,false,false,{scale=1,motion=Vector3.ZERO})
S.near(n.cc.desiredVelocity.z,5)
n:Move(.1,1,0,true,false,false,{scale=.5,motion=Vector3.ZERO})
S.near(n.cc.desiredVelocity.z,2.5)
n.Position=function() return Vector3.ZERO end
local function Target(angle,dist)
    local rad=math.rad(angle)
    return {active=true,position=Vector3(math.sin(rad)*dist,0,math.cos(rad)*dist)}
end
n.yaw=0; n:AssistMelee({Target(30,3)},function() return nil end); S.near(n.yaw,20)
n.yaw=0; n:AssistMelee({Target(40,3),Target(20,5)},function() return nil end); S.near(n.yaw,0)
n.yaw=0; n:AssistMelee({Target(30,3)},function() return .5 end); S.near(n.yaw,0)
n.yaw=0; n:AssistMelee({Target(30,3),Target(-10,2)},function() return nil end); S.near(n.yaw,-10)
print('PASS actual Nomi Move: gap sweep/no teleport, jump blocked during roll, combat 5m/s/no sprint, bow slow walk')
