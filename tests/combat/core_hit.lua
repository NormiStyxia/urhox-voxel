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
assert(copy.resolved and H.Apply(target,{dmg=0/0}).resolved==false and H.Apply(target,{dmg=8}).resolved==false)
assert(not H.Apply(target,{dmg=0/0}).hit)
assert(not H.Apply(target,{dmg=8,poise=-1}).hit)
assert(not H.Apply(target,{dmg=8,armorBreak=0/0}).hit)
target.ApplyHit=function(_,info) assert(info.poise==4 and info.armorBreak==1.25); return {hit=true} end
assert(H.Apply(target,{dmg=8,poise=4,armorBreak=1.25}).hit)
assert(not H.Visible(a,b,function() return .4 end))
-- Exercise actual Nomi GridHit with an intentionally incorrect weapon layer.
local file=assert(io.open('scripts/ruins/NomiController.lua'));local source=file:read('*a');file:close()
local broadphase=assert(source:match('(local function MayIntersect.-)\nend'))..'\nend'
local body=assert(source:match('(function N:GridHit.-)\nend'))..'\nend'
local N={}
local rotation=setmetatable({}, {__mul=function(_,v)return v end})
local function volume(distance)
    local node={worldPosition=Vector3(0,0,distance),worldScale=Vector3(1,1,1),worldRotation=rotation,
        IsEnabled=function()return true end}
    local grid={GetDimensions=function()return {x=1,y=1,z=1}end}
    return {collisionLayer=1,distance=distance,voxelSize=1,GetNode=function()return node end,
        GetGrid=function()return grid end,IsEnabledEffective=function()return true end}
end
local weapon,wall=volume(1),volume(5)
local traced,nativeCalls=0,0
local env=setmetatable({N=N,Perf=require('combat.SwingPerf'),aimBounds=setmetatable({}, {__mode='k'}),
    VoxelRaycastResult={new=function() return {hit=false} end},
    TraceVolume=function(v,ray,limit)
        traced=traced+1;assert(v~=weapon and limit>=v.distance)
        return {hit=true,volume=v,distance=v.distance}
    end}, {__index=_G})
-- Use the production candidate filter too: no stub pretending every ray intersects.
assert(load(broadphase..'\n'..body,'actual Nomi candidate filter + GridHit','t',env))()
local native={hit=true,volume=weapon,distance=1}
local world={RaycastGridSingle=function()nativeCalls=nativeCalls+1;return native end,GetVolumeCount=function() return 2 end,
    GetVolume=function(_,i) return i==0 and weapon or wall end}
local n=setmetatable({world=world,aimMask=1,ignoreAimVolume=function(v) return v==weapon end},{__index=N})
local ray={origin=Vector3.ZERO,direction=Vector3.FORWARD}
assert(n:GridHit(ray,10).volume==wall and traced==1,'ignored foreground cannot truncate the real wall')
native={hit=true,volume=wall,distance=.01}
local actual=n:GridHit(ray,10)
assert(actual.volume==wall and actual.distance==5 and actual~=native and traced==2,'each uncached query traverses real Grid regardless of native distance')
assert(nativeCalls==0,'native first hit is no longer a fast path or a clipping boundary')
assert(not n:GridHit({origin=Vector3(20,0,0),direction=Vector3.FORWARD},10).hit and traced==2,'actual bounding sphere rejects a disjoint ray before tracing')
print('PASS analytic start-inside, tangent, degenerate, behind, finite damage, result ownership, wall occlusion')
