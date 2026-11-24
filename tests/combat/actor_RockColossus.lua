package.path='scripts/?.lua;tests/?.lua;'..package.path
local T=require('combat.enemy_support')
local Rock=require('combat.enemies.actors.RockColossus')
local S=Rock.State
local model=require('combat.enemies.models.RockColossus').Build()
local front=Vector3(0,0,2)
local function new()
    local terrain,combat=T.Fixture()
    return Rock.New(nil,nil,terrain,combat,Vector3.ZERO,'rock'),combat
end
local function pose(e,id)
    local p={x=0,y=0,z=0,pitch=0,yaw=0,roll=0,sx=1,sy=1,sz=1}
    e.config.posePart(e,id,p)
    return p
end
local function attack(index)
    local e,c=new()
    e:Update(.01,front)
    T.Tick(e,.40,front)
    assert(e.state==S.CHASE and not e.boss)
    e.attackIndex=index-1
    e:Update(.01,front)
    assert(e.state==S.TELEGRAPH and e.warning.visible and e.warning.kind==(index==1 and 'fan' or 'fault_strip'))
    T.Tick(e,e.attack.telegraph-.01,front)
    assert(e.directionLocked and c.hits==0 and e.state==S.TELEGRAPH)
    local ready=pose(e,'fist_r')
    assert(index==1 and ready.yaw>60 or index==2 and ready.y>1)
    if index==2 then
        for _,h in ipairs(e:GetHurtShapes()) do
            if h.id=='fist_r' then assert(h.center.y>2.9,'raised fist must remain hittable overhead') end
        end
    end
    e:Update(.01,front)
    assert(e.state==S.ATTACK)
    return e,c
end

local e,c=attack(1)
T.Tick(e,.09,front); assert(c.hits==0)
T.Tick(e,.05,front); assert(c.damage==15 and c.hits==1)
T.Tick(e,.27,front); assert(e.state==S.RECOVER and c.hits==1)
assert(pose(e,'fist_r').yaw < -60)
T.Tick(e,.83,front); assert(e.state==S.TELEGRAPH and e.attack==Rock.Config.attacks[2])
e:Destroy()
for _,evade in ipairs({Vector3(2,0,0),Vector3(0,0,-1.2),Vector3(0,0,2.90)}) do
    e,c=attack(1); T.Tick(e,.26,evade); T.Tick(e,.15,front)
    assert(c.hits==0); e:Destroy()
end
print('PASS sweep: 120 degree / 2.85m locked cone, misses flank, rear and radius, one 15 damage hit')

local Fault=require('combat.enemies.actors.RockColossusFault')
for i=1,Fault.COUNT do
    e,c=attack(2)
    local section=e.fault.sections[i]
    local spot=Vector3(0,0,section.distance)
    T.Tick(e,section.start-.01,spot);assert(c.hits==0 and section.warn)
    e:Update(.02,spot);assert(c.hits==1 and c.damage==21 and section.height>0 and not section.warn)
    T.Tick(e,1.5-section.start,spot);assert(c.hits==1 and not e.fault.active);e:Destroy()
end
for _,safe in ipairs({Vector3(.90,0,2.2),Vector3(0,0,-1),Vector3(0,0,6.30),Vector3(0,3,2.23)}) do
    e,c=attack(2);T.Tick(e,1.41,safe);assert(c.hits==0);e:Destroy()
end
e,c=attack(2);e:Update(.2,Vector3(0,0,2.23));e:Update(.2,Vector3(0,0,2.23));assert(c.hits==1);e:Destroy()
print('PASS five locked warning footprints, separate eruption windows, airborne/side/rear/outside evade, coarse frame')

for _,clear in ipairs({'disable','reset','stagger'}) do
    e,c=attack(2); T.Tick(e,.20,front); assert(e.fault.active)
    if clear=='disable' then e:SetActive(false); e:SetActive(true)
    elseif clear=='reset' then assert(e:Reset())
    else assert(e:Stagger(.8,false)) end
    assert(not e.warning.visible and not e.fault.active and e.particles:CountOwner(e)==0)
    T.Tick(e,.38,front); assert(c.hits==0); e:Destroy()
end

e,c=attack(2)
local hits=e:ApplyHit({dmg=2,kind='arrow',part='torso',dir=Vector3.RIGHT})
assert(hits.hit and e.particles:CountOwner(e)>0)
local shoulder,chest=pose(e,'upper_arm_r'),pose(e,'torso')
assert(shoulder.roll>0 and chest.x<0)
local died=0
e.onEvent=function(name) if name=='die' then died=died+1 end end
local killed=e:ApplyHit({dmg=900,dir=Vector3.FORWARD})
assert(killed.killed and c.deaths==1 and not e.warning.visible)
T.Tick(e,.80,front); assert(c.hits==0 and died==1 and e.deathBurst)
local quartz=pose(e,'crystal'); assert(quartz.y> -2.5 and pose(e,'torso').pitch==-90)
T.Tick(e,.46,front); assert(e.deathFinished and died==1 and c.deaths==1 and e.particles:CountOwner(e)==0)
for _,part in ipairs(model.parts) do
    local p=pose(e,part.id)
    local foot=math.huge
    local angle=math.rad(p.pitch)
    for _,cell in ipairs(part.cells) do
        for dy=0,1 do for dz=0,1 do
            local y=(cell[2]+dy)*model.size-part.pivot[2]
            local z=(cell[3]+dz)*model.size-part.pivot[3]
            foot=math.min(foot,part.pivot[2]+p.y+y*math.cos(angle)-z*math.sin(angle))
        end end
    end
    T.Near(foot,0)
end
e:Destroy()
print('PASS interruption, shoulder/chest recoil, stone chips, one death callback, crystal lands last and all 9 parts rest on ground')

-- Shoot three real pooled arrows from the same distance. Projectile.Step calls
-- Hit.Query and sorts all hurt spheres before settling just the first contact.
dofile('tests/combat/core_support.lua')
local Arrows=require('combat.Projectile')
local arrowCases={{'upper_arm_l',.55},{'torso',1},{'crystal',1.85}}
for _,case in ipairs(arrowCases) do
    e,c=new();local center
    for _,h in ipairs(e:GetHurtShapes()) do if h.id==case[1] then center=h.center end end
    local landed
    local arrows=Arrows.New{random=function() return .5 end,enemies=function() return {e} end,
        hit=function(_,info,result) landed=result;T.Near(result.damage,info.dmg*case[2]) end}
    assert(arrows:Fire(center+Vector3(0,.04,3),Vector3(0,0,-1),1,{attack=10}))
    arrows:Update(.12);assert(landed and landed.part==case[1]);print(case[1],landed.material,landed.damage)
    e:Destroy()
end
