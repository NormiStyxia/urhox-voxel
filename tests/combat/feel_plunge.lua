local S=dofile('tests/combat/core_support.lua')
local C=require('combat.CombatMoves');local A=require('combat.CombatAnim')
local State=require('combat.CombatState');local Camera=require('combat.CombatCamera')
local function near(a,b)S.near(a,b,1e-8)end
near(C.PlungeDistance(.10+(-6+math.sqrt(132))/24),2)
near(C.PlungeDistance(.35+1.75/12),4)
near(C.PlungeDistance(.10),0);near(C.PlungeDistance(.35),2.25);near(C.PlungeDistance(.5),4.05)
local rig={SetActive=function()end,SetPose=function()end,GetStats=function()return {attack=10,speed=1}end}
for _,dt in ipairs({1/30,1/60,.007,.13}) do
 local air={y=5,height=5,onGround=false,vx=2,vz=-1}
 State.Configure{rig=rig};State.Enter();State.FinishTransition();State.Activity(true)
 local fxOn,impacts=false,0
 rig.SetPlunging=function(_,on)fxOn=on end
 rig.ImpactFx=function()impacts=impacts+1 end
 local moves=C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,
  position=function()return Vector3.ZERO end,forward=function()return Vector3.FORWARD end,
  airState=function(out)for k,v in pairs(air)do out[k]=v end;return out end}
 assert(moves:StartPlunge(air) and not fxOn)
 local total=0
 for i=1,math.ceil(.6/dt) do
  moves:Update(dt,{allowed=true})
  total=total-moves.plungeVelocity.y*dt
  near(total,C.PlungeDistance(i*dt));near(moves.plungeVelocity.x,2);near(moves.plungeVelocity.z,-1)
  assert(moves.plungeVelocity.y>=-12-1e-8 and moves.plungeVelocity.y<=0)
  assert(impacts==0,'distance alone must not synthesize a grounded impact')
 end
 air.onGround=true;air.y=0
 moves:Update(dt,{allowed=true});assert(impacts==1 and not fxOn)
 for i=1,20 do moves:Update(dt,{allowed=true})end
 assert(impacts==1,'one impact per actual touchdown')
 moves:Cancel('test-reset');air.onGround=false;air.height=5;air.y=5
 assert(moves:StartPlunge(air));moves:Update(.2,{allowed=true});assert(fxOn)
 moves:Cancel('menu');assert(not moves.plunging and not fxOn and impacts==1)
 assert(moves:StartPlunge(air));air.invalid=true;moves:Update(.1,{allowed=true})
 assert(not moves.plunging and not fxOn and impacts==1,'void cancellation cannot emit a landing')
end
-- Cancellation and void detection clear falling FX, including before the hold expires.
local camera=Camera.New()
for _,age in ipairs({0,.1,.2,.35,.6})do
 local out=camera:Update(.016,{plunging=true,plungeAge=age},true,true,true)
 assert(out.fov>=0 and out.fov<=4)
end
camera:Land();near(camera:Update(.016,{},true,true,true).impact.y,-.03)
near(camera:Update(.13,{},true,true,true).impact.y,0)
-- Pose-owned start survives its event boundary for a genuine .08 second blend.
local a=A.New(S.anim.character(),nil,{quantize=false})
a:Play('plunge_start',{fadeIn=0});a:Update(.12);a:Poll()
a:Play('plunge_loop',{fadeIn=.08,params={plungeSpeed=.5}})
local old,new
for _,track in ipairs(a.tracks) do if track.live then
 if track.clip.id=='plunge_start' then old=track else new=track end
end end
assert(old and new and old.stopping and old.weight==1 and new.weight==0)
a:Update(.04);near(old.weight,.5);near(new.weight,.5)
print('PASS plunge analytic distance/30/60/large dt, inertia, real touchdown once, FOV, .08s crossfade')
