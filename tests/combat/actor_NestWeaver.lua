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
    advance(e,S.ATTACK,escape); e:Update(.2,escape); advance(e,S.RECOVER,escape)
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
assert(e.thread.y>2.1 and e.thread.fy<0 and e.thread.z>.60)
T.Near(e.thread.node.position.z+e.thread.fz*e.thread.node.scale.z*.5,e.thread.z+e.thread.travel*e.thread.fz)
T.Near(e.thread.node.position.y+e.thread.fy*e.thread.node.scale.z*.5,e.thread.y+e.thread.travel*e.thread.fy)
e:Update(.2,far); assert(combat.hits==1 and combat.damage==12 and not e.thread.node.enabled)
advance(e,S.RECOVER,far); assert(combat.hits==1)
e.thread.node=nil; e:Destroy()

for _,mode in ipairs({'sidestep','jump','wall','deactivate','reset','stagger','death'}) do
    e,combat=new(); advance(e,S.TELEGRAPH,far); T.Tick(e,.76,far)
    local target=mode=='sidestep' and Vector3(.65,0,5) or (mode=='jump' and Vector3(0,1.4,5) or far)
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
        assert(e.position.y>0 and e.position.y<e.dropHeight)
        T.Tick(e,1.0,target)
        T.Near(e.position.y,e.floorY)
        assert(dies==1 and combat.deaths==1 and e.deathFinished and e.particles:CountOwner(e)==0)
        assert(not e:Reset())
    end
    T.Tick(e,.62,target)
    assert(combat.hits==0 and not e.thread.active,mode); e:Destroy()
end
print('PASS NestWeaver: scissor and travelling silk, lock/dodge/jump/wall, interrupt/reset, recoil/death')

-- The game's actual ballistic pool integrates drag/gravity, tests hurt spheres
-- and embeds the arrow. A low copy of the same trajectory must pass underneath.
dofile('tests/combat/core_support.lua')
local Projectile=require('combat.Projectile')
local Hit=require('combat.Hit')
e,combat=new()
local arrow=Projectile.New{random=function()return .5 end,enemies=function()return {e} end}
local function wingCenter()
    for _,h in ipairs(e:GetHurtShapes()) do if h.id=='wing_r' then return h.center end end
end
local w1=wingCenter(); T.Tick(e,.06,Vector3(0,0,30)); local w2=wingCenter()
assert(math.abs(w1.y-w2.y)>.30 and e:GetHurtShapes()[1].id=='body')
local body=e:GetHurtShapes()[1].center
assert(body.y>1.9)
assert(arrow:Fire(Vector3(0,.28,-3),Vector3.FORWARD,1,{attack=3})); arrow:Update(.17)
assert(e.hp==e.maxHP and not arrow.pool[1].embedded)
assert(#Hit.QueryZone({e},{origin=Vector3(0,0,-1),forward=Vector3.FORWARD,
    radius=2.1,angle=120,low=0,high=.7})==0)
arrow:Clear(); assert(arrow:Fire(Vector3(0,body.y,-3),Vector3.FORWARD,1,{attack=3})); arrow:Update(.17)
assert(arrow.pool[1].attached==e and e.hp<e.maxHP and e.impact.pos.y>1.7)
local previous=e.position
T.Tick(e,.60,Vector3(0,0,9.7)); assert(e.position.y~=previous.y and e.position.z>previous.z)
assert(e:GetHurtShapes()[1].center.y==e.position.y+.54)
arrow:Clear();e:Destroy()
print('PASS real ballistic pool: low arrow and low melee miss; airborne arrow embeds; root and aim sphere fly together')

-- Freeze during the visible aim line, well before there is a launched thread.
e,combat=new(); e.thread.node={}; advance(e,S.TELEGRAPH,far); T.Tick(e,.77,far)
assert(e.thread.node.enabled); e:Stagger(1.2,false)
local frozenWing=pose(e,'wing_r'); T.Tick(e,.75,far)
assert(not e.thread.node.enabled and not e.thread.active and combat.hits==0)
T.Near(frozenWing.roll,pose(e,'wing_r').roll); T.Near(frozenWing.yaw,pose(e,'wing_r').yaw)
e.thread.node=nil; e:Destroy()

-- Verify visibility on the actual CustomGeometry components, including when a
-- status change interrupts gathering or an airborne shot and pooled nodes live on.
local H=require('combat.actor_roles_support')
local Silk=require('combat.enemies.actors.NestWeaverSilk')
for _,batch in ipairs(Silk.batches) do
    for _,quad in ipairs(batch.quads) do for _,v in ipairs(quad) do
        assert(v[1]^2+v[2]^2<=1,'fibres exceed the radial dodge lane')
        if batch.group~='gather' then assert(math.abs(v[3])<=.50001,'fibre exceeds the swept interval') end
    end end
end
local function verifyGroups(mesh,mode)
    for name,g in pairs(mesh.groups) do
        local on=mode=='warn' and (name=='warn' or name=='gather') or mode=='bolt' and (name=='bolt' or name=='shed') or false
        assert(g.enabled==on and #g.meshes>0)
        for _,c in ipairs(g.meshes) do assert(c.enabled==on,name..' mesh visibility') end
    end
end
for _,phase in ipairs({'warn','bolt'}) do
    for _,interrupt in ipairs({'freeze','disable','die','switch'}) do
        local enemy,_,combat=H.newVisual('NestWeaver')
        local mesh,root=enemy.thread.fxMesh,enemy.thread.node
        verifyGroups(mesh,nil)
        advance(enemy,S.TELEGRAPH,far); T.Tick(enemy,.77,far)
        verifyGroups(mesh,'warn')
        if phase=='bolt' then advance(enemy,S.ATTACK,far); T.Tick(enemy,.06,far); verifyGroups(mesh,'bolt') end
        local groups=mesh.groups
        if interrupt=='freeze' then enemy:Stagger(1.4,false)
        elseif interrupt=='disable' then enemy:SetActive(false)
        elseif interrupt=='die' then enemy:ApplyHit({dmg=999})
        else enemy:Destroy() end
        verifyGroups({groups=groups},nil)
        assert(not mesh.visible and not root.enabled and not enemy.thread.active)
        if interrupt=='switch' then assert(root.removed and enemy.thread.node==nil and not next(mesh.groups))
        else T.Tick(enemy,.65,far); assert(combat.hits==0); enemy:Destroy() end
    end
end
print('PASS pooled silk batches: range bounds, aim/flight switch and eight cleanup paths')

-- A non-damaging contact afterimage has its own short lifetime. A missed
-- shot cannot invent a target impact. All interruption routes retire it.
for _,mode in ipairs({'wall','ground','expire','freeze','disable','reset','switch','die'}) do
    local enemy,_,c,w=H.newVisual('NestWeaver')
    advance(enemy,S.TELEGRAPH,far); T.Tick(enemy,.8,far)
    advance(enemy,S.ATTACK,far)
    if mode=='wall' then
        function w:RaycastSingle(ray,length)
            local d=(3-ray.origin.z)/ray.direction.z
            return {hit=d>=0 and d<=length,distance=d}
        end
    end
    local target=(mode=='wall' or mode=='ground') and Vector3(2,0,5) or far
    for _=1,62 do enemy:Update(.01,target); if enemy.thread.endAge then break end end
    local t=enemy.thread
    assert(t.endAge and not t.active and not t.node.enabled and t.endNode.enabled,mode)
    if mode=='wall' or mode=='ground' then assert(c.hits==0) else assert(c.hits==1) end
    T.Near(t.endNode.position.y,t.endY)
    local root=t.endNode
    if mode=='freeze' then enemy:Stagger(1,false)
    elseif mode=='disable' then enemy:SetActive(false)
    elseif mode=='reset' then enemy:Reset()
    elseif mode=='switch' then enemy:Destroy()
    elseif mode=='die' then enemy:ApplyHit({dmg=999})
    else
        T.Tick(enemy,.12,target);assert(root.position.y<=t.endY+.04 and t.fxMesh.groups['end'].age>0)
        T.Tick(enemy,.22,target)
    end
    assert(not t.endAge and not root.enabled,mode)
    if mode~='switch' then enemy:Destroy() end
end
-- The successful branch binds real shader/texture resource names, while a
-- missing texture or rejected binding leaves the approved PBR meshes intact.
local load=cache.GetResource; local make=Material.new
for _,failure in ipairs({'none','missing','throw','shader','bind'}) do
    local requested,bindings=0,0
    cache.GetResource=function(self,kind,path)
        if kind=='Texture2D' and path=='Textures/fx/NestWeaverSilk.png' then
            requested=requested+1
            if failure=='missing' then return nil elseif failure=='throw' then error('missing texture') end
        end
        return load(self,kind,path)
    end
    Material.new=function(...)
        local m=make(...);local shader=m.SetSurfaceShader;local bind=m.SetSurfaceTexture
        m.SetSurfaceShader=function(self,path)
            if path=='Shaders/BLGL/NestWeaverSilk.shader' and failure=='shader' then return false end
            return shader(self,path)
        end
        m.SetSurfaceTexture=function(self,name,tex)
            if name=='fibre_ink' then bindings=bindings+1;if failure=='bind' then return false end end
            return bind(self,name,tex)
        end
        return m
    end
    local enemy=H.newVisual('NestWeaver');local g=enemy.thread.fxMesh.groups
    assert(requested==1)
    if failure=='none' then assert(bindings>0 and #g.gather.inks==3 and #g.bolt.inks==4)
    else assert(#g.gather.inks==0 and #g.gather.meshes==2 and #g.bolt.meshes==3) end
    enemy:Destroy()
end
cache.GetResource,Material.new=load,make
print('PASS impact point, 0.32s fibre tail, cancellation, atlas binding and four resource failure paths')
