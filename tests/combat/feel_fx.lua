package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock');local Fx=require('combat.CombatFx')
local scene=Mock.Node('scene');local world=Mock.World(scene)
local fx=Fx.New(scene,world)
assert(#fx.land==30 and #fx.arcs==24 and #fx.ribbons==3)
local children=#scene.children;local pos=Vector3(0,0,0);local forward=Vector3(0,0,1)
fx:Impact(pos,forward,true)
local active=0;for _,s in ipairs(fx.land)do if s.active then active=active+1 end end
assert(active==30 and active<=40)
fx:Update(.14);assert(fx.land[1].scale.x>2.1 and fx.land[1].scale.x<2.4)
for i=16,21 do assert(fx.land[i].scale.z<=.420001 and fx.land[i].color==5)end
for i=2,15 do assert(fx.land[i].ttl>=.5 and fx.land[i].ttl<=.7)end
fx:Impact(pos,forward,true)
fx:Update(1/30);assert(fx.land[30].color==1)
fx:Update(1/30);assert(fx.land[30].color==1)
fx:Update(1/30);assert(fx.land[30].color==2,'30 Hz also presents two white flash frames')
fx:Begin(4,false)
local root,tip=Vector3(.4,1,0),Vector3(1.4,1,0)
local slots={};for i,s in ipairs(fx.arcs)do slots[i]=s end
local nativeVector=Vector3;local created=0
rawset(_G,'Vector3',setmetatable({},{__call=function(_,...)created=created+1;return nativeVector(...)end}))
for i=0,24 do
 local a=i*math.pi/12;tip.x,tip.z=root.x+math.cos(a),root.z+math.sin(a)
 fx:Blade(root,tip);fx:Update(.005)
end
assert(created==0,'effect sampling/update creates no vectors')
rawset(_G,'Vector3',nativeVector)
active=0;for i,s in ipairs(fx.arcs)do assert(s==slots[i]);if s.active then active=active+1 end end
assert(active>=20 and active<=24 and #scene.children==children,'full circle has bounded visible coverage')
-- A single long 30 Hz contact interval must not reverse a 208-degree spin.
fx:Begin(4,false);tip.x,tip.z=root.x+1,root.z;fx:Blade(root,tip)
local first=fx.head%24+1
local turn=math.rad(208);tip.x,tip.z=root.x+math.cos(turn),root.z+math.sin(turn)
fx:Blade(root,tip)
assert(fx.arcs[first].pos.z>root.z,'large spin follows authored positive XZ direction')
fx.plunging=true;fx:Descent(root,tip)
for _,s in ipairs(fx.ribbons)do assert(s.node.enabled)end
fx.plunging=false;fx:Update(.001)
for _,s in ipairs(fx.ribbons)do assert(not s.node.enabled)end
-- Measure the effect itself, without the engine adapter's simulated allocations.
fx:Impact(pos,forward,true);fx:Begin(4,false);fx:Blade(root,tip);fx:Update(.01)
collectgarbage('collect');collectgarbage('stop');local before=collectgarbage('count')
for i=1,600 do
 if i%60==1 then fx:Impact(pos,forward,true);fx:Begin(4,false) end
 local a=i*.2;tip.x,tip.z=root.x+math.cos(a),root.z+math.sin(a)
 fx:Blade(root,tip);fx:Update(1/60)
end
local growth=collectgarbage('count')-before;collectgarbage('restart')
assert(growth/600<2,'hot FX Lua per-frame growth: '..(growth/600)..' KiB')
print(string.format('FX 600-frame stopped-GC delta %.3f KiB; created nodes %d',growth,#scene.children-children))
-- Mock FromEulerAngles constructs Lua quaternions on Impact; isolate steady
-- sampling/update to distinguish adapter allocations from the effect hot path.
collectgarbage('collect');collectgarbage('stop');before=collectgarbage('count')
for i=1,600 do
 local a=i*.2;tip.x,tip.z=root.x+math.cos(a),root.z+math.sin(a)
 fx:Blade(root,tip);fx:Update(1/60)
end
local steady=collectgarbage('count')-before;collectgarbage('restart')
assert(steady<2,'steady FX Lua growth: '..steady..' KiB')
print(string.format('FX steady 600-frame stopped-GC delta %.3f KiB',steady))
fx:Impact(pos,forward,true);fx:ClearSword()
assert(fx.land[1].active and fx.land[1].node.enabled,'low-quality trail switch preserves essential ground impact')
for _,s in ipairs(fx.arcs)do assert(not s.active and not s.node.enabled)end
fx:Clear();for _,s in ipairs(fx.land)do assert(not s.active and not s.node.enabled)end
fx:Dispose()
print('PASS fixed 30 landing/24 arc/3 descent slots, 360 coverage, lifetime/geometry budget, no hot vectors/nodes')
