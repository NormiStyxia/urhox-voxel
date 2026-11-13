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
-- Render-only greedy CustomGeometry: exact exposed surface coverage, no hidden
-- faces/duplicates, outward winding, all palette channels, fixed grip/bounds.
local savedCache=rawget(_G,'cache')
local previewMaterial={}
rawset(_G,'cache',{GetResource=function(_,kind,path)
    assert(kind=='Material' and path=='Materials/NomiVoxel.xml');return previewMaterial
end})
local function PreviewConfig(value)
    local pending=B.BeginPreview(scene,value,nil)
    for _=1,1000 do if B.StepPreview(pending,2,nil) then break end end
    assert(pending.done and pending.mesh and not pending.error)
    local result=pending.mesh --[[@as any]] -- recorded custom geometry, not native userdata
    local faces,seen={},{}
    local function cellKey(p) return p[1]..':'..p[2]..':'..p[3] end
    local function faceKey(axis,sign,layer,u,v) return table.concat({axis,sign,layer,u,v},':') end
    local total=0
    for _,cell in ipairs(result.blueprint.geometry.cells) do
        local p={cell.x,cell.y,cell.z}
        for axis=1,3 do for sign=-1,1,2 do
            local neighbor={cell.x,cell.y,cell.z};neighbor[axis]=neighbor[axis]+sign
            if not result.blueprint.geometry.sparse[cellKey(neighbor)] then
                faces[faceKey(axis,sign,p[axis]+(sign==1 and 1 or 0),p[axis%3+1],p[(axis+1)%3+1])]=cell.channel
                total=total+1
            end
        end end
    end
    local covered=0
    for _,q in ipairs(result.quads) do
        for u=q.u,q.u+q.w-1 do for v=q.v,q.v+q.h-1 do
            local key=faceKey(q.axis,q.sign,q.layer,u,v)
            assert(faces[key]==q.channel and not seen[key],'greedy mesh omitted/duplicated or merged across a color')
            seen[key]=true;covered=covered+1
        end end
    end
    assert(covered==total and #result.quads<total,'real weapon faces should merge')
    local geom=result.geometry
    assert(geom.material==previewMaterial and geom.commits==1 and #geom.vertices==#result.quads*6)
    local lower,upper={math.huge,math.huge,math.huge},{-math.huge,-math.huge,-math.huge}
    for i,vertex in ipairs(geom.vertices) do
        local p={vertex.position.x,vertex.position.y,vertex.position.z}
        for axis=1,3 do lower[axis]=math.min(lower[axis],p[axis]);upper[axis]=math.max(upper[axis],p[axis]) end
        assert(vertex.color and vertex.color.a==1 and vertex.normal)
        local channel=result.quads[math.ceil(i/6)].channel
        ---@type number[]
        local rgb=P.ColorPresets[value.colors[channel=='dark' and 'primary' or channel]].rgb
        local shade=channel=='dark' and .38 or 1
        Mock.Near(vertex.color.r,rgb[1]/255*shade)
        Mock.Near(vertex.color.g,rgb[2]/255*shade)
        Mock.Near(vertex.color.b,rgb[3]/255*shade)
    end
    for axis=1,3 do Mock.Near(lower[axis],result.blueprint.bounds.min[axis]);Mock.Near(upper[axis],result.blueprint.bounds.max[axis]) end
    for i=1,#geom.vertices,3 do
        local a,b,d=geom.vertices[i],geom.vertices[i+1],geom.vertices[i+2]
        local e=(b.position-a.position) --[[@as Vector3]]
        local f=(d.position-a.position) --[[@as Vector3]]
        local cross={e.y*f.z-e.z*f.y,e.z*f.x-e.x*f.z,e.x*f.y-e.y*f.x}
        assert(cross[1]*a.normal.x+cross[2]*a.normal.y+cross[3]*a.normal.z>0,'back-face culled preview')
    end
    B.DisposePreview(result);B.DisposePreview(result)
    assert(result.node.removed and not result.volume and world.created==world.removed)
end
for weapon,slots in pairs(P.Slots) do
    local value=config(weapon)
    local function combinations(i)
        if i>#slots then PreviewConfig(value);return end
        for _,part in ipairs(P.GetOptions(weapon,slots[i])) do value.parts[slots[i]]=part.id;combinations(i+1) end
    end
    combinations(1)
end
local tinted=config('sword');tinted.colors={primary=6,secondary=5,accent=2};PreviewConfig(tinted)
for _,phase in ipairs({'quads','create','emit','commit','verify','publish'}) do
    local pending=B.BeginPreview(scene,config('bow'),nil)
    for _=1,1000 do if pending.phase==phase then break end;B.StepPreview(pending,2,nil) end
    assert(pending.phase==phase)
    local node=pending.node
    B.CancelPreview(pending);B.CancelPreview(pending)
    assert(pending.cancelled and (not node or node.removed))
end
-- Native bindings are not guaranteed to expose counts immediately after Commit.
-- Diagnostic failures must identify the exact stage and preserve cleanup.
local function DiagnosticPreview(options,expectedCode)
    local parent=Mock.Node('diagnostic') --[[@as any]]
    local createChild=parent.CreateChild
    parent.CreateChild=function(self,name)
        local node=createChild(self,name)
        node.CreateComponent=function(_,kind)
            assert(kind=='CustomGeometry')
            if options.nilGeometry then return nil end
            return Mock.CustomGeometry(node,options)
        end
        return node
    end
    local pending=B.BeginPreview(parent,config('sword'),nil)
    for _=1,1000 do
        local phase=pending.phase
        B.StepPreview(pending,2,nil)
        if phase=='commit' and not pending.done then
            assert(pending.phase=='verify' and pending.geometry.queries==0,'never query native counts in Commit frame')
        end
        if pending.done then break end
    end
    local diagnostic=B.PreviewDiagnostic(pending)
    assert(pending.done and diagnostic:find('vertices=',1,true) and diagnostic:find('quads=',1,true)
        and diagnostic:find('triangles=',1,true) and diagnostic:find('material=Materials/NomiVoxel.xml',1,true)
        and diagnostic:find('bounds=(',1,true) and diagnostic:find('native_bounds=',1,true))
    if expectedCode then
        assert(not pending.mesh and pending.failureCode==expectedCode,diagnostic)
        assert(parent.children[1].removed,'partial preview leaked')
    else
        assert(pending.mesh and not pending.error,diagnostic)
        assert(pending.commitResult=='nil(void)' and pending.setMaterialResult=='true')
        assert(pending.mesh.vertexCount>0 and pending.mesh.materialReady and pending.materialBound=='true')
        B.DisposePreview(pending.mesh)
    end
    return pending,diagnostic
end
local delayed=DiagnosticPreview({zeroQueries=2})
assert(delayed.verifyFrames==3,'allow subsequent frame native publication')
local unsupported=DiagnosticPreview({countThrow=true})
assert(unsupported.verifyFrames==1 and unsupported.nativeVerticesDetail:find('unavailable',1,true))
local stayedEmpty=DiagnosticPreview({zeroQueries=3},'vertices_zero_after_3_frames')
assert(stayedEmpty.nativeVertices==0 and stayedEmpty.geometry.queries==3,'diagnostics must preserve the failing native sample')
DiagnosticPreview({nilGeometry=true},'custom_geometry_nil')
DiagnosticPreview({commitFalse=true},'commit_false')
local commitFailure=DiagnosticPreview({commitThrow=true},'binding_or_lua_error')
assert(commitFailure.stage=='commit' and commitFailure.commitResult=='threw')
DiagnosticPreview({materialFalse=true},'set_material_false')
local materialFailure=DiagnosticPreview({materialThrow=true},'binding_or_lua_error')
assert(materialFailure.stage=='set_material' and materialFailure.setMaterialResult=='threw')
rawset(_G,'cache',{GetResource=function() return nil end})
local missing=DiagnosticPreview({},'material_nil')
assert(missing.stage=='load_material' and not missing.materialLoaded and missing.commitResult=='not_called')
rawset(_G,'cache',savedCache)
print("weapon_builder: PASS (72 volume+greedy preview combinations, exact surface/color coverage, winding, bounds, cancellation, cache)")
