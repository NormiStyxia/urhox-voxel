-- The native Windows probe establishes event ordering. These regression doubles
-- exercise scope/identity/error handling, not native deletion or rendering.
package.path='scripts/?.lua;'..package.path
local D=require('ruins.VoxelDamage')
local world,otherWorld={},{}
local target,other={},{}
local function observe(w,v,n)
    D.Observe(w,{GetPtr=function()return v end,GetInt=function()return n end})
end
function world:ApplyDamage(v)
    observe(otherWorld,v,90);observe(self,other,80);observe(self,v,1)
    return 0
end
assert(D.Volume(world,target,{},.05,3)==1,'only synchronous same-world target events count')
observe(world,target,100)
world.ApplyDamage=function()return 0 end
assert(D.Volume(world,target,{},.05,3)==0,'late/unrelated events never carry to another attack')
world.ApplyDamage=function(self,v)observe(self,v,1);return 12 end
assert(D.Volume(world,target,{},.05,3)==1,'event count overrides native count; do not add severed pieces')
world.ApplyDamage=function()return 3 end
assert(D.Volume(world,target,{},.05,3)==3,'documented native return works without event bridge')
function world:ApplyDamageAtWorldPoint()
    observe(self,target,8);observe(self,other,8);observe(otherWorld,target,100)
    return 0
end
assert(D.AtWorldPoint(world,{},.9,3)==16,'area spell counts its own world only')
function world:ApplyDamage(v)
    if v==target then
        observe(self,v,1)
        assert(D.Volume(self,other,{},.05,3)==2)
        observe(self,v,3)
    else observe(self,v,2) end
    return 0
end
assert(D.Volume(world,target,{},.05,3)==4,'nested scopes restore without double counting')
function world:ApplyDamage(v)
    if v==other then error('native test failure') end
    assert(not pcall(D.Volume,self,other,{},.05,3))
    observe(self,v,1);return 0
end
assert(D.Volume(world,target,{},.05,3)==1,'nested exception restores parent')
assert(not pcall(D.Volume,world,other,{},.05,3))
world.ApplyDamage=function()return 0 end
observe(world,target,100)
assert(D.Volume(world,target,{},.05,3)==0,'top-level exception clears scope')
-- A removed native volume may no longer expose methods. Matching identities and
-- reading event scalars must be sufficient, with no grid/count reads afterwards.
setmetatable(target,{__index=function()error('stale volume access')end})
world.ApplyDamage=function(self,v)observe(self,v,1);return 0 end
assert(D.Volume(world,target,{},.05,3)==1)

-- Execute the real gate handler to ensure progress invalidation still runs and
-- the bridge is reached through the existing subscription, not a replacement.
local f=assert(io.open('scripts/ruins/RuinsPuzzles.lua'));local source=f:read('*a');f:close()
local handler=assert(source:match('(local function GateDamaged.-)\nend'))..'\nend\nreturn GateDamaged'
local invalidations=0
local env=setmetatable({VoxelDamage=D,M={world=world},InvalidateGate=function()invalidations=invalidations+1 end},{__index=_G})
local gate=assert(load(handler,'gate damage bridge','t',env))()
world.ApplyDamage=function(_,v)
    gate('VoxelDamaged',{GetPtr=function()return v end,GetInt=function()return 1 end,GetVector3=function()return {} end})
    return 0
end
assert(D.Volume(world,target,{},.05,3)==1 and invalidations==1)
print('PASS voxel result: world/target isolation, nested calls/errors, multi-volume, no stale reads, real gate bridge')
