package.path='scripts/?.lua;tests/?.lua;'..package.path
local T=require('combat.enemy_support')
local Construct=require('combat.enemies.actors.RuinConstruct')
local target=Vector3(0,0,8)

local function encounter(index)
    local terrain,combat=T.Fixture()
    combat.pos=target
    local e=Construct.New(nil,nil,terrain,combat,Vector3.ZERO,'ruin_test')
    e.aggro=true
    e.lastTarget=target
    e:Face(target)
    e.attackIndex=index-1
    e:StartAttack()
    return e,combat
end

local function pose(e,id)
    local p={x=0,y=0,z=0,pitch=0,yaw=0,roll=0,sx=1,sy=1,sz=1}
    e.config.posePart(e,id,p)
    return p
end

for _,dodge in ipairs({false,true}) do
    local e,c=encounter(1)
    T.Tick(e,.68,target)
    assert(e.boltPos and e.boltPos.x>.65 and c.hits==0)
    T.Tick(e,.20,target)
    assert(e.boltPos.z>2 and c.hits==0)
    T.Tick(e,.82,dodge and Vector3(-1.7,0,8) or target)
    assert(c.hits==(dodge and 0 or 1) and c.damage==(dodge and 0 or 9))
    e:Destroy()
end

-- Samples straddle half beam width (.34) plus player radius (.32).
for _,sample in ipairs({{0,0,1},{.64,0,1},{.67,0,0},{2,0,0},{0,1.9,0}}) do
    local e,c=encounter(2)
    T.Tick(e,.56,target)
    assert(e.directionLocked and e.beamOrigin and c.hits==0)
    local lockedX,lockedZ=e.beamOrigin.x,e.beamOrigin.z
    local after=Vector3(sample[1],sample[2],8)
    T.Tick(e,.48,after)
    assert(c.hits==0 and e.beamDir.x==0 and e.beamDir.z==1)
    assert(e.beamOrigin.x==lockedX and e.beamOrigin.z==lockedZ)
    T.Tick(e,.89,after)
    assert(c.hits==sample[3] and c.damage==15*sample[3] and not e.beamOrigin)
    e:Destroy()
end

for attackIndex=1,2 do
    local e,c=encounter(attackIndex)
    e.world={RaycastSingle=function(_,ray,length)
        local distance=(3-ray.origin.z)/ray.direction.z
        if distance>=0 and distance<=length then return {hit=true,distance=distance} end
        return {hit=false}
    end}
    T.Tick(e,1.5,target)
    assert(c.hits==0,'wall must stop bolt and truncate beam')
    e:Destroy()
end

for attackIndex=1,2 do
    for _,action in ipairs({'death','deactivate','reset'}) do
        local e,c=encounter(attackIndex)
        T.Tick(e,attackIndex==1 and .70 or .62,target)
        assert(e.boltPos or e.beamOrigin)
        if action=='death' then
            e:ApplyHit({kind='arrow',part='plate_r',dmg=1,dir=Vector3.FORWARD})
            assert(pose(e,'core').z<0,'core must recoil immediately')
            e:ApplyHit({kind='arrow',part='plate_r',dmg=1000,dir=Vector3.FORWARD})
            local dieEvents=0
            e.onEvent=function(name) if name=='die' then dieEvents=dieEvents+1 end end
            T.Tick(e,.80,target)
            assert(pose(e,'core').sx<.1 and pose(e,'crown').y<-.3 and pose(e,'arm_r').y<-.4)
            T.Tick(e,.45,target)
            assert(c.deaths==1 and dieEvents==1 and e.deathFinished)
        elseif action=='deactivate' then
            e:SetActive(false)
            T.Tick(e,.8,target)
        else
            assert(e:Reset()); T.Tick(e,.2,target)
        end
        assert(c.hits==0 and not e.boltPos and not e.beamOrigin)
        e:Destroy()
    end
end
-- Weapon query, arrow flight, damage resolution and embed use the actual game modules.
dofile('tests/combat/core_support.lua')
local Projectile=require('combat.Projectile')
local Hit=require('combat.Hit')
local function frontShot(e)
    local from=Vector3(.018,1.48,4)
    local line=Hit.Query({e},from,Vector3(.018,1.48,-1),.03)
    assert(line[1], 'reticle missed chest')
    local arrow=Projectile.New({random=function() return .5 end,enemies=function() return {e} end})
    local hp=e.hp
    local ok,p=arrow:Fire(from,Vector3(0,0,-1),1,{attack=5,poise=0})
    assert(ok);arrow:Update(.1)
    assert(p.embedded and p.attached==e and p.part==line[1].shape.id,'reticle and arrow disagree')
    return p.part,(hp-e.hp)/p.damage
end
for _,open in ipairs({false,true}) do
    local e=encounter(2)
    if open then T.Tick(e,2.10,target) end
    local part,factor=frontShot(e)
    assert(open and part=='core' or not open and part:find('plate_',1,true))
    T.Near(factor,open and 2.4 or .35)
    if open then
        T.Tick(e,2.1,target)
        assert(not e:PartEnabled(e.parts.core.spec));assert(pose(e,'plate_r').x==0)
    end
    e:Destroy()
end
for _,t in ipairs({.74,1.39}) do
    local e=encounter(2);T.Tick(e,t,target);assert(e:Stagger(.5,false));T.Tick(e,.51,target)
    assert(not e.venting and not e.beamOrigin and not e:PartEnabled(e.parts.core.spec));e:Destroy()
end
-- A wall touching only the beam's rim still truncates its full cross-section.
do
    local e,c=encounter(2)
    e.world={RaycastSingle=function(_,ray,d)
        local hit=ray.origin.x>.30 and ray.direction.z>.9 and 3-ray.origin.z or nil
        if hit and hit>=0 and hit<=d then return {hit=true,distance=hit} end
        return {hit=false}
    end}
    T.Tick(e,1.38,target);T.Near(e.beamLength+e.beamOrigin.z,3);assert(c.hits==0);e:Destroy()
end
print('PASS RuinConstruct: locked cylinder, edge cover, dodge, real arrow and reticle, armored 0.35x / core 2.40x, vents, interrupts, death and cleanup')
