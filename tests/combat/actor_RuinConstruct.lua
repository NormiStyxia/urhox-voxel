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

-- Capture the same transforms sent to the two scene nodes at the lock,
-- discharge and stop boundaries. Material changes must not allocate a new ray.
do
    local e,c=encounter(2)
    e.lockMaterial,e.crystalMaterial={},{}
    e.beamNode={LookAt=function(self,point) self.aim=point end,Remove=function() end}
    e.beamMesh={SetMaterial=function(self,m) self.selected=m end}
    T.Tick(e,.60,target)
    local node=e.beamNode
    assert(node.enabled and e.beamMesh.selected==e.lockMaterial and node.scale.x==.055)
    T.Near(node.position.z-node.scale.z*.5,e.beamOrigin.z)
    T.Near(node.scale.z,e.beamLength)
    T.Tick(e,.47,target)
    assert(node.enabled and node.scale.x==.20 and e.beamMesh.selected==e.crystalMaterial)
    T.Tick(e,.22,target)
    assert(not node.enabled and c.hits==1)
    e:Destroy()
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

-- Samples straddle half beam width (.10) plus player radius (.32).
for _,sample in ipairs({{0,0,1},{.40,0,1},{.44,0,0},{2,0,0},{0,1.9,0}}) do
    local e,c=encounter(2)
    T.Tick(e,.56,target)
    assert(e.directionLocked and e.beamOrigin and c.hits==0)
    local lockedX,lockedZ=e.beamOrigin.x,e.beamOrigin.z
    local after=Vector3(sample[1],sample[2],8)
    T.Tick(e,.48,after)
    assert(c.hits==0 and e.beamDir.x==0 and e.beamDir.z==1)
    assert(e.beamOrigin.x==lockedX and e.beamOrigin.z==lockedZ)
    T.Tick(e,.42,after)
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
            e:ApplyHit({kind='arrow',part='core',dmg=1,dir=Vector3.FORWARD})
            assert(pose(e,'core').z<0,'core must recoil immediately')
            e:ApplyHit({kind='arrow',part='core',dmg=1000,dir=Vector3.FORWARD})
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
print('PASS RuinConstruct: projectile, locked beam, dodge, cover, recoil, death and cleanup')
