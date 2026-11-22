-- API-shape/lifetime verification only; this mock cannot validate actual rendering.
package.path='scripts/?.lua;tests/?.lua;'..package.path
local T=require('combat.enemy_support')
local terrain,combat=T.Fixture()
local nodeMethods={}
local nodeBuilds,componentBuilds=0,0
local function node(name)
    nodeBuilds=nodeBuilds+1
    return setmetatable({name=name,position=Vector3.ZERO,scale=Vector3(1,1,1),children={},enabled=true}, {__index=nodeMethods})
end
function nodeMethods:CreateChild(name)
    local child=node(name); self.children[#self.children+1]=child; return child
end
function nodeMethods:SetParent(parent) self.parent=parent end
function nodeMethods:SetScale(scale) assert(not self.removed); self.scale=scale end
function nodeMethods:Remove() assert(not self.removed,'double remove'); self.removed=true end
local noop=function() end
local geometryBuilds,materialBuilds=0,0
function nodeMethods:CreateComponent(kind)
    componentBuilds=componentBuilds+1
    assert(kind=='CustomGeometry','enemy must not create any physics components')
    local component={BeginGeometry=noop,DefineVertex=noop,DefineNormal=noop,
        Commit=function() geometryBuilds=geometryBuilds+1 end,
        SetMaterial=function(self,mat) self.material=mat end}
    self.component=component
    return component
end
Color=function(r,g,b,a) return {r=r,g=g,b=b,a=a or 1} end
Variant=function(value) return value end
Quaternion=function(angle,axis) return {angle=angle or 0,axis=axis} end
local surface={GetName=function() return 'Shaders/BLGL/EnemyVoxelHit.shader' end}
local function material()
    materialBuilds=materialBuilds+1
    return {SetTechnique=noop,SetCullMode=noop,
        SetShaderParameter=function(self,key,value) self[key]=value end,
        GetShaderParameter=function() return {IsEmpty=function() return false end,GetVector4=function() return {x=1,y=1,z=1,w=1} end} end,
        Clone=function() return material() end}
end
local originalMaterial=material
material=function()
    local m=originalMaterial()
    m.GetSurfaceShader=function() return surface end -- Resource, NOT a path string (.emmylua)
    m.GetName=function() return 'mock_palette_material' end
    m.SetSurfaceTexture=function(self,name,texture)
        assert(name=='palette_tex' and type(texture)=='table')
        self.paletteTexture=texture; return true
    end
    return m
end
Material={new=material}
local template=material()
local templateAvailable=true
cache={GetResource=function(_,kind,path)
    if kind=='Material' and path=='Shaders/BLGL/EnemyVoxelHit.xml' then return templateAvailable and template or nil end
    return {}
end}
TRIANGLE_LIST=0; CULL_NONE=0
local scene=node('scene')
VariantMap=function() return {} end
local cues=0
function scene:SendEvent(name,data)
    assert(name=='EnemyAttackCue' and data.EnemyId=='visual')
    assert(type(data.Event)=='string' and data.Enemy~='')
    cues=cues+1
end
local world={volumes={},removed=0,rayBlocked=false,rebuilds=0}
local palette={}
function world:GetPaletteTexture(domain) assert(domain==0); return palette end
function world:SetPaletteEntry(index,...) assert(index>=200 and index<=239) end
function world:SetPaletteEntryPBR(index,...) assert(index>=200 and index<=239) end
function world:FinalizeVolume() error('enemy must not enter physics world') end
function world:FinalizeVolumeAsDynamic() error('enemy must not enter physics world') end
function world:CreateVolume(nx,ny,nz,size,position,rotation)
    local n=node('voxel')
    local grid={SetSolid=noop,SetVoxelMaterial=noop,FillBox=noop,PaintBox=noop}
    local volume={GetGrid=function() return grid end,GetNode=function() return n end,
        RebuildGeometry=function() self.rebuilds=self.rebuilds+1 end,
        GetMaterial=function(vol) return vol.material or template end,
        GetPaletteDomain=function() return 0 end,GetPaletteBank=function() return 0 end,
        SetMaterial=function(vol,mat) vol.material=mat end}
    self.volumes[#self.volumes+1]=volume; return volume
end
function world:RemoveVolume(volume)
    assert(not volume.removed,'double volume remove')
    assert(volume.destructible==false and volume.evictable==false and volume.collisionLayer==0 and volume.collisionMask==0)
    volume.removed=true; self.removed=self.removed+1
end
function world:RaycastSingle(ray,length) return {hit=self.rayBlocked,distance=.3} end
local Beetle=require('combat.enemies.MossBeetle')
local Sentry=require('combat.enemies.StoneSentry')
local Beast=require('combat.enemies.StoneBeast')
for _,class in ipairs({Beetle,Sentry,Beast}) do
    world.materialAvailable=class~=Beetle
    templateAvailable=world.materialAvailable
    local enemy=class.New(scene,world,terrain,combat,Vector3.ZERO,'visual')
    local rebuilds=world.rebuilds
    local geometries,materials=geometryBuilds,materialBuilds
    assert(enemy.visual.flashSupported==world.materialAvailable)
    enemy:Update(.016,Vector3(0,0,3))
    assert(enemy.node~=nil)
    enemy:SelectAttack(); enemy:SetState('TELEGRAPH'); enemy:Update(.1,Vector3(0,0,3))
    assert(enemy.visual.warnings[enemy.attack.warning].enabled)
    if class==Beast then
        enemy:ApplyHit({dmg=301,part='head'}); T.Tick(enemy,.13,Vector3(0,0,3))
        assert(enemy.visual.bones.head.rotation.angle>0 and not enemy.visual.phaseRing.enabled,'brace before head lift')
        T.Tick(enemy,.33,Vector3(0,0,3))
        assert(enemy.visual.bones.head.rotation.angle<0,'roar head lift')
        assert(enemy.visual.phaseRing.enabled and not enemy.visual.bones.core.enabled)
        assert(enemy.visual.hitGroups['back_armor:0:0'].material.rage_glow==1)
        enemy:ApplyHit({dmg=70,part='back_armor',kind='arrow'}); T.Tick(enemy,.1,Vector3(0,0,3))
        assert(enemy.visual.bones.core.enabled)
    end
    enemy:Reset(); enemy:SetActive(true)
    for _,group in pairs(enemy.visual.hitGroups) do assert(not group.rage) end
    local part=class==Beetle and 'shell' or (class==Beast and 'foreleg_l' or 'body')
    local original=Vector3(enemy.position.x,enemy.position.y,enemy.position.z)
    enemy:ApplyHit({dmg=.1,part=part,kind='arrow',dir=Vector3(1,0,0)})
    if class==Beast then T.Near(enemy.position.x,original.x) end
    for _,p in ipairs(enemy.visual.pieces) do
        if p.name==part then
            assert(p.node.position.x>p.rest.x,'local impact must move struck piece, not root')
            if world.materialAvailable then assert(p.lit and p.material.hit_flash==.85 and p.material.paletteTexture==palette) end
        end
    end
    T.Tick(enemy,.17,Vector3(0,0,3)) -- .04 stop + complete .12 recoil
    for _,p in ipairs(enemy.visual.pieces) do if p.name==part then
        T.Near(p.node.position.x,p.rest.x); assert(not p.lit)
    end end
    if class==Beast then
        enemy:Stagger(3,true); T.Tick(enemy,.4,Vector3(0,0,3))
        assert(enemy.visual.body.scale.y==1 and enemy.poseRoll>65)
        local ring=enemy.visual.phaseRing.component.material.MatDiffColor
        assert(ring.r<.5 and ring.g>.3 and ring.b>.2,'phase ring must be low-bright gold-grey, not warning red')
    end
    world.rayBlocked=true; assert(not enemy:Move(1,0) and enemy.blockReason=='wall'); world.rayBlocked=false
    enemy:ApplyHit({dmg=10000,part='head'})
    if not enemy.dead then enemy:ApplyHit({dmg=10000}) end
    assert(enemy.dead and enemy.visual.body.enabled)
    T.Tick(enemy,.11,Vector3(0,0,3)); assert(enemy.visual.body.enabled)
    T.Tick(enemy,.25,Vector3(0,0,3)); assert(not enemy.visual.body.enabled)
    T.Tick(enemy,1.5,Vector3(0,0,3))
    assert(enemy.node==nil and enemy.visual.removed)
    assert(world.rebuilds==rebuilds and geometryBuilds==geometries,'combat/death/particle reuse must never rebuild geometry')
    assert(materialBuilds==materials,'hits/phase/death must not allocate any material')
    enemy:SetActive(false); enemy:Reset(); enemy:Destroy(); enemy:Destroy()
end
-- Prebuilt independent instance/part materials: 100 impacts add no engine objects.
templateAvailable=true
local a=Beast.New(scene,world,terrain,combat,Vector3.ZERO,'visual')
local b=Beast.New(scene,world,terrain,combat,Vector3(2,0,0),'visual')
local beforeN,beforeC,beforeM,beforeG=nodeBuilds,componentBuilds,materialBuilds,geometryBuilds
assert(a.visual.hitMaterialCount==6 and b.visual.hitMaterialCount==6)
local ga=a.visual.hitGroups['foreleg_l:0:0']
local gb=b.visual.hitGroups['foreleg_l:0:0']
assert(ga.material~=gb.material and ga.material~=template)
for i=1,100 do
    a:ApplyHit({dmg=.01,part='foreleg_l',heavy=i%2==0,kind='arrow',dir=Vector3(1,0,0)})
    assert(ga.material.hit_flash==(i%2==0 and 1 or .85))
    assert(gb.material.hit_flash==0 and a.visual.hitGroups['foreleg_r:0:0'].material.hit_flash==0)
    local held=a.hitStop
    T.Tick(a,held+.13,Vector3(0,0,3))
    assert(ga.material.hit_flash==0 and a.reaction.recoilAge>=.12)
end
assert(nodeBuilds==beforeN and componentBuilds==beforeC and materialBuilds==beforeM and geometryBuilds==beforeG)
a:ApplyHit({dmg=.01,part='head'}); a:SetActive(false)
assert(a.visual.hitGroups['head:0:0'].material.hit_flash==0)
a:SetActive(true); a:ApplyHit({dmg=.01,part='head'}); a:Reset()
assert(a.visual.hitGroups['head:0:0'].material.hit_flash==0)
a:Destroy(); b:Destroy()
assert(world.removed==#world.volumes,'all actor/projectile volumes must be released')
assert(cues>=6,'native cue events must be dispatched for telegraph and cancellation')
print('PASS visual API mock: no physics/finalize, warnings/phase effects, wall stopping, complete idempotent cleanup')
