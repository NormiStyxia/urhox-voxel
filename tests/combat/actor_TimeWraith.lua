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
    assert(e.state == S.TELEGRAPH and (e.warning.visible or e.fieldStage == 'warn'))
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
local field=require('combat.enemies.actors.TimeWraithField')
local function at(e,x,y,z) return e:GetPlayerTimeScale(Vector3(x,y,z)) end
local e,c=encounter(true,2.2)
assert(at(e,0,0,0)==1 and e.fieldStage=='warn')
T.Tick(e,field.warning,c.pos)
assert(e.fieldStage=='active' and at(e,0,0,0)==.5 and at(e,2.8,1.6,0)==.5)
assert(at(e,0,-.18,2.8)==.5 and at(e,0,-.181,0)==1 and at(e,0,1.601,0)==1)
for i=1,3 do assert(at(e,2.81,0,0)==1 and at(e,2.79,0,0)==.5) end
assert(at(e,2,0,2)==1 and e:GetPlayerTimeScale(nil)==1)
e.position=Vector3(.6,0,0)
assert(at(e,-2.79,0,0)==.5 and at(e,3,0,0)==1)
T.Tick(e,3.59,c.pos)
assert(at(e,0,0,0)==.5 and c.damage==0)
T.Tick(e,.01,c.pos)
assert(at(e,0,0,0)==1 and e.fieldStage=='release')
T.Tick(e,.48,c.pos)
assert(not e.fieldStage and c.damage==0)

for _, age in ipairs({.3,1.1,4.55}) do
    for _, action in ipairs({'reset','freeze','disable','destroy','kill'}) do
        local e,c=encounter(true)
        T.Tick(e,age,c.pos)
        assert(e.fieldStage)
        if action=='reset' then assert(e:Reset())
        elseif action=='freeze' then assert(e:Stagger(.8,false)) -- SpellHit(control) path
        elseif action=='disable' then e:SetActive(false); e:SetActive(true)
        elseif action=='destroy' then e:Destroy()
        else
            local before=pose(e,'clock_hand').roll
            local dies=0
            e.onEvent=function(name) if name=='die' then dies=dies+1 end end
            assert(e:ApplyHit({kind='arrow',part='hood',dmg=999,stop=0}).killed and c.deaths==1)
            T.Near(pose(e,'clock_hand').roll,before)
            T.Tick(e,.30,c.pos)
            assert(pose(e,'tail').sy < pose(e,'hourglass').sy and pose(e,'hourglass').sy < pose(e,'hood').sy)
            T.Tick(e,.81,c.pos)
            for _,part in ipairs(model.parts) do assert(pose(e,part.id).sx<=.002) end
            assert(e.deathFinished and dies==1 and c.deaths==1 and e.particles:CountOwner(e)==0)
        end
        assert(not e.fieldStage and at(e,0,0,0)==1 and c.damage==0)
    end
end
local hitch,combat=encounter(true)
T.Tick(hitch,field.warning,combat.pos)
hitch.hitStop=8
hitch:Update(5,combat.pos)
assert(at(hitch,0,0,0)==1 and not hitch.fieldStage and combat.hits==0)
print('TimeWraith: sweep, cast warning, cylinder boundaries, exit/re-entry, expiry, 15 interrupts and ordered death passed')

-- Measure the transforms sent to the prebuilt FX nodes. This check is separate
-- from the software-projected four-frame sample and needs no graphics context.
Quaternion=function(angle) return angle end
Variant=function(v) return v end
Color=function(r,g,b,a) return {r,g,b,a} end
local fx={root={}}
for _,name in ipairs({'floor','rim','ticks','hand','dust','gold'}) do
    fx[name]={node={},mat={SetShaderParameter=function() end},color={1,1,1}}
end
local p=Vector3(7,2,-8)
field.Draw(fx,p,'warn',.25); local warnAngle=fx.dust.node.rotation
field.Draw(fx,p,'warn',.50); local warnRate=(fx.dust.node.rotation-warnAngle)/.25
field.Draw(fx,p,'active',.25); local activeAngle=fx.dust.node.rotation
field.Draw(fx,p,'active',.50); local activeRate=(fx.dust.node.rotation-activeAngle)/.25
T.Near(warnRate,120); T.Near(activeRate,9)
assert(fx.root.position==p and fx.root.enabled)
local full=fx.rim.step
field.Draw(fx,p,'release',.32); assert(fx.rim.step<full and fx.rim.step>0)
field.Draw(fx,nil,nil,0); assert(not fx.root.enabled)
print('TimeWraith FX: rim, sand and fade transforms passed (120 -> 9 deg/s)')
