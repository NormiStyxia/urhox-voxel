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
    assert(e.state==S.TELEGRAPH and e.warning.visible and e.warning.kind==(index==1 and 'fan' or 'ring'))
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
for _,evade in ipairs({Vector3(2,0,0),Vector3(0,0,-1.2),Vector3(0,0,2.30)}) do
    e,c=attack(1); T.Tick(e,.26,evade); T.Tick(e,.15,front)
    assert(c.hits==0); e:Destroy()
end
print('PASS sweep: 120 degree / 2.25m locked cone, misses flank, rear and radius, one 15 damage hit')

e,c=attack(2)
T.Tick(e,.15,front); assert(c.hits==0 and not e.impacted)
T.Tick(e,.03,front); assert(e.impacted and e.warning.visible and e.particles:CountOwner(e)>0)
T.Near(e.warning.radius,.2)
T.Tick(e,.17,front); assert(c.hits==0)
T.Tick(e,.02,front); assert(c.damage==21 and c.hits==1)
T.Tick(e,.26,front); assert(c.hits==1 and e.state==S.RECOVER and not e.warning.visible)
e:Destroy()
for _,evade in ipairs({Vector3(0,.75,2),Vector3(0,0,3.7)}) do
    e,c=attack(2); T.Tick(e,.54,evade); T.Tick(e,.12,front); assert(c.hits==0); e:Destroy()
end
e,c=attack(2); local behind=Vector3(0,0,-2)
e:Update(.2,behind); e:Update(.2,behind); assert(c.hits==1); e:Destroy()
print('PASS slam: ring travels to 3.6m, one 21 damage hit, jump and exit evade, .2s updates cover wavefront')

for _,clear in ipairs({'disable','reset','stagger'}) do
    e,c=attack(2); T.Tick(e,.20,front); assert(e.warning.visible)
    if clear=='disable' then e:SetActive(false); e:SetActive(true)
    elseif clear=='reset' then assert(e:Reset())
    else assert(e:Stagger(.8,false)) end
    assert(not e.warning.visible)
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
local quartz=pose(e,'crystal'); assert(quartz.y> -1.7 and pose(e,'torso').pitch==-90)
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
