package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock')
require('sword_vfx_support').Install()
local Vfx=require('combat.SwordVfx')
local PITCH=.09
local scene=Mock.Node('scene')
local fx=Vfx.New(scene)
local function nodes(n) local c=1;for _,child in ipairs(n.children) do c=c+nodes(child) end;return c end
local built=nodes(scene)
assert(#fx.world.free==Vfx.WORLD_CUBES and #fx.blade.free==Vfx.BLADE_CUBES)
-- Blue-white only: every palette entry is at least as blue as it is red or green.
for _,c in ipairs(fx.world.colors) do assert(c.b>=c.g and c.g>=c.r,'palette stays blue-white') end

local function shown(pool)
    local list={}
    for _,item in ipairs(pool.items) do if item.cube then list[#list+1]=item end end
    return list
end
local function onGrid(x) local k=x/PITCH;return math.abs(k-math.floor(k+.5))<1e-6 end
-- A horizontal quarter swing around the origin at chest height.
local function swing(target,from,to,steps)
    for i=0,steps do
        local a=math.rad(from+(to-from)*i/steps)
        target:Sample(Vector3(math.sin(a)*.2,1,math.cos(a)*.2),Vector3(math.sin(a)*1.1,1,math.cos(a)*1.1))
    end
end
local function signature(target)
    local keys={}
    for _,item in ipairs(shown(target.world)) do
        keys[#keys+1]=string.format('%.3f,%.3f,%.3f,%d',item.px,item.py,item.pz,item.stage)
    end
    table.sort(keys);return table.concat(keys,';')
end

fx:Sample(Vector3(0,1,.2),Vector3(0,1,1.1))
assert(fx.world:Count()==0,'nothing is emitted outside a swing')
fx:Begin('light');swing(fx,0,90,4)
local arc=shown(fx.world)
assert(#arc>40 and #arc==fx.world:Count('arc'),'cells light up on the frame the blade passes them')
local seen={}
for _,item in ipairs(arc) do
    assert(onGrid(item.px) and onGrid(item.py) and onGrid(item.pz),'cubes sit on the world voxel grid')
    local key=string.format('%.3f,%.3f,%.3f',item.px,item.py,item.pz)
    assert(not seen[key],'one cube per cell');seen[key]=true
    local radius=math.sqrt(item.px^2+item.pz^2)
    assert(radius>.55 and radius<1.35 and math.abs(item.py-1)<PITCH*1.6,'cubes stay on the swept blade surface')
    assert(item.px>-PITCH and item.pz>-PITCH,'no cube outside the swept quarter')
end
-- Same swing, same cubes: no randomness anywhere.
local twin=Vfx.New(Mock.Node('twin'));twin:Begin('light');swing(twin,0,90,4)
assert(signature(fx)==signature(twin),'deterministic')
-- A coarse 2-sample swing covers the same band as a fine one: fast swings leave no gaps.
local coarse=Vfx.New(Mock.Node('coarse'));coarse:Begin('light');swing(coarse,0,90,2)
assert(math.abs(#shown(coarse.world)-#arc)<#arc*.25,'frame rate does not thin the arc')
-- Inner rows expire first; the outer edge is the last thing visible.
fx:End();fx:Update(.12)
local inner,outer=0,0
for _,item in ipairs(shown(fx.world)) do
    if math.sqrt(item.px^2+item.pz^2)<.95 then inner=inner+1 else outer=outer+1 end
end
assert(outer>0 and inner<outer*.25,'crescent retracts toward its outer edge')
fx:Update(.2)
assert(fx.world:Count()==0 and #fx.world.free==Vfx.WORLD_CUBES,'every cube returns to the pool')
for _,cube in ipairs(fx.world.free) do assert(not cube.node.enabled) end

-- A new swing never bridges from the previous one.
fx:Begin('light');swing(fx,0,20,2);fx:Begin('light')
fx:Sample(Vector3(0,1,-.2),Vector3(0,1,-1.1))
for _,item in ipairs(shown(fx.world)) do assert(math.abs(item.px)<.5,'no chord between two swings') end
fx:Clear()

-- Hit: a cut along the swing direction plus expanding diamond rings; survives ClearSword.
fx:Begin('heavy');swing(fx,0,40,3)
fx:Contact(Vector3(.5,1,.9),true)
local hit=fx.world:Count('hit')
assert(hit>20 and hit<120)
fx:ClearSword()
assert(fx.world:Count('arc')==0 and fx.world:Count('hit')==hit,'hit confirmation outlives the trail')
fx:Update(.5);assert(fx.world:Count()==0)

-- Finisher: ground columns only ahead of the player, nearer rings first and taller.
fx:GroundWave(Vector3(0,0,0),Vector3(0,0,1))
local wave=fx.world:Count('wave')
assert(wave>60 and wave<=Vfx.WORLD_CUBES)
for _,item in ipairs(fx.world.items) do
    assert(item.pz>-.9,'wave travels forward');assert(item.ground and item.py==0)
end
local first=shown(fx.world)
assert(#first>0 and #first<wave*.2,'rings appear in sequence, not all at once')
fx:Update(.1);local near,far=0,0
for _,item in ipairs(shown(fx.world)) do near=math.max(near,item.cube.node.scale.y) end
fx:Update(.12)
for _,item in ipairs(shown(fx.world)) do far=math.max(far,item.cube.node.scale.y) end
assert(far>0 and far<near,'columns shrink as the front moves out')
fx:Update(1);assert(fx.world:Count()==0)

-- Charge rings ride the blade frame and stay inside their own small pool.
local root,tip=Vector3(0,1,0),Vector3(0,1.9,0)
for i=0,60 do fx:Charge(root,tip,i/60,1/60);fx:Update(1/60) end
assert(fx.blade:Count('charge')>0 and fx.blade:Count('charge')<=Vfx.BLADE_CUBES and fx.world:Count()==0)
fx:ChargeBurst(root,tip);assert(fx.blade:Count('charge')==32)
fx:Update(1);assert(fx.blade:Count()==0 and #fx.blade.free==Vfx.BLADE_CUBES)

-- Pool exhaustion drops inner rows instead of erroring or allocating.
fx:Begin('moon')
for turn=0,5 do swing(fx,turn*360,turn*360+360,24);fx.cells={} end
assert(#fx.world.free>=0 and fx.world:Count()>=Vfx.WORLD_CUBES-80)
fx:Clear();assert(#fx.world.free==Vfx.WORLD_CUBES)
assert(nodes(scene)==built,'no node is created after construction')
fx:Dispose()
print('PASS sword voxel vfx: grid-snapped deterministic arc, edge-last retract, hit/wave/charge budgets, pooled')
