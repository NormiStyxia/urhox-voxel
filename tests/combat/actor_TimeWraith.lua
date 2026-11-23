local T = dofile('tests/combat/enemy_support.lua')
local Wraith = require('combat.enemies.actors.TimeWraith')
local model = require('combat.enemies.models.TimeWraith').Build()
local S = Wraith.State
local function encounter(skill, range)
    local ground, combat = T.Fixture()
    local e = Wraith.New(nil, nil, ground, combat, Vector3.ZERO, 'wraith_test')
    combat.pos = Vector3(0, 0, range or 1.4)
    e.attackIndex = skill and 1 or 0
    e:Update(.01, combat.pos)
    T.Tick(e, .4, combat.pos)
    e:Update(.01, combat.pos)
    assert(e.state == S.TELEGRAPH and e.warning.visible)
    return e, combat
end
local function pose(e, id)
    local p = {x=0,y=0,z=0,pitch=0,yaw=0,roll=0,sx=1,sy=1,sz=1}
    Wraith.Config.posePart(e,id,p)
    for _, n in pairs(p) do assert(type(n) == 'number' and n == n) end
    return p
end

local recoilEnemy, recoilCombat = encounter(false)
local before = pose(recoilEnemy, 'clock_hand').roll
assert(recoilEnemy:ApplyHit({kind='arrow',part='hood',dmg=1,stop=0}).hit)
T.Near(pose(recoilEnemy, 'clock_hand').roll, before-42)
T.Tick(recoilEnemy, .26, recoilCombat.pos)
assert(recoilEnemy.reaction.recoilAge >= .24)
recoilEnemy:Destroy()

-- Both attacks use the real AI, lock and ground/capsule queries.
for _, evade in ipairs({false, true}) do
    local e, c = encounter(false)
    T.Tick(e, .56, c.pos)
    assert(e.state == S.ATTACK and c.hits == 0)
    if evade then c.pos = Vector3(1.3, 0, -.25) end
    T.Tick(e, .09, c.pos)
    assert(c.hits == 0)
    T.Tick(e, .24, c.pos)
    assert(e.state == S.RECOVER and c.hits == (evade and 0 or 1))
    assert(c.damage == (evade and 0 or 9))
end
for _, evade in ipairs({'none','inside','outside','jump','wall'}) do
    local e, c = encounter(true, 3.4)
    T.Tick(e, .48, c.pos)
    assert(e.state == S.ATTACK and e.arrived and e.warning.visible and e.warning.step == 6)
    T.Near(e.position.x^2 + e.position.z^2, 2.35^2)
    T.Near((c.pos.x-e.position.x)^2 + (c.pos.z-e.position.z)^2, 1.85^2)
    T.Tick(e, .69, c.pos)
    assert(c.hits == 0)
    if evade == 'inside' then c.pos = e.position
    elseif evade == 'outside' then c.pos = Vector3(e.position.x,0,e.position.z+2.3)
    elseif evade == 'jump' then c.pos = Vector3(c.pos.x,.8,c.pos.z)
    elseif evade == 'wall' then e.world = {RaycastSingle=function() return {hit=true,distance=.5} end} end
    e:Update(.02, c.pos)
    assert(e.ringSpent and c.hits == (evade == 'none' and 1 or 0))
    T.Tick(e, .21, Vector3(e.position.x,0,e.position.z+1.85))
    assert(e.state == S.RECOVER and not e.warning.visible and c.damage == (evade == 'none' and 14 or 0))
end

-- Both attempted paths reach a safe prefix before their footprint hits the gap.
local e, c = encounter(true, 2.0)
e.terrain.IsSafeGround = function(x, _, z) return z < 1.2 end
T.Tick(e, .48, c.pos)
assert(e.state == S.RECOVER and not e.warning.visible and c.hits == 0)
T.Near(e.position.x, 0); T.Near(e.position.z, 0)

for _, action in ipairs({'reset','sleep','stagger','shove','kill'}) do
    local e, c = encounter(true, 2.2)
    T.Tick(e,.62,c.pos)
    assert(e.arrived and e.warning.visible and e.particles:CountOwner(e)>0)
    if action == 'reset' then assert(e:Reset() and e.state == S.IDLE)
    elseif action == 'sleep' then e:SetActive(false); e:SetActive(true)
    elseif action == 'stagger' then assert(e:Stagger(.8))
    elseif action == 'shove' then
        local before = pose(e,'clock_hand').roll
        assert(e:ApplyHit({kind='sword',dmg=1,dir=Vector3.RIGHT,stop=0}).hit)
        assert(not e.arrived and pose(e,'clock_hand').roll ~= before)
    else
        local dies=0
        e.onEvent=function(name) if name=='die' then dies=dies+1 end end
        local before = pose(e,'clock_hand').roll
        assert(e:ApplyHit({kind='arrow',part='hood',dmg=999,stop=0}).killed and c.deaths==1)
        assert(not e:ApplyHit({kind='sword',dmg=99}).hit)
        T.Tick(e,.30,c.pos)
        assert(dies==1 and e.deathBurst)
        T.Near(pose(e,'clock_hand').roll,before)
        assert(pose(e,'tail').sy < pose(e,'hourglass').sy and pose(e,'hourglass').sy < pose(e,'hood').sy)
        T.Tick(e,.81,c.pos)
        for _, part in ipairs(model.parts) do assert(pose(e,part.id).sx <= .002) end
        assert(e.deathFinished and dies==1 and c.deaths==1 and e.particles:CountOwner(e)==0)
    end
    assert(not e.arrived and not e.warning.visible and c.hits==0)
    if action=='reset' or action=='sleep' or action=='stagger' then assert(e.particles:CountOwner(e)==0) end
    e:Destroy()
end
print('TimeWraith: swept fan, flank blink, annular hit/miss, safe rollback, interrupts and ordered death passed')
