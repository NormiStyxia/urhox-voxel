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
n.yaw=180; n:AssistMelee({Target(30,3)},nil,Vector3.FORWARD,true); S.near(n.yaw,30);S.near(n.camYaw,0)
n.yaw=0; n:AssistMelee({Target(40,3),Target(20,5)},nil,Vector3.FORWARD,true); S.near(n.yaw,40)
n.yaw=0; n:AssistMelee({Target(30,3)},function() return .5 end,Vector3.FORWARD,true); S.near(n.yaw,0)
n.yaw=0; n:AssistMelee({Target(30,3),Target(-10,2)},nil,Vector3.FORWARD,true); S.near(n.yaw,-10)
-- Actual movement method, camera held at yaw 0; all four move directions turn
-- independently and stationary orbit preserves the actor's previous yaw.
for _,v in ipairs({{1,0,0},{0,1,90},{-1,0,180},{0,-1,-90}}) do
    n.yaw=0;n.camYaw=0
    for _=1,120 do n:Move(1/60,v[1],v[2],false,false,false,{scale=1,motion=Vector3.ZERO}) end
    assert(math.abs(n.yaw-v[3])<.001 and n.camYaw==0)
end
n.yaw=45;n.camYaw=170
n:Move(.1,0,0,false,false,false,{scale=1,motion=Vector3.ZERO});S.near(n.yaw,45)
print('PASS actual Nomi Move: gap sweep/no teleport, jump blocked during roll, combat 5m/s/no sprint, bow slow walk')
local debugBody=assert(source:match('(function N:TeleportForCombatDebug.-)\nend'))..'\nend'
env.Terrain.IsSafeGround=function(x) return x<10 end
assert(load(debugBody,'actual safe debug teleport','t',env))()
local moved,cameraUpdates=0,0
n.cc.SetLinearVelocity=function(_,v) S.near(v:Length(),0) end
n.cc.Teleport=function(_,p) moved=moved+1; n.node.worldPosition=p end
n.camTarget={}
n.UpdateCamera=function(_,dt,mode,target) assert(dt==1 and mode=='normal' and target==n.node);cameraUpdates=cameraUpdates+1 end
assert(not n:TeleportForCombatDebug(Vector3(11,6,0),90) and moved==0)
assert(n:TeleportForCombatDebug(Vector3(2,6,3),90))
assert(moved==1 and cameraUpdates==1 and n.safePos.x==2 and n.camYaw==90 and n.camPitch==12)
S.near(n.cc.desiredVelocity:Length(),0);S.near(n.vel:Length(),0)
assert(n.speed==0 and n.safeT==0 and not n.onGround)
print('PASS debug teleport rejects unsafe ground, clears velocity, sets safe fallback and snaps camera')

local C=require('combat.CombatMoves')
local function ground(p) if p.x<1 or p.x>2 then return 0,1 end end
local motion,stopped=C.ClipSlidePath(Vector3.ZERO,Vector3(3,0,0),.32,ground)
assert(stopped and motion.x<=.58 and motion.x>.56,'footprint+margin stops before gap, 2cm refinement')
assert(C.SlideFootprint(Vector3(.7,0,0),.32,ground)==nil,'edge footprint rejects a seemingly solid centre')
assert(C.SlideFootprint(Vector3.ZERO,.32,function() return 0,math.cos(math.rad(36)) end)==nil)
motion,stopped=C.ClipSlidePath(Vector3.ZERO,Vector3(2.2,0,0),.32,function() return 0,1 end,
 function(a,b) assert((b-a):Length()<=.100001); return b.x<.75 end)
assert(stopped and motion.x<.75 and motion.x>=.73,'wall stops at last safe subsegment')
motion,stopped=C.ClipSlidePath(Vector3.ZERO,Vector3(2.2,0,0),.32,
 function(p) return p.x>.8 and .21 or 0,1 end)
assert(stopped and motion.x<=.8,'step rise above .20 rejects traversal')
motion,stopped=C.ClipSlidePath(Vector3.ZERO,Vector3(2.2,0,0),.32,function(p) return p.x*.4,1/math.sqrt(1.16) end)
S.near(motion.x,2.2);assert(not stopped,'walkable shallow slope stays supported')
print('PASS slide full-footprint edge guard, slope/height/wall probes <=.10m and <=.02m refinement')

-- Actual camera methods: framing is independent of player yaw; effects are
-- applied after fresh camera placement and cannot enter the follow state.
local cameraBody=assert(source:match('(function N:SetCombatCamera.-)\n%-%- 只修复'))
local CameraN={}
local rotation=setmetatable({}, {__mul=function(_,v) return v end})
local cameraEnv=setmetatable({N=CameraN,Ray=function(origin,direction) return {origin=origin,direction=direction} end,Quaternion=function() return rotation end},{__index=_G})
assert(load(cameraBody,'actual combat camera framing','t',cameraEnv))()
local cameraNode={position=Vector3(0,0,-5)}
local cameraStub={SetMode=function(self,mode) self.mode=mode end,SetTransitionSpeed=function(self,speed) self.speed=speed end,
 GetNode=function() return cameraNode end,
 Update=function(_,dt,target) cameraNode.position=target.position+Vector3(.55,1.65,-5) end}
local camN=setmetatable({cam=cameraStub,node={worldPosition=Vector3.ZERO},camTarget={position=Vector3.ZERO},camYaw=0,camPitch=12,
 world={RaycastSingle=function() return {hit=false} end},GridHit=function() return {hit=false} end,
 CameraNode=function() return cameraNode end},{__index=CameraN})
camN:SetCombatCamera(Vector3(0,0,10),true,true,false)
for i=1,120 do camN:UpdateCamera(1/60,'combat',camN.node) end
assert(cameraStub.mode=='combatBossBow' and camN.camYaw==0 and camN.camPitch==12)
assert(camN.combatFocusOffset.z>2.99 and camN.combatFocusOffset.z<=3,'70:30 focus with .25s smoothing')
local follow=camN.camTarget.position
for i=1,60 do camN:UpdateCamera(1/60,'combat',camN.node);camN:ApplyCombatOffset(Vector3(.02,0,0)) end
assert(camN.camTarget.position.x==0,'shake never leaks into smoothed follow position')
camN.GridHit=function() return {hit=true,distance=2} end
camN:UpdateCamera(1/60,'combat',camN.node);camN:ApplyCombatOffset(Vector3(.02,0,0))
S.near((cameraNode.position-camN.combatCameraOrigin):Length(),1.7)
camN.combatLookQuiet=.25;camN:UpdateCamera(.1,'combat',camN.node)
assert(camN.combatFocusOffset.z<3,'live player look suppresses target reframing')
print('PASS actual camera 70:30 framing, manual input priority, independent follow/offset, final obstruction guard')
