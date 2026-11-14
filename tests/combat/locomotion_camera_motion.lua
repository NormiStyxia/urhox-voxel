local S=dofile('tests/combat/locomotion_support.lua')
local Camera=require('combat.CombatCamera')
local cam=Camera.New();local m={sprintWeight=1}
cam:Slide(Vector3.FORWARD)
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
local code=assert(source:match('(function N:Move%(.+)\n%-%- Probe actual'))
local N={}
local env=setmetatable({N=N,WALK=4.2,RUN=7.2,JUMP=6.4,AIR_CONTROL=.35,
 Clamp=function(v,a,b)return math.max(a,math.min(b,v))end,
 WrapDeg=function(a)return (a+180)%360-180 end,Terrain={HasGround=function()return true end}}, {__index=_G})
-- N:Move uses Quaternion(angle, axis); this mock stores only the resulting yaw.
env.Quaternion=function(angle,axis)assert(type(angle)=='number' and type(axis.x)=='number');return {yaw=angle}end
local chunk=assert(load(code,'actual Nomi Move','t',env));chunk()
local jumped=0
local n=setmetatable({camYaw=0,yaw=0,vel=Vector3(0,0,7.2),actualVelocity=Vector3(0,0,7.2),
 node={worldPosition=Vector3.ZERO},cc={onGround=true,Jump=function(_,speed)S.near(speed,6.4);jumped=jumped+1 end},UpdateSafety=function()return false end},{__index=N})
local opts={scale=1,runDistance=1.012,runDirection=Vector3.FORWARD,motion=Vector3.ZERO,slideChecked=true,sprinting=true}
n:Move(.22,1,0,false,false,false,opts);S.near(n.cc.desiredVelocity.z*.22,1.012)
n.vel=Vector3(0,0,7.2);opts.runDistance=nil;opts.sprinting=false;opts.sprintJump=true
n:Move(.01,1,0,false,true,false,opts);S.near(n.cc.desiredVelocity.z,7.2);assert(jumped==1)
n.cc.onGround=false;opts.sprintJump=false
n:Move(.1,1,0,false,false,false,opts)
S.near(n.cc.desiredVelocity.z,7.2+(5-7.2)*(1-math.exp(-12*.35*.1)))
-- Rejected run gesture does not bypass CD; buffered exploration press can retry.
local moves,foot=S.New(false);moves.dodgeCool=.10
S.Tick(moves,.01,{evadePressed=true,evadeHeld=true});assert(moves.buffer=='dodge')
S.Tick(moves,.10,{evadeHeld=true});assert(moves.clip=='dodge_slide' and moves.dodgeCount==1)
print('PASS R9 max-only camera envelopes/disable/bow priority, exact Nomi distance/no double filter, jump carry + air control, explore buffered edge')
-- Execute the actual scene start port inside the hitch handoff, before the
-- remaining real time advances animation; no one-frame return to base pose.
do
 local file=assert(io.open('scripts/ruins/RuinsScene.lua'));local scene=file:read('*a');file:close()
 local body=assert(scene:match('foot_=FootLocomotion.New%({.-start=function%(%)(.-)\n        end,'))
 local moves,foot=S.New(false)
 local env=setmetatable({caster_={},foot_=foot,combatMoves_=moves,combatAnim_=moves.anim,CombatState=S.State},{__index=_G})
 local start=assert(load('return function() '..body..' end','actual R9 scene run start','t',env))()
 foot.ports.start=start
 S.Tick(moves,.52,{evadePressed=true,evadeHeld=true})
 assert(moves.anim:IsPlaying('sprint_loop'))
 for _,track in ipairs(moves.anim.tracks) do
  if track.live and track.clip.id=='sprint_loop' then S.near(track.t,.22);S.near(track.weight,1) end
 end
end
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
