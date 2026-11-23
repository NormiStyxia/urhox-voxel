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

for index, distance in ipairs({1.23,3.85}) do
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

local e,c = approach(3.8)
lock(e); T.Tick(e,.12)
e.obstacles={{x=0,z=1,radius=.30}}
T.Tick(e,.20)
assert(e.state==S.RECOVER and e.attackTravel<.30 and c.hits==0)
e:Reset(); assert(e.particles:CountOwner(e)==0 and not e.warning.visible)
e:Destroy()

for _,interrupt in ipairs({'disable','reset','kill'}) do
    e,c=approach(3.8); lock(e); T.Tick(e,.22)
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
