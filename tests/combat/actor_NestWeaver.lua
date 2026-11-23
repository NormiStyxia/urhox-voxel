package.path='scripts/?.lua;tests/?.lua;'..package.path
local T=require('combat.enemy_support')
local Weaver=require('combat.enemies.actors.NestWeaver')
local S=Weaver.State
local function new()
    local terrain,combat=T.Fixture()
    return Weaver.New(nil,nil,terrain,combat,Vector3.ZERO,'weaver'),combat
end
local function pose(e,id)
    local p={x=0,y=0,z=0,pitch=0,yaw=0,roll=0,sx=1,sy=1,sz=1}
    e.config.posePart(e,id,p)
    return p
end
local function advance(e,state,point)
    for _=1,160 do
        if e.state==state then return end
        e:Update(.01,point)
    end
    error('state not reached: '..state)
end
local near,far=Vector3(0,0,1.20),Vector3(0,0,5)
local flank=Vector3(1.4,0,0)
local e,combat=new()
advance(e,S.TELEGRAPH,near)
assert(e.attack.name=='hook_scissor' and e.warning.kind=='fan')
T.Tick(e,.44,near)
assert(e.directionLocked and pose(e,'leg_front_r').yaw>20 and pose(e,'leg_front_l').yaw< -20)
advance(e,S.ATTACK,near)
T.Tick(e,.07,near); assert(combat.hits==0)
T.Tick(e,.08,near); assert(combat.hits==1 and combat.damage==9 and pose(e,'leg_front_r').yaw< -30)
advance(e,S.RECOVER,near); assert(combat.hits==1)
e:Destroy()

for _,escape in ipairs({flank,Vector3(0,.82,1.2),Vector3(0,0,2.3)}) do
    e,combat=new(); advance(e,S.TELEGRAPH,near); T.Tick(e,.42,near)
    advance(e,S.ATTACK,escape); e:Update(.2,escape); advance(e,S.RECOVER,near)
    assert(combat.hits==0); e:Destroy()
end

e,combat=new(); advance(e,S.TELEGRAPH,far)
assert(e.attack.name=='silk_cast' and e.warning.kind=='line')
T.Tick(e,.76,far)
assert(e.directionLocked and pose(e,'shell_r').roll>30 and pose(e,'shell_l').roll< -30)
assert(pose(e,'nest_r').sx>1.1)
-- The transform of the pooled thread and its swept collision use the same travel.
e.thread.node={}
advance(e,S.ATTACK,far); T.Tick(e,.2,far)
assert(combat.hits==0 and e.thread.node.enabled)
T.Near(e.thread.node.position.z+e.thread.node.scale.z*.5,e.thread.travel)
e:Update(.2,far); assert(combat.hits==1 and combat.damage==12 and not e.thread.node.enabled)
advance(e,S.RECOVER,far); assert(combat.hits==1)
e.thread.node=nil; e:Destroy()

for _,mode in ipairs({'sidestep','jump','wall','deactivate','reset','stagger','death'}) do
    e,combat=new(); advance(e,S.TELEGRAPH,far); T.Tick(e,.76,far)
    local target=mode=='sidestep' and Vector3(.65,0,5) or (mode=='jump' and Vector3(0,.92,5) or far)
    advance(e,S.ATTACK,target); T.Tick(e,.10,target); assert(e.thread.active)
    if mode=='wall' then
        e.world={RaycastSingle=function(_,ray,length)
            local d=3-ray.origin.z
            return {hit=d>=0 and d<=length,distance=d}
        end}
    elseif mode=='deactivate' then e:SetActive(false); assert(not e.thread.active); e:SetActive(true)
    elseif mode=='reset' then assert(e:Reset() and not e.thread.active)
    elseif mode=='stagger' then e:Stagger(.8); assert(not e.thread.active)
    elseif mode=='death' then
        local dies=0
        e.onEvent=function(name) if name=='die' then dies=dies+1 end end
        e:ApplyHit({dmg=1,dir=Vector3.FORWARD})
        assert(pose(e,'fiber_collar').roll~=0)
        -- The shot is still charged open. A hit pinches the two elytra inward.
        local pinched=pose(e,'shell_r').roll
        e.reaction.recoilAge=.3; assert(pose(e,'shell_r').roll>pinched)
        assert(e:ApplyHit({dmg=999}).killed and combat.deaths==1 and not e.thread.active)
        T.Tick(e,.35,target)
        for _,pair in ipairs({'front','middle','rear'}) do
            assert(pose(e,'leg_'..pair..'_r').roll<0 and pose(e,'leg_'..pair..'_l').roll>0)
        end
        assert(pose(e,'shell_r').x>0 and pose(e,'shell_l').x<0 and pose(e,'nest_r').sy<1)
        T.Tick(e,1.0,target)
        assert(dies==1 and combat.deaths==1 and e.deathFinished and e.particles:CountOwner(e)==0)
        assert(not e:Reset())
    end
    T.Tick(e,.62,target)
    assert(combat.hits==0 and not e.thread.active,mode); e:Destroy()
end
print('PASS NestWeaver: scissor and travelling silk, lock/dodge/jump/wall, interrupt/reset, recoil/death')
