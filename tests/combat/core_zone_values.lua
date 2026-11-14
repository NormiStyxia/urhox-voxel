-- Emulate the documented native Vector3 table-field read-by-value boundary.
-- Plain Lua table vectors in older tests mutate in place and hid this defect.
local S=dofile('tests/combat/core_support.lua')
local C=require('combat.CombatMoves')
local H=require('combat.Hit')
local A=require('combat.CombatAnim')
local State=require('combat.CombatState')
local function copy(v)return Vector3(v.x,v.y,v.z)end
local function valueFields(t)
 return setmetatable({}, {__index=function(_,k)
  local v=t[k];return type(v)=='table' and v.x~=nil and copy(v) or v
 end,__newindex=function(_,k,v)t[k]=type(v)=='table' and v.x~=nil and copy(v) or v end})
end
local function freshZone()return valueFields{origin=Vector3.ZERO,source=Vector3.ZERO}end
local probe=freshZone();probe.origin.x=99;assert(probe.origin.x==0,'test must discard property component writes')
local sceneFile=assert(io.open('scripts/ruins/RuinsScene.lua'));local scene=sceneFile:read('*a');sceneFile:close()
local nf=assert(io.open('scripts/ruins/NomiController.lua'));local ns=nf:read('*a');nf:close()
local N={}
local terrain={IsSafeGround=function()return true end,GroundHeight=function()return 6 end}
local function yawRotation(yaw)return Quaternion(0,yaw,0)end
local env=setmetatable({N=N,Terrain=terrain,Quaternion=yawRotation},{__index=_G})
for _,name in ipairs({'TeleportForCombatDebug','AssistMelee'})do
 assert(load(assert(ns:match('(function N:'..name..'.-)\nend'))..'\nend',name,'t',env))()
end
local startCode=assert(scene:match('(local function StartCombatTest%(%).-)\nlocal function HandleCombatDebugKeys'))
local tests=0
for _,yaw in ipairs({0,45,90,180,270})do
 for _,opposite in ipairs({false,true})do
  for _,fixture in ipairs({false,true})do
   for _,wall in ipairs({false,true})do
    local dir=Vector3(math.sin(math.rad(yaw)),0,math.cos(math.rad(yaw)))
    local pos=Vector3(12,6.1,-64)
    local n=setmetatable({node={worldPosition=pos,worldDirection=dir},camTarget={},safePos=pos,
     yaw=yaw,camYaw=yaw+(opposite and 180 or 0),camPitch=12}, {__index=N})
    function n:Position()return copy(self.node.worldPosition)end
    function n:CanSlide()return true end
    function n:UpdateCamera()end
    n.cc={SetLinearVelocity=function()end,Teleport=function(_,p)n.node.worldPosition=copy(p)end}
    -- In normal play, aim at camera intent even with the body initially backwards.
    local targetDir=fixture and dir or Vector3(math.sin(math.rad(n.camYaw)),0,math.cos(math.rad(n.camYaw)))
    local dummy=C.NewTrainingDummy(pos+targetDir*(fixture and 3 or 1.35))
    local rig={SetActive=function()end,SetPose=function()end,GetStats=function()return {attack=10,reach=1,speed=1,poise=6}end}
    State.Configure{rig=rig};State.Enter();State.FinishTransition();State.Activity(true)
    local cast=wall and function()return .5 end or nil
    local m=C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,position=function()return n:Position()end,
     forward=function()return n.node.worldDirection end,
     intent=function()local a=math.rad(n.camYaw);return Vector3(math.sin(a),0,math.cos(a))end,
     assist=function(intent,select)return n:AssistMelee({dummy},cast,intent,select)end,
     enemies=function()return {dummy}end,cast=cast}
    -- Both persistent cached zone fields have native-value semantics.
    m.strikeZone,m.slamZone=freshZone(),freshZone()
    local opts
    if fixture then
     local e=setmetatable({nomi_=n,combatMoves_=m,combatRig_=rig,CombatState=State,trainingDummy_=dummy,animPreview_={index=0},
      Terrain=terrain,Quaternion=yawRotation,DebugPointClear=function()return true end,
      combatArrows_={Clear=function()end},TouchControls={Cancel=function()end},CombatTest={New=function(o)opts=o;return {}end}}, {__index=_G})
     assert(load(startCode..'\nreturn StartCombatTest','actual F11 setup','t',e))()()
     assert(opts.prepare{weapon='sword'})
     S.near(n.camYaw,n.yaw);S.near((n:Position()-(dummy.position-dir*1.35)):Length(),0)
    end
    local hits={}
    m.observe=function(kind,v)if kind=='hit'then hits[v.clip]=(hits[v.clip]or 0)+v.damage end end
    local function tick(input)
     m:Update(1/60,input or {allowed=true});n.node.worldPosition=n:Position()+m.motion
     m:AfterPose();m:AfterPose();State.Update(1/60)
    end
    for i=1,3 do
     tick{allowed=true,attackTap=true}
     S.near(m.hitForward:DotProduct(targetDir),1)
     for _=1,32 do tick()end
     assert((hits['sword_light_'..i]or 0)==(wall and 0 or 10),
      string.format('native zone normal/fixture=%s yaw=%d opposite=%s wall=%s stage=%d damage=%s origin=(%.1f,%.1f,%.1f)',
       tostring(fixture),yaw,tostring(opposite),tostring(wall),i,tostring(hits['sword_light_'..i]),m.strikeZone.origin.x,m.strikeZone.origin.y,m.strikeZone.origin.z))
    end
    for _,full in ipairs({false,true})do
     m:Cancel('test');State.SetBusy(false);State.Activity(true)
     n.node.worldPosition=dummy.position-targetDir*1.35
     m.releaseFull=full;assert(m:Action('heavy'))
     for _=1,60 do tick()end
    end
    assert((hits.sword_heavy_release or 0)==(wall and 0 or 38),'heavy short/full 16+22; no duplicate settlement')
    tests=tests+1
   end
  end
 end
end
-- Translation, height, target eligibility, and caller-owned range samples.
local p=Vector3(30,12,-80);local z=C.MeleeZone('sword_light_1',p,Vector3.RIGHT,1,false,freshZone())
S.near((z.origin-p):Length(),0);S.near((z.source-p-Vector3(0,.9,0)):Length(),0)
local good=C.NewTrainingDummy(p+Vector3(1.35,0,0))
assert(#H.QueryZone({good},z)==1);good.dead=true;assert(#H.QueryZone({good},z)==0);good.dead=false
good.active=false;assert(#H.QueryZone({good},z)==0);good.active=true
assert(#H.QueryZone({C.NewTrainingDummy(p+Vector3(4,0,0)),C.NewTrainingDummy(p+Vector3(1,4,0))},z)==0)
local point=valueFields{world=Vector3.ZERO}
for i=0,24 do
 point.world=C.ZoneBoundary(z,i,16,point.world) -- engine copies this argument
 assert(point.world,'ZoneBoundary must return its Vector3 value')
 local shape={center=point.world,radius=.001,id='edge'}
 assert(#H.QueryZone({{GetHurtShapes=function()return {shape}end}},z)==1)
end
-- Run the actual HUD projection with value-semantic point storage too: merely
-- testing the helper's return would miss a caller that forgets to assign it.
local hf=assert(io.open('scripts/ui/CombatHUD.lua'));local hs=hf:read('*a');hf:close()
local points={}
for i=1,50 do points[i]=valueFields{world=Vector3.ZERO}end
local he=setmetatable({H={},Moves=C,rangePoints=points},{__index=_G})
assert(load(assert(hs:match('(function H.UpdateRange.-)\nlocal data=')),'actual range projection','t',he))()
local projected=0
he.H.UpdateRange{combat=true,moves={StrikeZones=function()return z,nil,true end},
 rangeVisible=function(from,to)
  S.near((from-z.source):Length(),0);assert(to.x>28 and to.y>12 and to.z< -78,'HUD must project translated world boundary')
  return true
 end,camera={WorldToScreenPoint=function(_,world)
  projected=projected+1;assert(world.x>28);return {x=.5,y=.5}
 end}}
assert(projected==25 and points[1].visible)
print('PASS native Vector3 boundary: '..tests..' real Action->animation->zone->LOS->Apply matrices; actual F11 prepare aligns body/camera; all light/heavy damages; translated range samples')
