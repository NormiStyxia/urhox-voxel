-- Actual repaired GridHit and weapon code, offline voxel/physics adapter.
-- Native fracture/GPU cost and visible results still require Web acceptance.
local F=dofile('tests/combat/perf_support.lua')
local N=F.LoadNomi()
local E=require('combat.EnvironmentDamage')
local P=require('combat.Projectile')
-- The base animation mock omits Inverse and returns its tiny vector stub.
-- GridHit needs the full arithmetic value type for transformed ray normals.
local qm=getmetatable(Quaternion(0,0,0))
local multiply=qm.__mul
function qm:Inverse()return Quaternion(self.w,-self.x,-self.y,-self.z)end
function qm.__mul(a,b)
    local v=multiply(a,b)
    return b.w==nil and Vector3(v.x,v.y,v.z) or v
end
local volumes,calls={},{}
local function volume(origin,size,dims,rotation,scale)
    rotation=rotation or Quaternion(0,0,0);scale=scale or Vector3(1,1,1)
    local removed={}
    local function key(x,y,z)return x..':'..y..':'..z end
    local node={worldPosition=origin,worldRotation=rotation,worldScale=scale,enabled=true}
    function node:IsEnabled()return self.enabled end
    function node:WorldToLocal(p)
        local d=rotation:Inverse()*(p-origin)
        return Vector3(d.x/scale.x,d.y/scale.y,d.z/scale.z)
    end
    function node:LocalToWorld(p)return origin+rotation*Vector3(p.x*scale.x,p.y*scale.y,p.z*scale.z)end
    local grid={}
    function grid:GetDimensions()return dims end
    function grid:IsSolid(x,y,z)
        return x>=0 and y>=0 and z>=0 and x<dims.x and y<dims.y and z<dims.z and not removed[key(x,y,z)]
    end
    function grid:GetVoxelMaterial()return 1 end
    function grid:Remove(x,y,z)removed[key(x,y,z)]=true end
    local v={destructible=true,collisionLayer=1,voxelSize=size,volumeId=#volumes+1,hardness=1,enabled=true}
    function v:IsEnabledEffective()return self.enabled end
    function v:GetNode()return node end
    function v:GetGrid()return grid end
    function v:GetPaletteDomain()return 0 end
    volumes[#volumes+1]=v
    return v
end
local world={}
function world:GetVolumeCount()return #volumes end
function world:GetVolume(i)return volumes[i+1] end
function world:ApplyDamage(v,center,radius,power)
    assert(v.destructible and not v.timeObject and v.collisionLayer==1,'only opted-in environment')
    assert(power==3,'do not bypass hardness with infinite power')
    local call={volume=v,center=center,radius=radius,removed=0};calls[#calls+1]=call
    if v.hardness>power then return 0 end
    local grid,node=v:GetGrid(),v:GetNode()
    local d=grid:GetDimensions()
    for x=0,d.x-1 do for y=0,d.y-1 do for z=0,d.z-1 do
        local p=node:LocalToWorld(Vector3((x+.5)*v.voxelSize,(y+.5)*v.voxelSize,(z+.5)*v.voxelSize))
        -- Conservative ragged radius: neighbours must STILL survive arrows.
        if grid:IsSolid(x,y,z) and (p-center):Length()<=radius*2 then
            grid:Remove(x,y,z);call.removed=call.removed+1
        end
    end end end
    return call.removed
end
local actor=setmetatable({world=world,aimMask=1},{__index=N})
local castCount=0
local function cast(a,b)
    castCount=castCount+1
    local delta=b-a
    if delta:Length()<1e-8 then return nil end
    local h=actor:GridHit({origin=a,direction=delta:Normalized()},delta:Length())
    return h.hit and h.distance/delta:Length() or nil,h
end
local effects=0
local function new()
    return E.New({world=world,cast=cast,timeObject=function(v)return v.timeObject end,
        feedback=function(e)assert(e.removed>0);effects=effects+1 end})
end
local function reset()volumes={};calls={};castCount=0;effects=0;F.P.BeginFrame()end
local function hit(v,x,y,z)
    return {hit=true,volume=v,voxel={x=x,y=y,z=z},position=v:GetNode():LocalToWorld(Vector3(x*v.voxelSize,(y+.5)*v.voxelSize,(z+.5)*v.voxelSize)),normal=Vector3(-1,0,0)}
end
reset()
for _,size in ipairs({.0625,.125,.25,1}) do
    for _,scale in ipairs({Vector3(1,1,1),Vector3(.5,2,1),Vector3(-2,1,.5)}) do
        local v=volume(Vector3(12,4,-8),size,{x=4,y=4,z=4},Quaternion(0,37,0),scale)
        local damage=new();local h=hit(v,1,1,1)
        local before=F.P.revision
        assert(damage:Arrow({worldHit=h})==1,'one selected cell, including rotated/scaled volumes')
        assert(F.P.revision==before+2,'invalidate queries on both sides of damage callbacks')
        assert(v:GetGrid():IsSolid(0,1,1) and v:GetGrid():IsSolid(2,1,1))
        assert(damage:Arrow({worldHit=h})==0,'stale/empty cell cannot find another cell')
    end
end
local v=volume(Vector3.ZERO,.25,{x=4,y=8,z=4})
local damage=new();local h=hit(v,1,4,1)
for _,field in ipairs({'destructible','enabled'}) do
    v[field]=false;assert(damage:Arrow({worldHit=h})==0);v[field]=true
end
v:GetNode().enabled=false;assert(damage:Arrow({worldHit=h})==0);v:GetNode().enabled=true
v.collisionLayer=2;assert(damage:Arrow({worldHit=h})==0);v.collisionLayer=1
v.timeObject=true;assert(damage:Arrow({worldHit=h})==0);v.timeObject=false
v.hardness=4;assert(damage:Arrow({worldHit=h})==0 and v:GetGrid():IsSolid(1,4,1));v.hardness=1
assert(damage:Arrow({})==0 and damage:Arrow({worldHit={hit=true}})==0,'missing target cannot dig')
assert(damage:Arrow({worldHit=hit(v,-1,0,0)})==0,'invalid cell rejected')
print('PASS arrow exact cell: size/rotation/scale, masks, protected/time objects, hardness, stale cells')

for _,fps in ipairs({30,60,120}) do
    reset();v=volume(Vector3.ZERO,.25,{x=8,y=12,z=8});damage=new()
    local feet=Vector3(-.8,0,.5)
    for frame=0,fps/5 do
        local t=frame/fps
        local root,tip=Vector3(-.4,1.5,.25+t*5),Vector3(.65,1.5,.25+t*5)
        damage:Melee(root,tip,feet,1,'sword_light_1',true,t)
        local n=#calls
        damage:Melee(root,tip,feet,1,'sword_light_1',true,t)
        assert(#calls==n,'same-frame/hitstop repeat cannot deepen cut')
    end
    assert(#calls>=2 and #calls<=4 and castCount<=E.MAX_RAYS,'bounded strip at 30/60/120Hz')
    assert(effects>0)
    for _,c in ipairs(calls) do assert(c.radius==E.LIGHT_RADIUS and c.center.y>feet.y+.15+c.radius*2) end
    for x=0,7 do for z=0,7 do assert(v:GetGrid():IsSolid(x,0,z),'floor intact')end end
    local n=#calls
    damage:Melee(Vector3(-.4,.2,.5),Vector3(.5,.2,.5),feet,2,'plunge_land',true,1)
    damage:Melee(Vector3(-.4,1.5,.5),Vector3(.5,1.5,.5),feet,3,'sword_light_1',false,2)
    assert(#calls==n,'plunge and inactive attack never excavate')
end
reset();v=volume(Vector3.ZERO,.25,{x=4,y=4,z=4});damage=new()
damage:Melee(Vector3(.5,1.5,.5),Vector3(.5,.2,.5),Vector3(-.8,0,.5),1,'sword_heavy_release',true,0)
assert(#calls==0,'upward-facing support protected even if destructible')
reset();v=volume(Vector3.ZERO,.25,{x=4,y=8,z=4});damage=new()
damage:Melee(Vector3(-.4,.3,.5),Vector3(.5,.3,.5),Vector3(-.8,0,.5),1,'sword_light_3',true,0)
assert(#calls==0,'foot-height side hits cannot dig ground')
reset()
local wall=volume(Vector3(-.5,0,0),.25,{x=1,y=12,z=8});wall.destructible=false
v=volume(Vector3.ZERO,.25,{x=4,y=12,z=8});damage=new()
damage:Melee(Vector3(-.1,1.5,.5),Vector3(.5,1.5,.5),Vector3(-1,0,.5),1,'sword_light_1',true,0)
assert(#calls==0,'LOS blocks damage through wall')
reset();v=volume(Vector3.ZERO,.25,{x=4,y=12,z=8});damage=new()
damage:Melee(Vector3(-.4,1.5,.5),Vector3(.5,1.5,.5),Vector3(-1,0,.5),2,'sword_heavy_release',true,0)
assert(#calls==1 and calls[1].radius==E.HEAVY_RADIUS)
print('PASS sword strip/budgets/duplicates/30-120Hz/ground/landing/occlusion')

local function arrowCase(enemyFirst,initial,protected)
    reset();v=volume(Vector3(1,0,0),.25,{x=4,y=8,z=4});v.destructible=not protected
    damage=new()
    local count,enemyHits,drawVisible=0,0,nil
    local enemy={GetHurtShapes=function()return {{id='body',center=Vector3(.5,1.125,.375),radius=.1}}end,
        ApplyHit=function()enemyHits=enemyHits+1;return {hit=true}end}
    local pool=P.New({random=function()return .5 end,cast=cast,enemies=function()return enemyFirst and {enemy} or {}end,
        wallHit=function(event)count=count+1;assert(event.worldHit.volume==v);return damage:Arrow(event)>0 end,
        draw=function(_,visible)drawVisible=visible end})
    assert(pool:Fire(Vector3(0,1.125,.375),Vector3.RIGHT,1,{pierce=0},initial and Vector3(1.3,1.125,.375) or nil))
    pool:Update(.1);pool:Update(.1)
    if enemyFirst then assert(count==0 and #calls==0 and enemyHits==1,'nearest enemy wins')
    elseif protected then assert(count==1 and #calls==0 and pool.pool[1].embedded,'wall stops arrow')
    else assert(count==1 and #calls==1 and calls[1].removed==1 and not pool.pool[1].active and drawVisible==false,'retire once')end
end
arrowCase(false,false,false);arrowCase(false,true,false);arrowCase(true,false,false);arrowCase(false,false,true)
reset();v=volume(Vector3(1,0,0),.25,{x=4,y=8,z=4})
local predictor=P.NewPrediction()
for t=0,30 do P.Predict(predictor,Vector3(0,1.125,.375),Vector3.RIGHT,1,{},t*.016,false,10,cast,{})end
assert(#calls==0,'prediction is read-only')
print('PASS arrow flight/initial sweep/occlusion/retirement and read-only prediction')

local f=assert(io.open('scripts/ruins/RuinsScene.lua'));local source=f:read('*a');f:close()
local function extract(name)
    return assert(source:match('(local function '..name..'.-)\nend'))..'\nend\nreturn '..name
end
local captured={}
local env=setmetatable({combatEnvironment_={Melee=function(_,...)captured={...}end},
    Safe=function(_,fn,...)return pcall(fn,...)end,nomi_={Position=function()return Vector3.ZERO end},
    combatRig_={active='sword',visualState='hand',pose='hand',bladeRoot=Vector3(0,.2,0),bladeTip=Vector3(0,1.2,0),
        entries={sword={pivot={LocalToWorld=function(_,p)return p+Vector3(1,0,0)end}}}}}, {__index=_G})
local route=assert(load(extract('CombatMeleeEnvironment'),'Scene environment route','t',env))()
route({swingSerial=3,hitClip='sword_light_2',age=1},true)
assert(captured[1].x==1 and captured[2].y==1.2 and captured[4]==3 and captured[6]==true)
env.combatRig_.visualState='hang';route({swingSerial=3,hitClip='sword_light_2',age=1},true)
assert(captured[1]==nil and captured[2]==nil,'back-hanging weapon cannot damage world')
print('PASS Scene reads held blade only')

-- Real animation event clock -> CombatMoves.AfterPose -> damage. Tests above
-- exercise geometry; this catches missing or over-eager gameplay wiring.
local C=require('combat.CombatMoves')
local A=require('combat.CombatAnim')
local State=require('combat.CombatState')
local feet=Vector3(-.8,0,.5)
local rig={SetActive=function()end,SetPose=function()end,
    GetStats=function()return {attack=10,speed=1,reach=1,poise=6}end}
local function combat(clip,cancelOnHit)
    reset();v=volume(Vector3.ZERO,.25,{x=4,y=12,z=8});damage=new()
    State.Configure{rig=rig};State.Enter();State.FinishTransition();State.Activity(true)
    local moves
    local enemy={GetHurtShapes=function()return {{id='body',center=feet+Vector3(.5,.5,0),radius=.3}}end,
        ApplyHit=function()moves:Cancel('menu');return {hit=true}end}
    moves=C.New{anim=A.New(F.S.anim.character(),nil),state=State,rig=rig,
        position=function()return feet end,forward=function()return Vector3.RIGHT end,
        enemies=function()return cancelOnHit and {enemy} or {}end,
        environmentMelee=function(m,active)
            damage:Melee(Vector3(-.4,1.5,.5),Vector3(.5,1.5,.5),feet,m.swingSerial,m.hitClip,active,m.age)
        end}
    moves.combo=tonumber(clip:match('(%d)$')) or 0
    assert(moves:Play(clip));return moves
end
for _,clip in ipairs({'sword_light_1','sword_light_2','sword_light_3','sword_light_4','sword_light_5','sword_heavy_release'}) do
    local moves=combat(clip)
    moves:AfterPose();assert(#calls==0,'windup has no environment contact')
    for _=1,100 do moves:Update(.01,{allowed=true});moves:AfterPose() end
    assert(#calls==1,'active blade cuts once with stationary endpoints: '..clip)
    local count=#calls;moves.hitstop=.2
    moves:Update(.05,{allowed=true});moves:AfterPose()
    assert(#calls==count,'recovery cannot cut')
end
local moves=combat('sword_light_1')
moves:Cancel('menu')
for _=1,30 do moves:Update(.01,{allowed=true});moves:AfterPose()end
assert(#calls==0,'cancel before hit_on discards environment contact')
moves=combat('sword_light_1',true)
for _=1,30 do moves:Update(.01,{allowed=true});moves:AfterPose()end
assert(moves.clip==nil and #calls==0,'enemy callback cancellation precedes environment pass')
moves=combat('sword_light_1')
moves:Update(.4,{allowed=true});moves:AfterPose()
assert(#calls==1,'hitch over hit_on/off preserves one pending contact')
moves:AfterPose();assert(#calls==1,'pending contact is consumed once')
print('PASS real attack events: five stages/heavy/windup/recovery/cancel/reentrant cancellation/low FPS')

-- Diagnostics identify the failing stage without changing the carve contract.
reset();v=volume(Vector3.ZERO,.25,{x=4,y=8,z=4});damage=new()
local reports={}
damage.o.trace=function(kind,reason,_,center,radius,removed)
    reports[#reports+1]={kind=kind,reason=reason,center=center,radius=radius,removed=removed}
end
v.destructible=false
for _=1,100 do assert(damage:Arrow({worldHit=hit(v,1,4,1)})==0) end
assert(#reports==1 and reports[1].reason=='protected' and #calls==0)
v.destructible=true
assert(damage:Arrow({worldHit=hit(v,1,4,1)})==1)
assert(#reports==3 and reports[2].reason=='carve-start' and reports[3].reason=='removed')
assert(reports[3].removed==1 and reports[3].radius==.05)
damage.o.trace=function()error('diagnostic sink failed')end
assert(damage:Arrow({worldHit=hit(v,1,4,1)})==0,'diagnostics cannot break gameplay')
print('PASS bounded stage diagnostics: deduplication, real return value, no mutation on rejects, failing sink isolation')
