package.path="scripts/?.lua;tests/combat/?.lua;"..package.path
local Mock=require("weapon_mock")
local B=require("combat.WeaponBuilder")
local P=require("combat.WeaponCatalog")
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
    if c.weapon=="sword" then
        Mock.Near(b.hit.length,b.bounds.max[2]); assert(b.hit.radius==.12)
        local tip=-math.huge
        for _,cell in ipairs(g.cells) do if cell.region=='blade' then tip=math.max(tip,cell.y) end end
        Mock.Near(b.hit.length,(tip+.5)*P.VOXEL_SIZE)
        assert(g.sparse['0:'..tip..':0'].region=='blade','actual tip must lie on the hit axis')
        assert(b.stats.reach<=1.4)
    else
        local lx,ly,lz=math.floor(b.hit.origin[1]/.03+.5),math.floor(b.hit.origin[2]/.03+.5),math.floor(b.hit.origin[3]/.03+.5)
        assert(b.hit.dir[1]==0 and b.hit.dir[2]==0 and b.hit.dir[3]==1)
        assert(g.sparse[lx..':'..(ly-1)..':'..lz],'arrow shelf must support the unchanged launch socket')
        for stage=0,2 do
            local shape=B.BowVisual(b,stage)
            local occupied={}
            for _,cell in ipairs(shape.cells) do
                local k=cell.x..':'..cell.y..':'..cell.z
                assert(not occupied[k],'draw shape duplicate voxel');occupied[k]=cell
                if cell.feature=='string' then
                    local grip=g.sparse[k]
                    assert(not grip or grip.region~='grip','string penetrated grip')
                end
            end
            local nz=math.floor(shape.nockZ/.03+.5)
            assert(occupied['0:'..ly..':'..nz].feature=='string','arrow nock must touch the actual rasterized string')
            for z=nz,lz+12 do assert(not occupied[lx..':'..ly..':'..z],'arrow shaft corridor obstructed') end
            local arrow=B.NockedArrow(b)
            local arrowSeen={}
            for _,cell in ipairs(arrow) do
                local k=cell.x..':'..cell.y..':'..cell.z
                assert(not arrowSeen[k],'duplicate arrow cell');arrowSeen[k]=true
                local contact=occupied[(lx+cell.x)..':'..(ly+cell.y)..':'..(nz+cell.z)]
                assert(not contact or contact.feature=='string','arrow/feather intersects grip or limb')
            end
            assert(arrowSeen['-2:0:0'] and arrowSeen['0:0:21'],'nock/shaft missing')
        end
    end
    checked=checked+1
end
for _,weapon in ipairs({'sword','bow'}) do verify(config(weapon)) end
assert(checked==2)
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
local nextMesh=assert(B.Build(world,scene,c,mesh))
assert(nextMesh==mesh and world.rebuilds==1,'cosmetics retain geometry')
B.Dispose(nextMesh);B.Dispose(nextMesh)
assert(world.removed==1)
assert(B.Compile({weapon="axe"})==nil)
-- Unrecognized legacy fields cannot change the class's gameplay profile.
local sword=config('sword');sword.parts={blade='blade_broad'}
assert(B.Compile(sword).stats.attack==10 and B.Compile(sword).hit.length==.825)
local bow=config('bow');bow.parts={tip='tip_crystal',limbs='limbs_long'}
local fixed=assert(B.Compile(bow))
assert(fixed.stats.attack==8 and fixed.stats.crystalRadius==nil)
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
for _,weapon in ipairs({'sword','bow'}) do PreviewConfig(config(weapon)) end
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
-- §20 bow orientation: old geometry used X/Y with string at X=-6. New
-- geometry is Y/Z, convex back on +Z and string behind the palm on -Z.
do
    do
        local value=config('bow')
        local bp=assert(B.Compile(value))
        local middle,front=false,false
        for _,cell in ipairs(bp.geometry.cells) do
            local mirrored=bp.geometry.sparse[cell.x..':'..(-cell.y)..':'..cell.z]
            if cell.region~='grip' then assert(mirrored and mirrored.channel==cell.channel,'limbs/tips must be symmetric above/below grip') end
            if cell.feature=='string' and cell.y==0 then assert(cell.x==0 and cell.z<0);middle=true end
            if cell.region=='limbs' and cell.feature~='string' and cell.z>0 then front=true end
        end
        assert(middle and front and bp.hit.origin[1]>0 and bp.hit.dir[3]==1)
        local lastZ=0
        for stage=0,2 do
            local shape=B.BowVisual(bp,stage)
            assert(shape.stringMidpoint[3]<lastZ);lastZ=shape.stringMidpoint[3]
            local occupied={}
            for _,cell in ipairs(shape.cells) do occupied[cell.x..':'..cell.y..':'..cell.z]=true end
            for _,cell in ipairs(shape.cells) do
                if cell.region~='grip' then assert(occupied[cell.x..':'..(-cell.y)..':'..cell.z],'draw limbs must stay vertically symmetric') end
                if cell.feature=='string' and cell.y==0 then
                    assert(math.abs(cell.z*P.VOXEL_SIZE-shape.stringMidpoint[3])<=P.VOXEL_SIZE/2+.0001)
                end
            end
        end
    end
end
print(B.BowTopASCII(assert(B.Compile(config('bow')))))
print("weapon_builder: PASS (72 volume+greedy preview combinations, exact surface/color coverage, winding, bounds, cancellation, cache)")
