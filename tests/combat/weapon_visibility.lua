GetPlatform=function() return "Web" end
package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock')
local function read(path)
    local f=assert(io.open('assets/'..path,'rb'),path)
    local bytes=f:read('*a');f:close();return bytes
end
local function checkResource(path)
    assert(#read(path)>0 and #read(path..'.meta')>0,path)
end
local missing
local getResource=cache.GetResource
function cache:GetResource(kind,path,...)
    if kind~='Material' then return getResource(self,kind,path,...) end
    if path==missing then return nil end
    checkResource(path)
    local shader=assert(read(path):match('<surfaceshader name="([^"]+)"'),path)
    checkResource(shader)
    local m=Material:new();m.resourcePath=path
    local clone=m.Clone
    m.Clone=function(self,...) local copy=clone(self,...);copy.resourcePath=path;return copy end
    return m
end
local scene=Mock.Node('scene')
local create=scene.CreateComponent
-- Exercise the production VoxelFX.Motes implementation; double only native rendering calls.
local function ignore() end
local newNode=Mock.Node
Mock.Node=function(...)
    local n=newNode(...)
    function n:CreateComponent(kind)
        if kind~='BillboardSet' then return create(self,kind) end
        local b={items={},SetMaterial=ignore,SetRelative=ignore,SetSorted=ignore,Commit=ignore}
        function b:SetNumBillboards(count) for i=0,count-1 do self.items[i]={} end end
        function b:GetBillboard(i) return assert(self.items[i]) end
        return b
    end
    return n
end
require('dragon.VoxelFX').Material=function() return Material:new() end
local State=require('combat.CombatState')
local Store=require('combat.WeaponStore')
Store.Save=function() return true end
local Rig=require('combat.WeaponRig')
local world=Mock.World(scene)
local rig=Rig.New(scene,world,Mock.Nomi(scene))
assert(rig.pixelSwordFx and rig.shockBurst.pixelMode,'exercise real billboard pool')
State.Configure{rig=rig,explicitSelection=true}
local function tick(n)
    for _=1,n do State.Update(1/60);rig:Update(1/60) end
end
assert(State.Enter('manual'));tick(100)
for _,item in ipairs({{'sword','iron'},{'bow','field'},{'sword','wing'},{'bow','thorn'},{'sword','warden'},{'bow','silver'},{'sword','iron'},{'bow','field'}}) do
    local class,id=table.unpack(item)
    assert(Store.Forge(rig,class,'select',id));assert(State.SetWeapon(class));tick(100)
    local e=rig.entries[class];local v=e.authoredVisual or e.wing or e.thorn
    assert(v and v.node and v.node.enabled and v.geometry.commits>0 and v.geometry.material and #v.geometry.vertices>=3,'missing '..id)
    assert(e.pivot.parent==rig.sockets['back_'..class]);assert(State.Activity(true));State.SetBusy(true);tick(60)
    assert(v.node.enabled and e.pivot.parent==rig.sockets[class=='sword' and 'hand_right' or 'hand_left'])
    if class=='bow' then rig:SetBowDraw(.85);tick(4);assert(v.node.enabled and rig.bowArrow.node.enabled);rig:SetBowDraw(0) end
    print('PASS',class,id,#v.geometry.vertices,v.geometry.commits)
    State.SetBusy(false);tick(90);assert(e.pivot.parent==rig.sockets['back_'..class] and v.node.enabled)
    State.Exit('manual');tick(40);assert(not v.node.enabled);State.Enter('manual');tick(40)
end
State.Stop();rig:Dispose();assert(world.created==world.removed,'volume leak')

-- Cold start from a saved common loadout, so there is no cached legendary body.
local config=assert(Store.Normalize(Store.Default()))
Store.Load=function() return config end
local function failureCase()
    local root=Mock.Node('missing optional backend');world=Mock.World(root)
    return Rig.New(root,world,Mock.Nomi(root))
end
package.loaded['dragon.VoxelFX']=nil
package.preload['dragon.VoxelFX']=function() error('injected backend unavailable') end
rig=failureCase()
assert(not rig.pixelSwordFx and not rig.bowChargeFx)
State.Configure{rig=rig,explicitSelection=true};State.Enter('manual');tick(100)
missing='model/forge-blades/WardenSword.xml'
assert(Store.Forge(rig,'sword','select','warden'));tick(2)
local sword=rig.entries.sword
assert(sword.mesh.volume and sword.mesh.node.enabled and not sword.authoredVisual)
missing=nil
assert(Store.Forge(rig,'sword','select','iron'));tick(100)
assert(not sword.mesh.volume and sword.authoredVisual.node.enabled)
assert(State.SetWeapon('bow'));tick(80)
assert(Store.Forge(rig,'bow','select','silver'));tick(1)
local bow=rig.entries.bow
bow.authoredVisual.geometry.Commit=function() error('injected geometry upload failure') end
tick(100);assert(not bow.authoredVisual and bow.mesh.volume and bow.mesh.node.enabled)
assert(Store.Forge(rig,'bow','select','field'));tick(100)
assert(not bow.mesh.volume and #rig.bowDrawMeshes==0 and bow.authoredVisual.node.enabled)
State.Stop();rig:Dispose();assert(world.created==world.removed)
print('PASS missing pixel backend, missing sword material, failed bow upload, fallback and re-equip; volumes released')
