local F=dofile('tests/combat/perf_support.lua')
local S,P=F.S,F.P
local N,trace=F.LoadNomi()
local rotation={Inverse=function(self)return self end}
setmetatable(rotation,{__mul=function(_,v)return v end})
local function volume(x,solid,dims)
 local node={worldRotation=rotation,worldScale=Vector3(1,1,1),WorldToLocal=function(_,p)return p-Vector3(x,0,0)end}
 local grid={GetDimensions=function()return dims or {x=4,y=4,z=4}end,
  IsSolid=function(_,a,b,c)assert(math.type(a)=='integer' and math.type(b)=='integer' and math.type(c)=='integer');return solid(a,b,c)end,
  GetVoxelMaterial=function()return 1 end}
 return {collisionLayer=1,voxelSize=1,volumeId=x,GetNode=function()return node end,GetGrid=function()return grid end,GetPaletteDomain=function()return 0 end}
end
local v=volume(0,function(x)return x==0 end)
local hit=trace(v,{origin=Vector3(4,1.5,1.5),direction=Vector3(-1,0,0)},10)
assert(hit and hit.hit);S.near(hit.distance,3);assert(hit.voxel.x==0)
local before=P.cells
assert(trace(v,{origin=Vector3(5,10,5),direction=Vector3(1,0,0)},10)==nil and P.cells==before,'bounds rejection enters no DDA cells')
local empty=volume(0,function()return false end,{x=10000,y=4,z=4})
P.BeginFrame();local _,exhausted=trace(empty,{origin=Vector3(0,1.5,1.5),direction=Vector3.RIGHT},10000,4096)
assert(exhausted and P.cells==4096,'optional DDA budget exact')
local native={hit=false}
local count=0
local world={RaycastGridSingle=function(_,ray,distance,mask)
 assert(type(ray.origin)=='table' and type(ray.direction)=='table' and type(distance)=='number' and math.type(mask)=='integer')
 count=count+1;return native
end,GetVolumeCount=function()return 1 end,GetVolume=function(_,i)assert(i==0);return v end}
local n=setmetatable({world=world,aimMask=1},{__index=N})
local ray={origin=Vector3(4,1.5,1.5),direction=Vector3(-1,0,0)}
P.BeginFrame();n:BeginQueryScope()
local a=n:GridHit(ray,10);assert(n:GridHit(ray,10)==a and count==1)
n:GridHit(ray,9);assert(count==2)
n.aimMask=3;n:GridHit(ray,10);assert(count==3)
P.Invalidate();n:GridHit(ray,10);assert(count==4)
n:EndQueryScope();n:GridHit(ray,10);n:GridHit(ray,10);assert(count==6,'uncached by default')
-- Ignored foreground native result repaired; query cache never survives scope end.
n.aimMask=1
local ignored={}
n.ignoreAimVolume=function(vol)return vol==ignored end
native={hit=true,distance=1,volume=ignored}
P.BeginFrame();n:BeginQueryScope();local repaired=n:GridHit(ray,10)
assert(repaired.volume==v and repaired.distance==3 and P.fallbackReason=='ignored')
assert(n:GridHit(ray,10)==repaired and P.fallbacks==1)
n:EndQueryScope()
P.fallbacks=4
local hidden=n:GridHit(ray,10,true);assert(hidden.hit and hidden.distance==0 and P.gridBudgetExceeded==1)
local exact=n:GridHit(ray,10);assert(exact.volume==v and exact.distance==3,'gameplay cannot be dropped by HUD budget')
P.BeginFrame();n.ignoreAimVolume=nil
native={hit=true,distance=0,volume=empty}
local repairedEmpty=n:GridHit(ray,10);assert(repairedEmpty.volume==v and P.fallbackReason=='emptyOrigin')
print('PASS Grid slab rejection, negative-boundary DDA, exact ray/mask/distance/scope invalidation, 4096-cell optional cap, gameplay fallback preserved')

local _,oldTrace=F.LoadNomi('validation/combat/sword-hitch/before/NomiController.lua.txt')
local miss={origin=Vector3(5,10,5),direction=Vector3.RIGHT}
F.results=0;for _=1,100 do oldTrace(v,miss,10) end;local beforeResults=F.results
F.results=0;for _=1,100 do trace(v,miss,10) end
assert(beforeResults==100 and F.results==0)
print('R10 Grid 100 disjoint bounds: VoxelRaycastResult allocations 100 -> 0; DDA cells 0 -> 0')
