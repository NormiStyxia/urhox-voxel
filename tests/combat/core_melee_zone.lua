local S=dofile('tests/combat/core_support.lua')
local H=require('combat.Hit')
local C=require('combat.CombatMoves')
local A=require('combat.CombatAnim')
local State=require('combat.CombatState')
local function sphere(x,y,z,r,weak,id)
    return {id=id or 'body',center=Vector3(x,y,z),radius=r or .1,enabled=true,weak=weak or false,material=weak and 'core' or 'soft'}
end
local function enemy(shapes)
    return {active=true,id='test',GetHurtShapes=function()return shapes end}
end
local function query(shape,id,reach,slam)
    return H.QueryZone({enemy({shape})},C.MeleeZone(id or 'sword_light_1',Vector3.ZERO,Vector3.FORWARD,reach,slam))
end
-- Exact spherical boundary intersections: do not check only the sphere centre.
assert(#query(sphere(0,1,1.9,.1))==1,'outer radial tangent')
assert(#query(sphere(0,1,1.91,.1))==0)
local angle=math.rad(65)
assert(#query(sphere(math.sin(angle),1,math.cos(angle),.1))==1,'sphere grazes 60 degree half-angle')
assert(#query(sphere(math.sin(angle),1,math.cos(angle),.05))==0)
assert(#query(sphere(0,2.1,1,.1))==1 and #query(sphere(0,2.11,1,.1))==0)
assert(#query(sphere(0,-.4,1,.1))==1 and #query(sphere(0,-.41,1,.1))==0)
assert(#query(sphere(0,1,-1,.3))==0,'ordinary attacks cannot hit behind')
assert(#query(sphere(0,1,-1,.3),'sword_heavy_release')==1,'heavy spin is full 360')
assert(#query(sphere(0,1,2.3,.1),'sword_light_3')==1,'third zone shifts forward .4')
assert(#query(sphere(0,1,2.31,.1),'sword_light_3')==0)
assert(#query(sphere(0,1,2.4,.1),'sword_light_1',1.3)==1,'reach applied once to radius')
assert(#query(sphere(0,1,2,.1),'sword_heavy_release',1,true)==1)
assert(#query(sphere(1.5,1,1,.1),'sword_heavy_release',1,true)==0,'slam half-angle 45')
-- Real capsule axis crosses the zone but both endpoint spheres miss.
assert(#query({id='capsule',a=Vector3(-3,1,1),b=Vector3(3,1,1),radius=.05})==1)
assert(#query({id='capsule',a=Vector3(-3,3,1),b=Vector3(3,3,1),radius=.05})==0)
assert(#query({id='capsule',a=Vector3(0,-2,1),b=Vector3(0,4,1),radius=.05})==1)
assert(#query({id='capsule',a=Vector3(0,1,1),b=Vector3(0,1,1),radius=.05})==1)
local disabled=sphere(0,1,1,.6);disabled.enabled=false;assert(#query(disabled)==0)
-- Nearest surface contact rather than arbitrary shape order; weakpart metadata.
local shapes={sphere(0,1,1.5,.2,false,'armor'),sphere(0,1,1,.2,true,'core')}
local hits=H.QueryZone({enemy(shapes)},C.MeleeZone('sword_light_1',Vector3.ZERO,Vector3.FORWARD,1))
assert(hits[1].shape.id=='core' and hits[1].shape.weak)
assert((hits[1].pos-shapes[2].center):Length()>.19,'contact is on near surface')
-- REAL F9 geometry: centre feet+(0,1,0), radius .6, hp9999. All blade
-- capsules point behind/down and provably miss; only the authored attack zone
-- may succeed. Integrate W4 root motion, instead of a fabricated always-hit rig.
local function Run(fps,wall)
    local position=Vector3.ZERO
    local dummy=C.NewTrainingDummy(Vector3(0,0,1.35))
    local damage,events={},{}
    local rig={SetActive=function()end,SetPose=function()end,
        GetStats=function()return {attack=10,speed=1,reach=1,poise=6}end,
        GetHit=function()return {origin=position+Vector3(0,2,-2),dir=Vector3(0,-1,0),length=.7,radius=.1}end}
    local function New()
        State.Configure{rig=rig};State.Enter();State.FinishTransition();State.Activity(true)
        local m=C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,
            position=function()return position end,forward=function()return Vector3.FORWARD end,
            enemies=function()return {dummy}end,cast=wall and function()return .5 end or nil,
            feedback=function(e)events[#events+1]={damage=e.damage,part=e.part,pos=e.pos,weapon=e.weapon}end}
        m.observe=function(kind,e)if kind=='hit' then damage[e.clip]=(damage[e.clip] or 0)+e.damage end end
        return m
    end
    local m=New()
    local function tick(input)
        m:Update(1/fps,input or {allowed=true})
        position=position+m.motion
        local blade=rig:GetHit()
        assert(#H.Query({dummy},blade.origin,blade.origin+blade.dir*blade.length,blade.radius)==0,'old blade path must miss in regression')
        m:AfterPose();m:AfterPose() -- duplicate render/query passes never duplicate damage
        State.Update(1/fps)
    end
    for i=1,3 do
        tick({allowed=true,attackTap=true})
        for _=1,math.ceil(fps*.6) do tick() end
    end
    for i=1,3 do assert((damage['sword_light_'..i] or 0)==(wall and 0 or 10),'each light stage must settle once') end
    for _,full in ipairs({false,true}) do
        position=Vector3.ZERO;m=New();m.releaseFull=full
        -- Use actual heavy action and authored event clock, not forced hitOpen.
        assert(m:Action('heavy'))
        for _=1,fps do tick() end
    end
    assert((damage.sword_heavy_release or 0)==(wall and 0 or 38),'short16/full22 from real geometry')
    assert(#events==(wall and 0 or 5),'HitEvent remains once per real settlement')
    return position
end
Run(60,false);Run(30,false);Run(10,false);Run(60,true)
-- Actual active window follows controller translation after hit_on and freezes
-- the attack facing, instead of using a stale world-space root or rotating bone.
local pos=Vector3.ZERO;local yaw=Vector3.FORWARD
local count=0
local target=enemy({sphere(0,1,3.1,.1)})
target.ApplyHit=function()count=count+1;return {hit=true,damage=10}end
local rig={SetActive=function()end,SetPose=function()end,GetStats=function()return {attack=10,speed=1,reach=1}end,
 GetHit=function()error('zone query must not require weapon geometry')end}
State.Configure{rig=rig};State.Enter();State.FinishTransition();State.Activity(true)
local m=C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,
 position=function()return pos end,forward=function()return yaw end,enemies=function()return {target}end}
m:Update(.01,{allowed=true,attackTap=true});m:Update(.09,{allowed=true});m:AfterPose();assert(count==0)
pos=Vector3(0,0,1.5);yaw=Vector3(0,0,-1);m:AfterPose();assert(count==1,'zone translates while facing stays hit_on snapshot')
m:Cancel('menu');m:AfterPose();assert(count==1,'cancel closes zone immediately')
print('PASS core_melee_zone: real F9 geometry vs missing blade, all light/heavy hits at 10/30/60FPS, walls/dedup/weakpart/contact, sector/height/range/capsule/translation')

-- Multiple parts on one enemy and multiple overlapping zones remain one health
-- settlement. Weak metadata belongs to the nearest visible shape, not rig pose.
local settlements,which,dirs=0,{},{}
local parts=enemy({sphere(0,1,1.4,.2,false,'armor'),sphere(0,1,1,.2,true,'core')})
parts.ApplyHit=function(_,info)
 settlements=settlements+1;which[#which+1]=info.part;dirs[#dirs+1]=info.dir
 return {hit=true,damage=10,weak=info.part=='core'}
end
State.Configure{rig=rig};State.Enter();State.FinishTransition();State.Activity(true)
local player=C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,
 position=function()return Vector3.ZERO end,forward=function()return Vector3.FORWARD end,enemies=function()return {parts}end}
player:Update(.01,{allowed=true,attackTap=true});player:Update(.10,{allowed=true});player:AfterPose()
player:AfterPose();assert(settlements==1 and which[1]=='core' and player.lastHitWeak and dirs[1].z==1)
player:Cancel('test');State.SetBusy(false);State.FinishTransition();State.Activity(true)
player.releaseFull=false;assert(player:Action('heavy'))
player:Update(.30,{allowed=true});player:AfterPose();player:AfterPose()
assert(settlements==2,'360 spin + forward slam overlap must not double damage')
print('PASS nearest weak shape feeds unchanged HitEvent; body/armor overlaps and spin/slam union settle once')
