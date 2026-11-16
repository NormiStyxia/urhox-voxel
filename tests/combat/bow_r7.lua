local S=dofile('tests/combat/core_support.lua')
local P=require('combat.Projectile')
local C=require('combat.CombatMoves')
local A=require('combat.CombatAnim')
local State=require('combat.CombatState')
local function nearVec(a,b) S.near(a.x,b.x);S.near(a.y,b.y);S.near(a.z,b.z) end
for _,u in ipairs({0,.1,.15,.5,.9,1}) do S.near(P.Power(u),(u*u+2*u)/3) end
local calls,sounds,draws=0,0,0
local p=P.New{random=function()calls=calls+1;return .5 end,audio={Play=function()sounds=sounds+1 end},draw=function()draws=draws+1 end}
assert(not p:Fire(Vector3.ZERO,Vector3.FORWARD,.1,{}))
assert(calls==0 and sounds==0 and draws==0 and p.serial==0)
local ok,arrow=p:Fire(Vector3.ZERO,Vector3.FORWARD,.15,{})
assert(ok and calls==4 and sounds==1 and not arrow.critical and arrow.pierce==0)
S.near(arrow.vel.z,60*(.15*.15+2*.15)/3)
p:Update(.1);assert(calls==4,'spread sampled only at launch')
p:Clear()
for i=1,12 do assert(p:Fire(Vector3.ZERO,Vector3.FORWARD,1,{})) end
local serial,played,randomCalls=p.serial,sounds,calls
assert(not p:Fire(Vector3.ZERO,Vector3.FORWARD,1,{}))
assert(p.serial==serial and sounds==played and calls==randomCalls,'full pool has no fake fire cue')

-- Independent analytic reference; frame subdivisions must not change physics.
local function flight(fps,pitch)
 local q=Quaternion(pitch,0,0)*Vector3.FORWARD
 local dir=Vector3(q.x,q.y,q.z)
 local pool=P.New{random=function()return .5 end}
 local _,shot=pool:Fire(Vector3(0,2,0),dir,1,{range=96})
 for i=1,fps do pool:Update(1/fps) end
 local lambda=-20*math.log(.99);local k=(1-math.exp(-lambda))/lambda
 nearVec(shot.pos,Vector3(0,2,0)+dir*(60*k)+Vector3(0,-20*(1-k)/lambda,0))
 S.near(shot.accumulator,0)
 return shot.pos
end
for _,pitch in ipairs({-35,0,35}) do nearVec(flight(30,pitch),flight(60,pitch)) end
p=P.New{random=function()return .5 end}
local _,shot=p:Fire(Vector3.ZERO,Vector3.FORWARD,1,{range=2000})
p:Update(.003);S.near(shot.pos.z,0);p:Update(.006);assert(shot.pos.z>0 and shot.accumulator>0)
p:Update(8);assert(not shot.active,'8 second TTL retires with catch-up')
p:Clear();_,shot=p:Fire(Vector3.ZERO,Vector3.FORWARD,1,{range=1});p:Update(.1);assert(not shot.active and shot.distance<=1+1e-8)

-- Launch-to-tip obstruction is swept before rendering; wall wins equal t.
local hits,casts,wallSounds=0,0,0
local enemy={active=true,GetHurtShapes=function()return {{id='body',center=Vector3(0,0,.6),radius=.1}} end,ApplyHit=function()hits=hits+1;return {hit=true} end}
p=P.New{random=function()return .5 end,enemies=function()return {enemy} end,cast=function(a,b)casts=casts+1;return .5 end,
 audio={Play=function(event)if event=='arrow_hit' then wallSounds=wallSounds+1 end end}}
_,shot=p:Fire(Vector3.ZERO,Vector3.FORWARD,1,{},Vector3(0,0,1))
assert(shot.embedded and hits==0 and casts==1 and wallSounds==1);S.near(shot.pos.z,.5)
p:Update(.2);assert(casts==1 and wallSounds==1)
p:Clear();p.opts.cast=nil;p.opts.enemies=nil
_,shot=p:Fire(Vector3.ZERO,Vector3.FORWARD,1,{attack=10,projectileSpeed=.9})
S.near(shot.fullSpeed,54);S.near(shot.damage,18);assert(shot.sound.material==nil and shot.sound.hitId==nil)

-- Predict uses the real integrator and collision chords <=25cm, no audio/hit.
local prediction=P.NewPrediction();local segments=0
local function floorCast(a,b)
 assert((b-a):Length()<=.250001);segments=segments+1
 return a.y>=0 and b.y<0 and a.y/(a.y-b.y) or nil
end
local dir=Vector3.FORWARD;local stats={range=64}
for frame=1,120 do
 local before=segments
 local used=P.Predict(prediction,Vector3(0,2,0),dir,1,stats,frame/60,false,8,floorCast,{})
 assert(used<=8 and segments-before==used)
 if prediction.valid then break end
end
assert(prediction.valid);S.near(prediction.contact.y,0)
p=P.New{random=function()return .5 end,cast=floorCast}
-- Flight chords are 1/120s (up to .5m); predictor alone has the .25m budget.
p.opts.cast=function(a,b)return a.y>=0 and b.y<0 and a.y/(a.y-b.y) or nil end
_,shot=p:Fire(Vector3(0,2,0),dir,1,stats)
for i=1,120 do p:Update(1/60);if shot.embedded then break end end
assert(shot.embedded and (shot.pos-prediction.contact):Length()<.02)
P.Predict(prediction,Vector3(1,2,0),dir,1,stats,3,false,0,floorCast,{})
assert(not prediction.valid,'changed launch invalidates stale landing marker')

-- Exact 1s full clock, snapshot once, same-frame cancellation wins.
local rig={pose='back',SetActive=function()end,GetStats=function()return {draw=1,attack=8,range=64}end}
function rig:SetPose(pose)self.pose=pose end
local fires,fulls,flashes=0,0,0
function rig:FlashBowFull()flashes=flashes+1 end
local function moves()
 State.Configure{rig=rig};State.Enter();State.FinishTransition();State.SetWeapon('bow');State.FinishTransition();State.Activity(true)
 return C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,position=function()return Vector3.ZERO end,forward=function()return Vector3.FORWARD end,
 audio={Play=function(event)if event=='bow_full' then fulls=fulls+1 end end},
 captureBowShot=function(snapshot)snapshot.cameraOrigin=Vector3(1,2,3) end,
 fire=function(u,stats,crystal,snapshot)fires=fires+1;assert(snapshot.u==u and snapshot.stats==stats and snapshot.cameraOrigin.x==1);return true end}
end
local m=moves()
for i=1,60 do m:Update(1/60,{allowed=true,attack=true}) end
assert(m.charge==1 and m.power==1 and fulls==1 and flashes==1)
for i=1,60 do m:Update(1/60,{allowed=true,attack=true}) end
assert(fulls==1 and flashes==1 and fires==0)
m:Release();assert(m.pendingFire);m:Cancel('focus');m:AfterPose();assert(fires==0)
m=moves();for i=1,30 do m:Update(1/60,{allowed=true,attack=true}) end
m:Release();m:AfterPose();m:AfterPose();assert(fires==1)
local target={hitStop=0};m:Feedback(target,{dmg=8,pos=Vector3.ZERO,dir=dir,swingId='a'}, {hit=true},false,true)
S.near(target.hitStop,.03);S.near(m.hitstop,0)
target.hitStop=0;m:Feedback(target,{dmg=8,pos=Vector3.ZERO,dir=dir,swingId='b',critical=true}, {hit=true},true,true)
S.near(target.hitStop,.06);S.near(m.hitstop,0)
local knocked={hitStop=0,knock={}}
function knocked:Knockback(info,distance)self.knock.distance=distance;self.knock.active=true end
m:Feedback(knocked,{dmg=8,pos=Vector3.ZERO,dir=dir,swingId='c',critical=true},{hit=true},false,true)
S.near(knocked.knock.distance,.16);S.near(knocked.knock.duration,.10)
knocked.boss=true;knocked.hitStop=0
m:Feedback(knocked,{dmg=8,pos=Vector3.ZERO,dir=dir,swingId='d',critical=true},{hit=true,staggered=true},false,true)
assert(not knocked.knock.active);S.near(knocked.hitStop,.10);S.near(m.hitstop,0)
print('PASS R7 formula/minimum/once-only RNG/pool, analytic 30/60fps, TTL/range, initial wall sweep, prediction budget/alignment, full clock/snapshot/cancel, target-only stop')

-- Execute the Scene's actual bow HUD/assist wiring and shared ray accounting.
local file=assert(io.open('scripts/ruins/RuinsScene.lua'));local scene=file:read('*a');file:close()
local code=assert(scene:match('(local hudAimHits.-local function UpdateCombatHUD.-)\nend'))..'\nend\nreturn UpdateCombatHUD'
local shape={id='body',center=Vector3(0,2,16),radius=.4}
local foe={active=true,GetHurtShapes=function()return {shape} end}
local camera={worldPosition=Vector3(0,2,0),worldDirection=Vector3.FORWARD}
local assist,blocked=true,false
local perf={rangeRays=0,rangeUsed=0,gridBudgetExceeded=0}
local hud
local env=setmetatable({Projectile=P,SwingPerf=perf,CombatHit=require('combat.Hit'),
 CombatEnemies=function()return {foe} end,
 CombatCast=function(a,b,decorative)assert(decorative==true);return blocked and a.z>0 and 0 or nil end,
 CombatState={InCombat=function()return true end,Engaged=function()return true end,GetWeapon=function()return 'bow' end,GetSetting=function(key)return key=='aimAssist' and assist end},
 combatRig_={GetStats=function()return {range=64} end,GetHit=function()return {origin=Vector3(0,2,.1)} end,GetBowArrowTip=function()return Vector3(0,2,.6) end},
 combatCameraFrame_={look=1,cross=1},combatMoves_={clip='bow_hold',charge=1},
 CombatHUD={BOW_PREDICTION=true,Set=function(value)hud=value end},combatHUDData={},
 nomi_={Camera=function()return {} end},M={combat={},ride={mode='free'}},animPreview_={index=0},
 time_=0,combatDebugUntil_=0},{__index=_G})
local update=assert(load(code,'actual bow HUD wiring','t',env))()
local function ticks(n)for i=1,n do perf.rangeRays=0;env.time_=env.time_+1/60;update(camera,1/60);assert(perf.rangeRays<=16) end end
ticks(60);assert(env.combatLookScale_<.801 and env.combatLookScale_>=.8,'assist works with FOV disabled')
shape.center=Vector3(math.tan(math.rad(3))*16,2,16);ticks(30);assert(env.combatLookScale_<.801,'3 degree target retains hysteresis')
shape.center=Vector3(math.tan(math.rad(4))*16,2,16);ticks(90);assert(env.combatLookScale_>.999,'outside 3.5 degrees restores sensitivity')
shape.center=Vector3(0,2,16);ticks(60);blocked=true;ticks(90)
assert(env.combatLookScale_>.999 and not hud.bowPrediction.valid,'launch obstruction blocks assistance and landing marker')
blocked=false;assist=false;ticks(60);assert(env.combatLookScale_>.999)
env.CombatHUD.BOW_PREDICTION=false;ticks(1);assert(not hud.bowPrediction.valid,'prediction has an independent off switch')
-- Fallback-budget denial is unknown; it must not manufacture a point at t=0.
prediction=P.NewPrediction()
P.Predict(prediction,Vector3(0,2,0),Vector3.FORWARD,1,{range=64},0,false,8,function()return 0,false end,{})
assert(not prediction.valid and not prediction.working)
print('PASS R7 actual Scene FOV-independent assist,2.5/3.5deg hysteresis,launch LOS,prediction off/unknown,shared16-ray cap')
