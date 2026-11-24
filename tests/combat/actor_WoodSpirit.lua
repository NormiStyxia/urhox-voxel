package.path = 'scripts/?.lua;tests/?.lua;' .. package.path
local T = require('combat.enemy_support')
local Wood = require('combat.enemies.actors.WoodSpirit')
local S = Wood.State
local function pose(enemy, id)
    local p = {x=0,y=0,z=0,pitch=0,yaw=0,roll=0,sx=1,sy=1,sz=1}
    enemy.config.posePart(enemy,id,p)
    return p
end
local function approach(range)
    local terrain, combat = T.Fixture()
    combat.pos = Vector3(0,0,range)
    local e = Wood.New(nil,nil,terrain,combat,Vector3.ZERO,'sprout')
    e:Update(.01)
    T.Tick(e,.42)
    assert(e.state==S.TELEGRAPH and e.warning.visible)
    return e,combat
end
local function lock(e)
    T.Tick(e,e.attack.telegraph-.12-e.stateTime)
    assert(e.directionLocked and e.state==S.TELEGRAPH)
end

for index, distance in ipairs({1.23,2.25}) do
    local e,c = approach(distance)
    local a = e.attack
    assert(a==Wood.Config.attacks[index] and e.warning.kind==(index==1 and 'fan' or 'line'))
    lock(e)
    local leaf,root = pose(e,'leaf_r'),pose(e,'root_front_r')
    assert(leaf.roll < -15 and root.x > .02 and root.z > .02)
    T.Tick(e,.12+a.start-.01)
    assert(e.state==S.ATTACK and c.hits==0)
    -- .20s frames cover several contact samples and may cross the end of the window.
    e:Update(.20); e:Update(.20); T.Tick(e,.15)
    assert(c.hits==1 and c.damage==a.damage and e.state==S.RECOVER)
    T.Near(e.attackTravel,a.travel)
    e:Destroy()

    e,c = approach(distance)
    lock(e)
    c.pos = Vector3(1.25,0,distance)
    T.Tick(e,.12+a.duration)
    assert(e.state==S.RECOVER and c.hits==0 and not e.warning.visible)
    T.Near(e.position.x,0); T.Near(e.position.z,a.travel)
    c.pos = Vector3(0,0,e.position.z+.1)
    T.Tick(e,a.recover-.01)
    assert(e.state==S.RECOVER and c.hits==0)
    e:Destroy()
end

local e,c = approach(2.2)
lock(e); T.Tick(e,.12)
e.obstacles={{x=0,z=1,radius=.30}}
T.Tick(e,.20)
assert(e.state==S.RECOVER and e.attackTravel<.30 and c.hits==0)
e:Reset(); assert(e.particles:CountOwner(e)==0 and not e.warning.visible)
e:Destroy()

for _,interrupt in ipairs({'disable','reset','kill'}) do
    e,c=approach(2.2); lock(e); T.Tick(e,.22)
    assert(e.state==S.ATTACK and c.hits==0)
    if interrupt=='kill' then
        local dies=0
        e.onEvent=function(name) if name=='die' then dies=dies+1 end end
        local reaction=e:ApplyHit({kind='arrow',part='body',dmg=1,dir=Vector3.RIGHT})
        assert(reaction.hit and pose(e,'body').yaw < -14)
        local immediate=pose(e,'leaf_l').roll
        T.Tick(e,.13)
        assert(math.abs(pose(e,'leaf_l').roll-immediate)>5)
        local hit=e:ApplyHit({kind='arrow',part='body',dmg=1000})
        assert(hit.killed and c.deaths==1 and not e.warning.visible)
        assert(not e:ApplyHit({dmg=1000}).hit)
        T.Tick(e,.38)
        assert(dies==1 and pose(e,'core').sx<.1 and pose(e,'body').pitch>5)
        T.Tick(e,.76)
        assert(e.deathFinished and dies==1 and c.deaths==1 and c.hits==0)
        assert(e.particles:CountOwner(e)==0 and pose(e,'body').pitch>78)
        assert(pose(e,'leaf_l').y<-.7 and pose(e,'leaf_r').y<-.7)
    elseif interrupt=='disable' then
        e:SetActive(false); T.Tick(e,.6)
        assert(e.state==S.IDLE and not e.warning.visible and e.particles:CountOwner(e)==0)
        e:SetActive(true); T.Tick(e,.01)
        assert(e.state==S.ALERT and c.hits==0)
    else
        assert(e:Reset() and e.state==S.IDLE and not e.warning.visible and c.hits==0)
        T.Near(e.position.z,0); T.Near(e.attackTravel,0)
    end
    e:Destroy()
end
print('PASS WoodSpirit: headbutt and pounce hit once, locked sidestep, wall stop, recovery, reset, disable, delayed leaf recoil and one death release')

local FX = require('combat.enemies.actors.WoodSpiritFX')
local function chipCount(enemy)
    local count=0
    for _,slot in ipairs(enemy.woodFX.slots) do
        if slot.alive then count=count+1 end
    end
    return count
end

for _,index in ipairs({1,2}) do
    local a=Wood.Config.attacks[index]
    T.Near(a.range,a.travel+a.hitRange+.32)
    local sections=FX.SoilSections(a)
    T.Near(sections[1][1],0); T.Near(sections[#sections][1],a.range)
    for _,section in ipairs(sections) do
        T.Near(section[2],FX.HalfWidth(a,section[1]))
    end
    -- Use the live movement and damage path to probe each side of the drawn border.
    for _,fraction in ipairs({.13,.48,.84}) do
        local z=a.range*fraction
        for _,offset in ipairs({-.055,.055}) do
            e,c=approach(index==1 and 1.23 or 2.25)
            lock(e)
            local x=FX.HalfWidth(a,z)+offset
            T.Tick(e,.12+a.duration,Vector3(x,0,z))
            assert(c.hits==(offset<0 and 1 or 0),'warning boundary diverged at z='..z..' offset='..offset)
            e:Destroy()
        end
    end
end

for _,interrupt in ipairs({'freeze','disable','reset','destroy','death'}) do
    e,c=approach(2.25)
    T.Tick(e,.46-e.stateTime)
    assert(chipCount(e)==4 and e.warning.step==6)
    if interrupt=='freeze' then assert(e:Stagger(1.5,false))
    elseif interrupt=='disable' then e:SetActive(false)
    elseif interrupt=='reset' then e:Reset()
    elseif interrupt=='destroy' then e:Destroy()
    else assert(e:ApplyHit({kind='arrow',part='body',dmg=999}).killed) end
    assert(chipCount(e)==0 and c.hits==0,'chips survived '..interrupt)
    if interrupt~='destroy' then e:Destroy() end
end

e,c=approach(2.25);lock(e)
T.Tick(e,.12+e.attack.finish+.02,Vector3(2,0,2.25))
assert(c.hits==0 and chipCount(e)==5 and pose(e,'root_front_l').sy<.83)
local resins=0
for _,s in ipairs(e.woodFX.slots) do if s.alive and s.palette==6 then resins=resins+1 end end
assert(resins==1,'landing should throw a single resin bead among the bark')
T.Tick(e,.42,Vector3(2,0,2.25)); assert(chipCount(e)==0); e:Destroy()
print('PASS WoodSpirit: 12 measured warning boundary probes, five foreground cleanup paths, root-plant and landing chip budgets')
