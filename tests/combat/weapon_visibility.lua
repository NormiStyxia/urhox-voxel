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
        local b={items={},published={},commits=0,SetMaterial=ignore,SetRelative=ignore,SetSorted=ignore}
        function b:Commit()
            self.commits=self.commits+1
            for i,item in pairs(self.items) do self.published[i]=item.enabled end
        end
        function b:SetNumBillboards(count) for i=0,count-1 do self.items[i]={} end end
        function b:GetBillboard(i) return assert(self.items[i]) end
        return b
    end
    return n
end
local VoxelFX=require('dragon.VoxelFX')
VoxelFX.Material=function() return Material:new() end
-- Empty Clear is already optimized in production. Pin its GPU contract here:
-- live -> clear and last-particle expiry must publish hidden state exactly once.
local function mote() return {pos=Vector3.ZERO,life=.1,size=.02,colors={Color(1,1,1)}} end
local pool=VoxelFX.Motes(scene,'clear regression',3,'square',true)
local function CheckFree(p)
    assert(p:Count()==0 and #p.free==p.n)
    local seen={};for _,id in ipairs(p.free)do assert(not seen[id]);seen[id]=true end
end
local base=pool.bb.commits
pool:Clear();pool:Update(.1);assert(pool.bb.commits==base,'empty billboard clear/update submits nothing')
local item=assert(pool:Spawn(mote()));pool:Update(.01)
assert(pool.bb.published[item.idx],'present a live mote before clearing')
base=pool.bb.commits;pool:Clear()
assert(pool.bb.commits==base+1 and not pool.bb.published[item.idx]);CheckFree(pool)
base=pool.bb.commits;pool:Clear();assert(pool.bb.commits==base)
-- Clear before first presentation must also recycle the slot safely.
assert(pool:Spawn(mote()));pool:Clear();CheckFree(pool)
item=assert(pool:Spawn(mote()));pool:Update(.01)
base=pool.bb.commits;pool:Update(1)
assert(pool.bb.commits==base+1 and not pool.bb.published[item.idx]);CheckFree(pool)
base=pool.bb.commits;pool:Clear();pool:Update(.1);assert(pool.bb.commits==base)
for _=1,20 do
    for _=1,pool.n do assert(pool:Spawn(mote())) end
    assert(not pool:Spawn(mote()),'fixed capacity survives repeated reuse')
    pool:Clear();CheckFree(pool)
end
pool.node:Remove()

-- WorldMotes is the actual time-catalyst backend, both immediate and deferred.
-- Adapt only native geometry overloads; particle lifetime/clear/draw stay real.
local parent=Mock.Node('time FX regression')
function parent:CreateChild(name)
    local node=Mock.Node(name,self)
    function node:WorldToLocal(p)return p end
    function node:CreateComponent(kind)
        assert(kind=='CustomGeometry')
        local g=Mock.CustomGeometry(self)
        function g:SetMaterial(mat)self.material=mat end
        function g:BeginGeometry()self.vertices={} end
        return g
    end
    return node
end
getmetatable(Vector3.ZERO).__unm=function(p)return p*-1 end
Vector3.RIGHT=Vector3(1,0,0)
local Fx=require('combat.TimeCatalystFx')
local camera={worldRight=Vector3(1,0,0),worldUp=Vector3.UP}
local fx=Fx.New(parent,camera)
assert(fx.ready and fx.spark.deferDraw and fx.burst.deferDraw)
Fx.SetShown(fx,true)
assert(fx.spark:Spawn(mote()) and fx.burst:Spawn(mote()))
Fx.Draw(fx)
assert(fx.spark.node.enabled and fx.burst.node.enabled)
local draws=0
for _,p in ipairs({fx.spark,fx.burst})do
    local draw=p.Draw
    p.Draw=function(self)draws=draws+1;return draw(self)end
end
Fx.SetShown(fx,false)
assert(draws==2 and not fx.spark.node.enabled and not fx.burst.node.enabled,'time -> weapon immediately hides both world-quad pools')
CheckFree(fx.spark);CheckFree(fx.burst)
Fx.Clear(fx);Fx.SetShown(fx,false)
assert(draws==2,'repeated empty time clear does not draw')
Fx.SetShown(fx,true);assert(fx.spark:Spawn(mote()));Fx.Draw(fx)
assert(fx.spark.node.enabled,'time FX can reappear after clear')
local commits=fx.spark.geometry.commits
fx.spark:Update(1)
assert(not fx.spark.node.enabled and fx.spark.geometry.commits==commits,'deferred final expiry hides without geometry upload')
CheckFree(fx.spark);base=draws;Fx.Clear(fx);assert(draws==base)
Fx.Dispose(fx)
local immediate=VoxelFX.WorldMotes(parent,'immediate expiry',2,'square',true)
assert(immediate:Spawn(mote()));immediate:Update(.01);assert(immediate.node.enabled)
immediate:Update(1);assert(not immediate.node.enabled);CheckFree(immediate)
base=immediate.geometry.commits;immediate:Clear();immediate:Update(.1)
assert(immediate.geometry.commits==base);immediate.node:Remove()
print('PASS real VoxelFX empty/live/expiry/reuse and time-catalyst deferred clear: no empty Commit/Draw, no residual particles')
require('sword_vfx_support').Install()
local State=require('combat.CombatState')
local Store=require('combat.WeaponStore')
Store.Save=function() return true end
local Rig=require('combat.WeaponRig')
local function grantModels(config)
    -- Visibility fixtures test every selectable model independently of economy.
    for class,ids in pairs({sword={'warden','wing'},bow={'silver','thorn'}}) do
        for _,id in ipairs(ids) do config.progress.slots[class].levels[id]=1 end
    end
    return config
end
local world=Mock.World(scene)
local rig=Rig.New(scene,world,Mock.Nomi(scene))
grantModels(rig.config)
assert(rig.pixelSwordFx and rig.swordVfx,'exercise the real sword voxel pool')
State.Configure{rig=rig,explicitSelection=true}
local function tick(n)
    for _=1,n do State.Update(1/60);rig:Update(1/60) end
end
assert(State.Enter('manual'));tick(100)
for _,item in ipairs({{'sword','iron'},{'bow','field'},{'sword','wing'},{'bow','thorn'},{'sword','warden'},{'bow','silver'},{'sword','iron'},{'bow','field'}}) do
    local class,id=table.unpack(item)
    assert(Store.Forge(rig,class,'select',id));tick(100)
    assert(rig.swordVfx.world:Count()==0 and rig.swordVfx.blade:Count()==0)
    local pools={rig.bowChargeFx.motes,rig.bowChargeFx.flakes}
    local commits={}
    for i,p in ipairs(pools)do assert(p:Count()==0);commits[i]=p.bb.commits end
    assert(State.SetWeapon(class))
    for i,p in ipairs(pools)do assert(p.bb.commits==commits[i],'idle weapon switch submits no empty billboard clear')end
    tick(100)
    local e=rig.entries[class];local v=e.authoredVisual or e.wing or e.thorn
    assert(v and v.node and v.node.enabled and v.geometry.commits>0 and v.geometry.material and #v.geometry.vertices>=3,'missing '..id)
    assert(e.pivot.parent==rig.sockets['back_'..class]);assert(State.Activity(true));State.SetBusy(true);tick(60)
    assert(v.node.enabled and e.pivot.parent==rig.sockets[class=='sword' and 'hand_right' or 'hand_left'])
    if class=='bow' then rig:SetBowDraw(.85);tick(4);assert(v.node.enabled and rig.bowArrow.node.enabled);rig:SetBowDraw(0) end
    print('PASS',class,id,#v.geometry.vertices,v.geometry.commits)
    State.SetBusy(false);tick(90);assert(e.pivot.parent==rig.sockets['back_'..class] and v.node.enabled)
    State.Exit('manual');tick(40);assert(not v.node.enabled);State.Enter('manual');tick(40)
end
assert(State.SetWeapon('sword'));tick(40)
assert(Store.Forge(rig,'sword','level','iron'))
local original=rig.config
local entry=rig.entries.sword
local originalVisual=entry.authoredVisual
local oldPose=rig.pose
local saveCalls=0
Store.Save=function(nextConfig)
    saveCalls=saveCalls+1
    assert(rig.config==original and entry.authoredVisual==originalVisual,'save happens before changing the live loadout')
    assert(nextConfig.sword.modelId=='warden' and nextConfig.progress.slots.sword.levels.iron==nil)
    return saveCalls>1
end
assert(not Store.Forge(rig,'sword','smelt','warden','iron'))
assert(saveCalls==1 and rig.config==original and entry.authoredVisual==originalVisual)
assert(Store.Forge(rig,'sword','smelt','warden','iron'))
assert(saveCalls==2 and rig.config.progress.slots.sword.levels.warden==2)
assert(entry.authoredId=='warden' and entry.authoredVisual~=originalVisual,'the new model is bound before Forge returns')
assert(rig.active=='sword' and rig.pose==oldPose and State.GetSelection()=='sword')
Store.Save=function() return true end
State.Stop();rig:Dispose();assert(world.created==world.removed,'volume leak')
print('PASS equipped smelt saves once and rebinds the model immediately, failed save preserves the live model')

-- Cold start from a saved common loadout, so there is no cached legendary body.
local config=grantModels(Store.Default())
Store.Load=function() return config end
local function failureCase()
    local root=Mock.Node('missing optional backend');world=Mock.World(root)
    return Rig.New(root,world,Mock.Nomi(root))
end
package.loaded['dragon.VoxelFX']=nil
package.preload['dragon.VoxelFX']=function() error('injected backend unavailable') end
package.loaded['combat.SwordVfx']=nil
package.preload['combat.SwordVfx']=function() error('injected backend unavailable') end
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
