local S=dofile('tests/combat/core_support.lua')
local H=require('combat.Hit')
local a,b=Vector3(0,0,0),Vector3(10,0,0)
S.near(H.SegmentSphere(a,b,Vector3(5,0,0),1),.4)
S.near(H.SegmentSphere(a,b,Vector3(5,1,0),1),.5)
assert(H.SegmentSphere(a,b,Vector3(-2,0,0),1)==nil)
assert(H.SegmentSphere(a,a,Vector3(2,0,0),1)==nil)
assert(H.SegmentSphere(a,a,a,1)==0)
local result={hit=true,killed=false}
local target={ApplyHit=function(_,info) assert(info.dmg==8); return result end}
local copy=H.Apply(target,{dmg=8,poise=4}); result.hit=false; assert(copy.hit)
assert(not H.Apply(target,{dmg=0/0}).hit)
assert(not H.Apply(target,{dmg=8,poise=-1}).hit)
assert(not H.Apply(target,{dmg=8,armorBreak=0/0}).hit)
target.ApplyHit=function(_,info) assert(info.poise==4 and info.armorBreak==1.25); return {hit=true} end
assert(H.Apply(target,{dmg=8,poise=4,armorBreak=1.25}).hit)
assert(not H.Visible(a,b,function() return .4 end))
-- Exercise actual Nomi GridHit with an intentionally incorrect weapon layer.
local file=assert(io.open('scripts/ruins/NomiController.lua'));local source=file:read('*a');file:close()
local body=assert(source:match('(function N:GridHit.-)\nend'))..'\nend'
local N={};local weapon={collisionLayer=1,distance=1};local wall={collisionLayer=1,distance=5}
local traced=0
local env=setmetatable({N=N,DebugLog={enabled=false},TimeObject={FindByVolume=function() return nil end},
    EmptyOriginHit=function() return false end,VoxelRaycastResult={new=function() return {hit=false} end},
    TraceVolume=function(v,ray,limit) traced=traced+1;assert(v~=weapon);return {hit=true,volume=v,distance=v.distance} end}, {__index=_G})
assert(load(body,'actual Nomi GridHit','t',env))()
local native={hit=true,volume=weapon,distance=1}
local world={RaycastGridSingle=function() return native end,GetVolumeCount=function() return 2 end,
    GetVolume=function(_,i) return i==0 and weapon or wall end}
local n=setmetatable({world=world,aimMask=1,ignoreAimVolume=function(v) return v==weapon end},{__index=N})
assert(n:GridHit({},10).volume==wall and traced==1,'weapon cannot occlude a wall beyond its native hit distance')
native={hit=true,volume=wall,distance=5}
assert(n:GridHit({},10)==native and traced==1,'ordinary native queries retain fast path')
print('PASS analytic start-inside, tangent, degenerate, behind, finite damage, result ownership, wall occlusion')
