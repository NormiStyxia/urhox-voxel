local S=dofile('tests/combat/core_support.lua')
local C=require('combat.CombatMoves')
local A=require('combat.CombatAnim')
local State=require('combat.CombatState')
local Camera=require('combat.CombatCamera')
local Hit=require('combat.Hit')
local function enemy(x,z) return C.NewTrainingDummy(Vector3(x,0,z)) end
local a,b,behind,far,dead,off=enemy(0,2.5),enemy(1,1),enemy(0,-1),enemy(0,3.61),enemy(0,1),enemy(0,1)
dead.dead=true;off.active=false
local direction,target=C.SelectMeleeTarget(Vector3.ZERO,Vector3.FORWARD,{b,a,behind,far,dead,off})
assert(target==a and direction.z==1,'intent alignment outweighs a nearer side target')
direction,target=C.SelectMeleeTarget(Vector3.ZERO,Vector3.RIGHT,{a,b})
assert(target==b,'movement intention can choose side of camera')
local wall=function()return .5 end
for _,targets in ipairs({{behind},{far},{dead},{off},{a}}) do
 direction,target=C.SelectMeleeTarget(Vector3.ZERO,Vector3.FORWARD,targets,targets[1]==a and wall or nil)
 assert(not target and direction.z==1,'no hidden/remote/dead/inactive/behind selection')
end
local rig={SetActive=function()end,SetPose=function()end,GetStats=function()return {attack=10,speed=1,reach=1,draw=.7}end}
local position,forward=Vector3.ZERO,-Vector3.FORWARD
local cam=Camera.New()
local calls=0
local function new()
 State.Configure{rig=rig};State.Enter();State.FinishTransition();State.Activity(true)
 return C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,camera=cam,
 position=function()return position end,forward=function()return forward end,
 intent=function()return Vector3.FORWARD end,enemies=function()return {a}end,
 assist=function(intent,select)
  calls=calls+1
  local dir,t=C.SelectMeleeTarget(position,intent,select and {a} or {})
  forward=dir;return dir,t
 end,attackMotion=function(v)return C.ClipSlidePath(position,v,.32,function()return 0,1 end,function(_,to)return to.z<.28 end)end}
end
local m=new();assert(m:Action('light'));assert(forward.z==1 and m.hitForward.z==1,'body turns before hit_on')
local z,_,active=m:StrikeZones();assert(z and not active and z.forward.z==1)
local cached=z
a.position=Vector3(3,0,0);forward=Vector3.RIGHT
m:Update(.11,{allowed=true,axis=Vector3.RIGHT});position=position+m.motion
z,_,active=m:StrikeZones();assert(z==cached and active and z.forward.z==1 and m.motion.x==0 and calls==1,'action never reselects or bends')
local boundary=Vector3.ZERO
for i=0,24 do
 C.ZoneBoundary(z,i,16,boundary)
 local shape={id='boundary',center=boundary,radius=.001}
 assert(#Hit.QueryZone({{active=true,GetHurtShapes=function()return {shape}end}},z)==1,'every displayed sample belongs to actual hit region')
end
for _=1,20 do m:Update(.01,{allowed=true});position=position+m.motion;m:AfterPose() end
assert(position.z<.28 and position.z>=.26,'authored lunge stops at wall without additive movement')
assert(not m:StrikeZones(),'no recovery ring')
m:Cancel('menu');assert(not m:StrikeZones())
-- All three light stages and both heavy zones share the exact region builder.
for _,id in ipairs({'sword_light_1','sword_light_2','sword_light_3','sword_heavy_release'}) do
 local zone=C.MeleeZone(id,Vector3.ZERO,Vector3.RIGHT,1.3)
 for i=0,16 do
  C.ZoneBoundary(zone,i,16,boundary)
  local radius=math.sqrt((boundary.x-zone.origin.x)^2+(boundary.z-zone.origin.z)^2)
  S.near(radius,zone.radius)
 end
end
-- Real Moves cancellation drives the same camera output for PC/touch callers.
for _,reason in ipairs({'menu','focus','touchcancel','dodge','swap','exit','death','mount'}) do
 m=new();State.SetBusy(false);State.SetWeapon('bow');State.FinishTransition();State.Activity(true)
 m:Cancel('setup');m.blocked=false;m:Action('hold')
 m.clip='bow_hold';m.charge=.01
 cam:Update(.2,m,true,false);S.near(cam.output.fov,-12);S.near(cam.output.look,.6)
 m:Cancel(reason);assert(m.pendingFire==nil and m.charge==0)
 cam:Update(.1,m,true,false);S.near(cam.output.fov,0);S.near(cam.output.look,1)
end
cam=Camera.New();cam:Update(.1,{clip='bow_draw',charge=0},true,false);S.near(cam.output.fov,-6)
cam:Update(.1,{clip='bow_draw',charge=0},true,false);S.near(cam.output.fov,-12)
cam:Update(.01,{clip='bow_draw',charge=1},false,false);S.near(cam.output.fov,0);S.near(cam.output.look,1)
print('PASS free-facing: intent selection/filter/turn snapshot, shared region samples, physical lunge clipping, bow zoom start/disable/all cancel reasons')
-- Real release and cosmetic cancellation tracks retain the pose snapshot even
-- after gameplay charge becomes zero and the user rotates the camera.
for _,kind in ipairs({'release','cancel'}) do
 m=new();State.SetBusy(false);State.SetWeapon('bow');State.FinishTransition();State.Activity(true)
 m.o.aimPitch=function()return 28 end
 m:Cancel('setup');m.blocked=false;m:Action('hold');m:Play('bow_hold');m.charge=.83
 if kind=='release' then m:Release() else m:Cancel('focus') end
 local id=kind=='release' and 'bow_release' or 'bow_cancel'
 m.o.aimPitch=function()return -30 end
 for frame=0,16 do
  local p,pitch=m:BowParameters(-30)
  S.near(p,.83);S.near(pitch,28)
  m.anim:SetParam('p',p);m.anim:SetParam('aimPitch',pitch)
  for _,track in ipairs(m.anim.ordered) do if track.live and track.clip.id==id then
   S.near(track.params.p,.83);S.near(track.params.aimPitch,28)
  end end
  m:Update(.01,{allowed=kind~='cancel'});m:AfterPose()
 end
 if kind=='cancel' then assert(m.pendingFire==nil and m.charge==0) end
 for _=1,8 do m:Update(.01,{allowed=true});m:AfterPose() end
 local p,pitch=m:BowParameters(-30);S.near(p,0);S.near(pitch,-30)
end
print('PASS W4 actual release/cancel first-frame and entire recovery snapshot p/pitch; no cancelled shot')

-- Static Time binding must win over a broken instance receiver.
local oldTime,oldGetTime=Time,GetTime
local instanceCalls,staticCalls=0,0
Time={GetSystemTime=function(receiver)assert(receiver==Time);staticCalls=staticCalls+1;return 100 end}
GetTime=function()instanceCalls=instanceCalls+1;error('invalid instance receiver')end
assert(State.Isolated('test-static-clock',function()return true end))
assert(staticCalls==1 and instanceCalls==0)
Time,GetTime=oldTime,oldGetTime
print('PASS static Time receiver preserved in isolation clock')
-- Execute Scene's actual FOV composition with a fresh 55-degree base each frame.
local f=assert(io.open('scripts/ruins/RuinsScene.lua'));local scene=f:read('*a');f:close()
local code=assert(scene:match('(local function UpdateCombatCamera.-)\nend'))..'\nend\nreturn UpdateCombatCamera'
local camera={fov=55};local cm={clip='bow_hold',charge=.01,ShakeOffset=function()return Vector3.ZERO end,FovOffset=function()return 0 end}
local env=setmetatable({combatCamera_=Camera.New(),combatMoves_=cm,CombatState=State,M={ride={mode='free'}},
 animPreview_={index=0},nomi_={ApplyCombatOffset=function()end,Camera=function()return camera end}},{__index=_G})
local update=assert(load(code,'actual Scene zoom composition','t',env))()
State.SetSetting('cameraFov',true)
for _=1,120 do camera.fov=55;update(1/60,{worldDirection=Vector3.FORWARD});assert(camera.fov>=43-1e-8) end
S.near(camera.fov,43)
cm.clip=nil;camera.fov=55;update(.1,{worldDirection=Vector3.FORWARD});S.near(camera.fov,55)
print('PASS actual Scene FOV composition: one 55->43 envelope, no double zoom or drift, restore55')

m=new();State.SetBusy(false);State.SetWeapon('bow');State.FinishTransition();State.Activity(true)
m:Cancel('setup');m.blocked=false;m:Action('hold');m:Play('bow_hold');m.charge=.8
m:Cancel('focus');assert(m.anim:IsPlaying('bow_cancel'))
assert(m:Action('dodge',Vector3.RIGHT));assert(not m.anim:IsPlaying('bow_cancel'),'slide interrupts cosmetic cancel even with protection preservation')
print('PASS hard action removes cosmetic bow cancel before slide')
