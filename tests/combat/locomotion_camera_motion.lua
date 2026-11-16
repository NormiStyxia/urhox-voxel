local S=dofile('tests/combat/locomotion_support.lua')
local Camera=require('combat.CombatCamera')
local cam=Camera.New();local m={sprintWeight=1}
for i=1,30 do
 local out=cam:Update(.01,m,true,true,true)
 assert(out.fov<=1.5+1e-8 and out.distance<=.2+1e-8)
end
S.near(cam.output.fov,1.5);S.near(cam.output.distance,.2)
m.sprintWeight=0;cam:Update(.18,m,true,true,true);S.near(cam.output.fov,0)
m.sprintWeight=1;cam:Update(.3,m,true,true,true)
m.clip,m.charge='bow_hold',1;cam:Update(.01,m,true,true,true);S.near(cam.output.fov,-8.25)
m.clip=nil;cam:Cancel();cam:Update(.2,m,false,false,false);S.near(cam.output.fov,0);S.near(cam.output.distance,0)
cam:Update(.3,m,true,true,false);S.near(cam.output.fov,0)
-- Execute actual Nomi movement body with documented engine ports only.
local file=assert(io.open('scripts/ruins/NomiController.lua'));local source=file:read('*a');file:close()
local code=assert(source:match('(function N:ResetJump%(.+)\n%-%- Probe actual'))
local N={}
local env=setmetatable({N=N,WALK=4.2,RUN=7.2,JUMP=6.4,AIR_CONTROL=.35,COYOTE_TIME=.12,JUMP_BUFFER=.12,
 Clamp=function(v,a,b)return math.max(a,math.min(b,v))end,
 WrapDeg=function(a)return (a+180)%360-180 end,Terrain={HasGround=function()return true end}}, {__index=_G})
-- N:Move uses Quaternion(angle, axis); this mock stores only the resulting yaw.
env.Quaternion=function(angle,axis)assert(type(angle)=='number' and type(axis.x)=='number');return {yaw=angle}end
local chunk=assert(load(code,'actual Nomi Move','t',env));chunk()
local jumped=0
local n=setmetatable({camYaw=0,yaw=0,vel=Vector3(0,0,7.2),actualVelocity=Vector3(0,0,7.2),
 node={worldPosition=Vector3.ZERO},cc={onGround=true,Jump=function(_,speed)S.near(speed,6.4);jumped=jumped+1 end},UpdateSafety=function()return false end},{__index=N})
local opts={scale=1,baseSpeed=5,motion=Vector3.ZERO,motionChecked=true,sprinting=true}
-- Identical held-run target in combat and exploration; no secondary displacement.
for _,explore in ipairs({true,false}) do
 opts.explore=explore;opts.baseSpeed=explore and 4.2 or 5
 n.vel=Vector3.ZERO
 for _=1,120 do n:Move(1/60,1,0,true,false,false,opts) end
 S.near(n.cc.desiredVelocity.z,7.2)
 n:Move(.1,1,0,false,false,false,opts)
 assert(n.cc.desiredVelocity.z<7.2 and n.cc.desiredVelocity.z>opts.baseSpeed)
end
opts.scale=0;n:Move(.01,1,0,true,false,false,opts);S.near(n.cc.desiredVelocity:Length(),0)
opts.scale=1;n.vel=Vector3(0,0,7.2)
n:Move(.01,1,0,true,true,false,opts);S.near(n.cc.desiredVelocity.z,7.2);assert(jumped==1)
n.cc.onGround=false
n:Move(.1,1,0,false,false,false,opts)
S.near(n.cc.desiredVelocity.z,7.2+(5-7.2)*(1-math.exp(-12*.35*.1)))
-- Shared low-priority pool remains bounded: one footprint, no new pool/node.
do
 local Moves=require('combat.CombatMoves')
 local pool={serial=0,slots={},count=0,limit=64,reserved=16}
 for i=1,6 do pool.slots[i]={} end
 function pool:Emit(owner)
  for _,slot in ipairs(self.slots) do self.serial=self.serial+1;slot.owner=owner;slot.serial=self.serial;slot.active=true;self.count=self.count+1 end
 end
 function pool:Hide(slot)if slot.active then slot.active=false;self.count=self.count-1 end end
 local owner={}
 assert(Moves.EmitDustStreak(pool,owner,Vector3.ZERO,Vector3.FORWARD,function()return 0 end,1)==1)
 assert(pool.count==1)
 pool.count=43;local serial=pool.serial
 assert(Moves.EmitDustStreak(pool,owner,Vector3.ZERO,Vector3.FORWARD,function()return 0 end,1)==0 and pool.serial==serial)
end
print('PASS actual Scene creates run before hitch tail advances; one pooled footprint / key-event reserve preserved')
-- Real controller descent port uses existing velocity setter, not root translation.
n.cc.onGround=false;n.cc.SetLinearVelocity=function(_,v)n.lastVertical=v end
opts.scale=0;opts.plungeVelocity=Vector3(2,-9,1)
n:Move(.016,-1,1,true,false,false,opts)
S.near(n.lastVertical.y,-9);S.near(n.cc.desiredVelocity.x,2);S.near(n.cc.desiredVelocity.z,1)
local airCode=assert(source:match('(function N:MeasureMotion%b().-)\nend'))..'\nend\n'
 ..assert(source:match('(function N:CombatAirState%b().-)\nend'))..'\nend'
local groundQueries=0;env.Terrain.GroundHeight=function()groundQueries=groundQueries+1;return 0 end
assert(load(airCode,'actual cached air state','t',env))()
n.cc.GetLinearVelocity=function()return Vector3(2,-18,1)end
n.node.worldPosition=Vector3(0,2,0);n:MeasureMotion(.016)
local out={};local q=groundQueries
for _=1,100 do assert(n:CombatAirState(out)==out);S.near(out.height,2);assert(not out.invalid)end
assert(groundQueries==q,'eligibility reuses current frame height; no additional ground query/ray')
n.cc.onGround=true;n.node.worldPosition=Vector3(0,1,0);n:MeasureMotion(.016);S.near(n:CombatAirState(out).height,0)
n.cc.onGround=false;n.node.worldPosition=Vector3(0,1.5,0);n:MeasureMotion(.016);S.near(n:CombatAirState(out).height,.5)
n.voidReturning=true;assert(n:CombatAirState(out).invalid)
print('PASS actual CC consumes authored velocity, locked horizontal inertia, cached physical/terrain support and void rejection')

-- Airborne over a bridge keeps nearby physical support; a real landing is never
-- rejected merely because the terrain heightmap has no island under the bridge.
env.Terrain.GroundHeight=function()return nil end
n.voidReturning=false;n.cc.onGround=true;n.node.worldPosition=Vector3(3,4,5);n:MeasureMotion(.016)
assert(not n:CombatAirState(out).invalid);S.near(out.height,0)
n.cc.onGround=false;n.node.worldPosition=Vector3(3,5,5);n:MeasureMotion(.016);S.near(n:CombatAirState(out).height,1)
n.node.worldPosition=Vector3(4,5,5);n:MeasureMotion(.016);assert(n:CombatAirState(out).invalid)
-- Ring emission borrows only the prebuilt slots and respects the shared pool.
do
 local Moves=require('combat.CombatMoves')
 local Particles=require('combat.enemies.EnemyParticles')
 local pool=Particles.Acquire(nil,nil,{})
 local owner={};local refs={}
 for i,v in ipairs(pool.slots)do refs[i]=v end
 for _=1,100 do
  Moves.EmitImpactRing(pool,owner,Vector3.ZERO,Vector3.FORWARD)
  assert(pool:CountOwner(owner)<=6)
  pool:UpdateOwner(owner,1)
 end
 for i,v in ipairs(pool.slots)do assert(refs[i]==v)end
 pool:Release(owner)
end
print('PASS bridge/void support cache and 100 landing rings reuse the same particle slots')
