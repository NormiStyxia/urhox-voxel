package.path="scripts/?.lua;tests/combat/?.lua;"..package.path
local Mock=require("weapon_mock")
local B=require("combat.WeaponBuilder")
local P=require("combat.WeaponParts")
local function config(weapon) local c=P.DefaultWeapon(weapon);c.weapon=weapon;return c end
local checked=0
local function verify(c)
    local b=assert(B.Compile(c))
    assert(B.Compile(c)==b,"compiled cache")
    local g=b.geometry
    assert(#g.cells>0 and #g.cells<=4000)
    local count=0
    for _ in pairs(g.sparse) do count=count+1 end
    assert(count==#g.cells)
    for _,cell in ipairs(g.cells) do
        for i,coord in ipairs({cell.x,cell.y,cell.z}) do
            assert(coord%1==0 and coord>=b.bounds.gridMin[i] and coord<=b.bounds.gridMax[i])
        end
    end
    -- Every occupied cell must connect to the grip through six-neighbour adjacency.
    local queue={g.cells[1]};local seen={}
    local function key(x,y,z) return x..":"..y..":"..z end
    seen[key(queue[1].x,queue[1].y,queue[1].z)]=true
    local i=1
    while queue[i] do
        local v=queue[i]; i=i+1
        for _,d in ipairs({{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}) do
            local k=key(v.x+d[1],v.y+d[2],v.z+d[3])
            if g.sparse[k] and not seen[k] then seen[k]=true;queue[#queue+1]=g.sparse[k] end
        end
    end
    assert(#queue==#g.cells,c.weapon.." disconnected geometry")
    local slots=P.Slots[c.weapon]
    for index=2,#slots do
        local a,z=assert(slots[index-1]),assert(slots[index])
        local before,after=assert(P.Get(c.parts[a])),assert(P.Get(c.parts[z]))
        for axis=1,3 do
            assert(before.sockets.top[axis]+g.offsets[a][axis]==after.sockets.root[axis]+g.offsets[z][axis],"socket mismatch")
        end
    end
    if c.weapon=="sword" then
        Mock.Near(b.hit.length,b.bounds.max[2]); assert(b.hit.radius==.12)
        assert(b.stats.speed>=.7 and b.stats.speed<=1.4 and b.stats.reach<=1.4)
    else
        assert(g.overlaps>0,"bow tip must overlap the upper limb socket")
    end
    checked=checked+1
end
for weapon,slots in pairs(P.Slots) do
    local c=config(weapon)
    local function combinations(i)
        if i>#slots then verify(c);return end
        for _,part in ipairs(P.GetOptions(weapon,slots[i])) do c.parts[slots[i]]=part.id;combinations(i+1) end
    end
    combinations(1)
end
assert(checked==72)
-- Deliberate four-way collision fixture tests sword priority independent of data.
local synthetic=config("sword")
for _,slot in ipairs(P.Slots.sword) do
    local id="test_"..slot
    P.ById[id]={id=id,weapon="sword",slot=slot,name=id,desc=id,voxels={{"P"}},origin={0,0,0},
        palette={P="primary"},sockets={root={0,0,0},top={0,0,0}},stats={}}
    synthetic.parts[slot]=id
end
local overlap=assert(B.Compile(synthetic))
assert(#overlap.geometry.cells==1 and overlap.geometry.overlaps==3)
assert(overlap.geometry.cells[1].slot=="blade")
local scene=Mock.Node("scene") --[[@as any]] -- intentional engine contract double
local world=Mock.World(scene) --[[@as any]]
local c=config("sword")
local mesh=assert(B.Build(world,scene,c))
assert(world.created==1 and world.rebuilds==1 and not mesh.volume.destructible and mesh.volume.collisionMask==0 and mesh.volume.collisionLayer==0)
local originalGeometry=mesh.blueprint.geometry
local writes,paletteWrites=world.writes,world.paletteWrites
assert(B.Build(world,scene,c,mesh)==mesh and world.paletteWrites==paletteWrites)
c.colors.accent=6
assert(B.Build(world,scene,c,mesh)==mesh)
assert(world.rebuilds==1 and world.writes==writes and mesh.blueprint.geometry==originalGeometry)
assert(world.paletteWrites>paletteWrites)
local colourBlueprint=mesh.blueprint
c.colors.accent=4
assert(colourBlueprint.config.colors.accent==6,"input must not mutate cached configuration")
B.SetOpacity(mesh,.5)
local fade=mesh.fade --[[@as any]] -- inspect the mock's recorded native calls
assert(mesh.volume.material==mesh.fade and fade.parameters.MatDiffColor.a==.5)
assert(fade.technique.passes.deferred==nil and fade.technique.passes.shadow==nil)
c.parts.blade="blade_broad"
local nextMesh=assert(B.Build(world,scene,c,mesh))
assert(nextMesh~=mesh and mesh.disposed and nextMesh.alpha==.5 and world.removed==1 and world.rebuilds==2)
B.Dispose(nextMesh);B.Dispose(nextMesh)
assert(world.removed==2)
assert(B.Compile({weapon="axe"})==nil)
local sword=config('sword');sword.parts.pommel='pommel_crystal'
local crystal=assert(B.Compile(sword))
Mock.Near(crystal.stats.charge,.45*.92);Mock.Near(crystal.stats.attack,9.5)
local bow=config('bow');bow.parts.grip='bow_grip_stable';bow.parts.tip='tip_crystal'
local tuned=assert(B.Compile(bow))
Mock.Near(tuned.stats.draw,.7/.92);Mock.Near(tuned.stats.spread,.75);Mock.Near(tuned.stats.move,.6)
Mock.Near(tuned.stats.armorBreak,1.25);Mock.Near(tuned.stats.range,36*.92)
Mock.Near(tuned.stats.projectileSpeed,.9);Mock.Near(tuned.stats.crystalRadius,.8)
assert(tuned.stats.crystalDamageMultiplier==.25 and tuned.stats.crystalDamage==nil)
for _,grip in ipairs(P.GetOptions('bow','grip')) do
    bow.parts.grip=grip.id
    local bp=assert(B.Compile(bow))
    Mock.Near(bp.hit.origin[1],0);Mock.Near(bp.hit.origin[2],.06);Mock.Near(bp.hit.origin[3],.09)
    assert(bp.hit.origin[2]<bp.bounds.max[2]/2,'launch must stay near grip')
end
-- Time-sliced preview writes, cancellation and measured indivisible native work.
local clockMs=0
local function clock() clockMs=clockMs+.1;return clockMs end
local job=B.BeginBuild(world,scene,config('sword'))
for _=1,200 do
    local before=world.writes
    local done=B.StepBuild(job,2,clock)
    assert(world.writes-before<=192,'cell batch exceeded')
    if job.phase=='geometry' then
        local rebuild=job.volume.RebuildGeometry
        job.volume.RebuildGeometry=function() clockMs=clockMs+3;rebuild() end
    end
    if done then break end
end
assert(job.done and job.mesh and job.steps>5 and job.overBudget and job.nativeMs>=3)
assert(job.mesh.volume.collisionLayer==0 and job.mesh.volume.collisionMask==0)
local asyncMesh=job.mesh
local same=config('sword');same.colors.primary=4
local recolor=B.BeginBuild(world,scene,same,asyncMesh)
local rebuilds=world.rebuilds
assert(B.StepBuild(recolor,2,clock) and recolor.mesh==asyncMesh and world.rebuilds==rebuilds)
local replacement=config('sword');replacement.parts.blade='blade_broad'
local cancel=B.BeginBuild(world,scene,replacement,asyncMesh)
B.StepBuild(cancel,2,clock);B.StepBuild(cancel,2,clock);B.StepBuild(cancel,2,clock)
local partial=cancel.volume
B.CancelBuild(cancel);B.CancelBuild(cancel)
assert(partial.removed and not asyncMesh.disposed and cancel.cancelled)
B.Dispose(asyncMesh);assert(world.created==world.removed)
-- Real binding shape: the global Time singleton requires its receiver, returns
-- seconds, and may be absent/broken in a sandbox. None may stall the build.
local savedTime,savedOs=rawget(_G,'time'),rawget(_G,'os')
rawset(_G,'os',nil) -- no accidental reliance on the host Lua standard library
rawset(_G,'GetTime',function() error('legacy GetSystemTime path') end)
local function Complete(clockOverride,unavailable)
    local pending=B.BeginBuild(world,scene,config('sword'))
    for _=1,1000 do
        local cursor,phase,writesBefore=pending.cursor,pending.phase,world.writes
        local done=B.StepBuild(pending,2,clockOverride)
        assert(world.writes-writesBefore<=192,'96 solid+material writes maximum')
        if phase=='fill' then assert(pending.cursor>cursor,'clock must not starve filling') end
        if done then break end
    end
    assert(pending.done and pending.mesh and not pending.error,'clock failure must not abort assembly')
    assert((pending.clockUnavailable==true)==unavailable)
    B.Dispose(pending.mesh)
    return pending
end
local engineTime={seconds=0}
function engineTime:GetElapsedTime()
    assert(self==engineTime,'requires time:GetElapsedTime()')
    self.seconds=self.seconds+.0001
    return self.seconds
end
rawset(_G,'time',engineTime)
local unitProbe=B.BeginBuild(world,scene,config('sword'))
assert(not B.StepBuild(unitProbe,2,nil))
Mock.Near(unitProbe.totalMs,.1) -- .0001 seconds between samples, not .0001 ms
B.CancelBuild(unitProbe)
local measured=Complete(nil,false)
assert(measured.totalMs>0 and measured.steps>5 and measured.maxStepMs<4,'seconds must become milliseconds')
rawset(_G,'time',nil);local untimed=Complete(nil,true)
assert(untimed.totalMs==0 and untimed.nativeMs==0)
rawset(_G,'time',{});Complete(nil,true)
rawset(_G,'time',setmetatable({},{__index=function() error('binding lookup failed') end}));Complete(nil,true)
for _,value in ipairs({'bad',false,0/0,math.huge,-1}) do
    rawset(_G,'time',{GetElapsedTime=function(self) assert(self==rawget(_G,'time'));return value end})
    Complete(nil,true)
end
for _,failAt in ipairs({1,2,9}) do
    local reads=0
    Complete(function() reads=reads+1;if reads>=failAt then error('clock failed mid-build') end;return reads*.1 end,true)
    assert(reads==failAt,'failed clock should be disabled for the remaining job')
end
local backwards=5
Complete(function() backwards=backwards-1;return backwards end,true)
Complete(function() return 0 end,false) -- a coarse/frozen clock still has a cell cap
local coarse=0
Complete(function() coarse=coarse+3;return coarse end,false) -- always over budget; still advances
rawset(_G,'time',savedTime);rawset(_G,'os',savedOs)
assert(world.created==world.removed)
print("weapon_builder: PASS (72 combinations, connected cells, sockets, bounds, overlap priority, cache, palette-only edits, cleanup)")
