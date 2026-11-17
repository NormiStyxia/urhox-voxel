package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock')
local Puzzles=require('ruins.RuinsPuzzles')
local Build=require('ruins.RuinsBuild')
local Terrain=require('ruins.RuinsTerrain')
local subscriptions={}
SubscribeToEvent=function(sender,name,callback)
    subscriptions[sender]=subscriptions[sender] or {}
    assert(not subscriptions[sender][name],'duplicate subscription')
    subscriptions[sender][name]=callback
end
UnsubscribeFromEvent=function(sender,name)
    assert(subscriptions[sender] and subscriptions[sender][name])
    subscriptions[sender][name]=nil
end
local disposed,updates=0,0
local function Populate()
    local object={id='test',Dispose=function()disposed=disposed+1 end,
        Update=function()updates=updates+1 end}
    Puzzles.list[#Puzzles.list+1]=object;Puzzles.objects.test=object
end
-- Keep the real Build/Stop lifecycle and event handlers; skip voxel generation.
for i=1,100 do
    local name=debug.getupvalue(Puzzles.Build,i)
    if not name then break end
    if name=='BuildGateRubble' then debug.setupvalue(Puzzles.Build,i,Populate)
    elseif name:match('^Build') then debug.setupvalue(Puzzles.Build,i,function()end) end
end
local world1,world2={},{}
Puzzles.Build(world1,{})
assert(#Puzzles.list==1)
Puzzles.On(function()error('old callback survived')end)
Puzzles.steps.awake=true;Puzzles.boulder={state='WHOLE'}
Puzzles.Update(.01);assert(updates==1)
Puzzles.Build(world2,{})
assert(disposed==1 and #Puzzles.list==1 and #Puzzles.events==0 and not Puzzles.steps.awake and not Puzzles.boulder)
assert(next(subscriptions[world1])==nil and subscriptions[world2].VoxelDamaged)
Puzzles.Update(.01);assert(updates==2)
local volumeDisposed,nodeDisposed,materialDisposed=0,0,0
world2.RemoveVolume=function()volumeDisposed=volumeDisposed+1 end
Puzzles.gateRubble={GetNode=function()return {Dispose=function()nodeDisposed=nodeDisposed+1 end}end,
    Dispose=function()volumeDisposed=volumeDisposed+1 end}
Puzzles.gateMaterial={Dispose=function()materialDisposed=materialDisposed+1 end}
Puzzles.keyNode={Remove=function()nodeDisposed=nodeDisposed+1 end}
Puzzles.Stop();Puzzles.Stop();Puzzles.Update(.01)
assert(disposed==2 and updates==2 and next(subscriptions[world2])==nil)
assert(volumeDisposed==2 and nodeDisposed==2 and materialDisposed==1)
assert(Puzzles.world==nil and #Puzzles.list==0 and next(Puzzles.objects)==nil)
Build.volumes={1,2};Build.floaters={3};Build.scene={}
Build.Stop();Build.Stop();assert(#Build.volumes==0 and #Build.floaters==0 and not Build.scene)
Terrain.grass={};Terrain.flowers={};Terrain.terrain={};Terrain.heightMap={};Terrain.grassWeight={}
Terrain.Stop();Terrain.Stop()
assert(not Terrain.grass and not Terrain.flowers and not Terrain.terrain and not Terrain.heightMap and not Terrain.grassWeight)
print('PASS scene lifecycle: Build/Build/Stop/Stop in one VM, subscriptions, callbacks, progress, owned volume disposal, cached terrain/scenery references')
