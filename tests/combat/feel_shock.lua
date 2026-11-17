-- Plunge / finisher shockwave: continuous ring + wall + petals, no bars, no allocation of nodes.
package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock');local Shock=require('combat.ShockBurst')
local scene=Mock.Node('scene');local b=Shock.New(scene);local children=#scene.children
b:Emit(Vector3(0,0,0),Vector3(0,0,1),true);b:Update(1/60)
assert(b.node.enabled and #b.geometry.vertices>0,'burst draws on the first frame')
local maxR,maxY,bright=0,0,0
for _,v in ipairs(b.geometry.vertices) do
    local p=v.position;maxR=math.max(maxR,math.sqrt(p.x*p.x+p.z*p.z));maxY=math.max(maxY,p.y);bright=math.max(bright,v.color.a)
end
assert(maxY>1 and bright>1,'tall bright core on landing')
for _=1,20 do b.geometry.vertices={};b:Update(1/60) end
local r2=0;for _,v in ipairs(b.geometry.vertices) do local p=v.position;r2=math.max(r2,math.sqrt(p.x*p.x+p.z*p.z)) end
assert(r2>2.5,'ring expands outward: '..r2)
-- Finisher lands ahead of the player.
b:Clear();b:Emit(Vector3(0,0,0),Vector3(1,0,0),false);b:Update(1/60)
local cx=0;local n=0;for _,v in ipairs(b.geometry.vertices) do cx=cx+v.position.x;n=n+1 end
assert(cx/n>.3,'finisher burst centred in front')
for _=1,60 do b:Update(1/60) end;assert(not b.node.enabled,'burst ends')
for i=1,10 do b:Emit(Vector3(i,0,0),Vector3(0,0,1),true) end
assert(#scene.children==children,'fixed pool, no nodes after New')
b:Dispose()
print('PASS shock burst: expanding ring/wall/petals, finisher offset, fade-out, fixed pool')
