-- API-shape/lifetime verification only; this mock cannot validate actual rendering.
package.path='scripts/?.lua;tests/?.lua;'..package.path
local T=require('combat.enemy_support')
local terrain,combat=T.Fixture()
local nodeMethods={}
local function node(name)
    return setmetatable({name=name,position=Vector3.ZERO,scale=Vector3(1,1,1),children={},enabled=true}, {__index=nodeMethods})
end
function nodeMethods:CreateChild(name)
    local child=node(name); self.children[#self.children+1]=child; return child
end
function nodeMethods:SetParent(parent) self.parent=parent end
function nodeMethods:SetScale(scale) assert(not self.removed); self.scale=scale end
function nodeMethods:Remove() assert(not self.removed,'double remove'); self.removed=true end
local noop=function() end
function nodeMethods:CreateComponent(kind)
    assert(kind=='CustomGeometry','enemy must not create any physics components')
    return {BeginGeometry=noop,DefineVertex=noop,DefineNormal=noop,Commit=noop,SetMaterial=noop}
end
Color=function(r,g,b,a) return {r=r,g=g,b=b,a=a or 1} end
Variant=function(value) return value end
Material={new=function() return {SetTechnique=noop,SetShaderParameter=noop,SetCullMode=noop} end}
cache={GetResource=function() return {} end}
TRIANGLE_LIST=0; CULL_NONE=0
local scene=node('scene')
VariantMap=function() return {} end
local cues=0
function scene:SendEvent(name,data)
    assert(name=='EnemyAttackCue' and data.EnemyId=='visual')
    assert(data.Phase=='inhale' or data.Phase=='whoosh' or data.Phase=='stop')
    cues=cues+1
end
local world={volumes={},removed=0,rayBlocked=false,rebuilds=0}
function world:SetPaletteEntry(index,...) assert(index>=200 and index<=239) end
function world:SetPaletteEntryPBR(index,...) assert(index>=200 and index<=239) end
function world:FinalizeVolume() error('enemy must not enter physics world') end
function world:FinalizeVolumeAsDynamic() error('enemy must not enter physics world') end
function world:CreateVolume(nx,ny,nz,size,position,rotation)
    local n=node('voxel')
    local grid={SetSolid=noop,SetVoxelMaterial=noop,FillBox=noop,PaintBox=noop}
    local volume={GetGrid=function() return grid end,GetNode=function() return n end,
        RebuildGeometry=function() self.rebuilds=self.rebuilds+1 end}
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
    local enemy=class.New(scene,world,terrain,combat,Vector3.ZERO,'visual')
    local rebuilds=world.rebuilds
    enemy:Update(.016,Vector3(0,0,3))
    assert(enemy.node~=nil)
    enemy:SelectAttack(); enemy:SetState('TELEGRAPH'); enemy:Update(.1,Vector3(0,0,3))
    assert(enemy.visual.warnings[enemy.attack.warning].enabled)
    if class==Beast then
        enemy:ApplyHit({dmg=301,part='head'}); T.Tick(enemy,.1,Vector3(0,0,3))
        assert(enemy.visual.phaseRing.enabled and not enemy.visual.bones.core.enabled)
        enemy:ApplyHit({dmg=70,part='back_armor'}); T.Tick(enemy,.1,Vector3(0,0,3))
        assert(enemy.visual.bones.core.enabled)
    end
    world.rayBlocked=true; assert(not enemy:Move(1,0) and enemy.blockReason=='wall'); world.rayBlocked=false
    enemy:ApplyHit({dmg=10000,part='head'})
    if not enemy.dead then enemy:ApplyHit({dmg=10000}) end
    assert(enemy.dead)
    T.Tick(enemy,1.5,Vector3(0,0,3))
    assert(enemy.node==nil and enemy.visual.removed)
    assert(world.rebuilds==rebuilds,'combat/death/particle reuse must never rebuild geometry')
    enemy:SetActive(false); enemy:Reset(); enemy:Destroy(); enemy:Destroy()
end
assert(world.removed==#world.volumes,'all actor/projectile volumes must be released')
assert(cues>=6,'native cue events must be dispatched for telegraph and cancellation')
print('PASS visual API mock: no physics/finalize, warnings/phase effects, wall stopping, complete idempotent cleanup')
