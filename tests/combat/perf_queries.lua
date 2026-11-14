local F=dofile('tests/combat/perf_support.lua')
local P,S=F.P,F.S
local H=require('combat.Hit');local C=require('combat.CombatMoves')
local shape={id='body',center=Vector3(0,1,1),radius=.4,enabled=true}
local stone={id='stone_1',center=Vector3(0,1,1),radius=.2,enabled=true}
local calls=0
local enemy={GetHurtShapes=function()calls=calls+1;return {shape,stone}end}
local zone=C.MeleeZone('sword_heavy_release',Vector3.ZERO,Vector3.FORWARD,1,false)
local hits,pool,skip,shapes={},{},{},{}
assert(H.QueryZone({enemy},zone,hits,pool,skip,shapes)==hits and #hits==2)
local record=pool[1]
assert(#H.QueryZone({enemy},zone,hits,pool,skip,shapes)==2 and pool[1]==record and calls==1)
skip[enemy]=true
assert(#H.QueryZone({enemy},zone,hits,pool,skip,shapes)==1 and hits[1].shape==stone,'body skip must not suppress projectile')
skip[H.TargetKey(enemy,'stone_1')]=true
assert(#H.QueryZone({enemy},zone,hits,pool,skip,shapes)==0)
-- Results and hit info intentionally stay owned snapshots for retained callbacks.
local retained={}
local target={ApplyHit=function(_,info)retained[#retained+1]=info;return {hit=true}end}
H.Apply(target,{dmg=2,part='a'});H.Apply(target,{dmg=3,part='b'})
assert(retained[1]~=retained[2] and retained[1].dmg==2)
package.loaded['ui.PixelDraw']={colors={}}
local HUD=require('ui.CombatHUD')
for _,id in ipairs({'sword_light_1','sword_heavy_release'})do
 for _,active in ipairs({false,true})do
  P.BeginFrame();local verified=0
  local z=C.MeleeZone(id,Vector3.ZERO,Vector3.FORWARD,1,false)
  local slam=id=='sword_heavy_release' and active and C.MeleeZone(id,Vector3.ZERO,Vector3.FORWARD,1,true)or nil
  local value={combat=true,moves={StrikeZones=function()return z,slam,active end},camera={WorldToScreenPoint=function()return Vector3(.5,.5,0)end},rangeVisible=function()verified=verified+1;return true end}
  HUD.UpdateRange(value)
  assert(verified==(active and 8 or 4))
  print(string.format('R10 HUD %s active=%s visibilityCalls=%d maxRays=%d',id,tostring(active),verified,verified*2))
  HUD.UpdateRange(value);HUD.UpdateRange(value);assert(verified<=8,'repeated same-frame updates share hard budget')
 end
end
print('PASS pooled QueryZone, per-target skip, independent stones, read-only shape reuse, <=16 HUD rays/frame')
-- Reentrant enemy feedback cannot overwrite a borrowed contact batch or settle
-- a target twice. Keep externally retained hit info independent between swings.
local A=require('combat.CombatAnim');local State=require('combat.CombatState')
local rig={pose='hand',SetActive=function()end,SetPose=function()end,GetStats=function()return {attack=10,speed=1,reach=1}end}
State.Configure{rig=rig};State.Enter();State.FinishTransition();State.Activity(true)
local settled,saved=0,{}
local player
local reentrant={GetHurtShapes=function()return {shape}end,
 ApplyHit=function(_,info)
  settled=settled+1;saved[#saved+1]=info
  player:AfterPose()
  return {hit=true,damage=info.dmg}
 end}
player=C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,
 position=function()return Vector3.ZERO end,forward=function()return Vector3.FORWARD end,enemies=function()return {reentrant}end}
for _=1,2 do
 player.hitstop=0;player:Play('sword_light_1');player:Update(.11,{allowed=true});player:AfterPose();player:AfterPose()
end
assert(settled==2 and saved[1]~=saved[2] and saved[1].dmg==10)
print('PASS reentrant AfterPose cannot corrupt borrowed contacts; retained info remains independent')
-- Actual Scene decoration LOS, including camera origin, collision masks, scope
-- revision, hard budget and terrain rejection (not just a counting HUD stub).
local f=assert(io.open('scripts/ruins/RuinsScene.lua'));local source=f:read('*a');f:close()
local body=assert(source:match('(local rangeRayPool=.-)\nlocal hudAimHits'))
local rayCalls=0;local solid=true;local blocked=false
local cn={worldPosition=Vector3(0,1,-2),worldDirection=Vector3.FORWARD}
local actor={cc={collisionMask=1,collisionLayer=1},CameraNode=function()return cn end,
 SlideRay=function(_,ray,distance,purpose)
  assert(purpose=='range' and type(distance)=='number');rayCalls=rayCalls+1;P.rangeRays=P.rangeRays+1
  if blocked then return {distance=0} end
 end}
local env=setmetatable({SwingPerf=P,nomi_=actor,Terrain={HasGround=function()return solid end},
 Ray=function(o,d)assert(type(o)=='table' and type(d)=='table');return {origin=o,direction=d}end},{__index=_G})
local visible=assert(load(body..'\nreturn CombatRangeVisible','actual range LOS','t',env))()
local from,point=Vector3(0,1,0),Vector3(0,.04,1)
P.BeginFrame();assert(visible(from,point));assert(rayCalls==2)
assert(visible(from,point) and rayCalls==2,'exact same read-only rays share results')
cn.worldPosition=Vector3(.1,1,-2);assert(visible(from,point) and rayCalls==3,'camera change only invalidates its ray')
actor.cc.collisionMask=2;assert(visible(from,point) and rayCalls==5,'mask revision invalidates')
P.Invalidate();assert(visible(from,point) and rayCalls==7,'world scope invalidates')
solid=false;assert(not visible(from,point) and rayCalls==7,'void is never cached visible');solid=true
for i=1,30 do visible(from,Vector3(i*.1,.04,1)) end
assert(P.rangeRays==16);assert(not visible(from,Vector3(9,.04,1)),'unverified point hidden at cap')
P.BeginFrame();blocked=true;assert(not visible(from,point),'next frame wall hides prior visible point')
print('PASS actual Scene LOS same-ray sharing, camera/mask/revision invalidation, void rejection and sixteen-ray hard ceiling')
