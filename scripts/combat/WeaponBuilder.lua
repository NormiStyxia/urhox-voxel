-- Pure compilation + a small engine adapter. No physics finalization, ever.
-- Integer cell coordinates denote centres; the volume's min corner is min-0.5.
local Parts = require("combat.WeaponParts")

---@class WeaponCell
---@field x integer
---@field y integer
---@field z integer
---@field channel string
---@field slot string
---@field feature? string

---@class WeaponGeometry
---@field key string
---@field weapon string
---@field cells WeaponCell[]
---@field sparse table<string, WeaponCell>
---@field offsets table<string, integer[]>
---@field bounds table
---@field stats table<string, number>
---@field hit table
---@field overlaps integer

---@class WeaponBlueprint
---@field key string
---@field geometry WeaponGeometry
---@field config table
---@field stats table<string, number>
---@field hit table
---@field bounds table

---@class WeaponMesh
---@field volume VoxelVolume
---@field node Node
---@field world VoxelPhysicsWorld
---@field blueprint WeaponBlueprint
---@field opaque Material
---@field fade Material
---@field alpha number
---@field disposed boolean

local Builder = {}
local SIZE = Parts.VOXEL_SIZE
local CACHE_LIMIT = 64
Builder.PaletteBase = {sword=160, bow=176}
Builder.ChannelOffset = {primary=0, secondary=1, accent=2, dark=3}
-- 175 is a shared active-weapon trail entry, unused by either weapon's mesh.
Builder.TRAIL_PALETTE = 175
---@type table<string, WeaponCell[]>
local decoded = {}
---@type table<string, WeaponGeometry>
local geometryCache = {}
---@type table<string, WeaponBlueprint>
local blueprintCache = {}
local geometryOrder, blueprintOrder = {}, {}

local function Cache(cacheTable, order, key, value)
    if #order>=CACHE_LIMIT then cacheTable[table.remove(order,1)] = nil end
    order[#order+1] = key
    cacheTable[key] = value
    return value
end

---@param a number
---@param b number
---@param c number
local function Key(a,b,c) return a..":"..b..":"..c end

---@param part WeaponPart
---@return WeaponCell[]
local function Decode(part)
    if decoded[part.id] then return decoded[part.id] end
    local result = {}
    for iy, layer in ipairs(part.voxels) do
        for iz, row in ipairs(layer) do
            for ix=1,#row do
                local char = row:sub(ix,ix)
                if char~="." then
                    result[#result+1] = {x=part.origin[1]+ix-1, y=part.origin[2]+iy-1,
                        z=part.origin[3]+iz-1, channel=part.palette[char], slot=part.slot,feature=char=='W' and 'string' or nil}
                end
            end
        end
    end
    decoded[part.id] = result
    return result
end

local function Sub(a,b) return {a[1]-b[1],a[2]-b[2],a[3]-b[3]} end
local function Add(a,b) return {a[1]+b[1],a[2]+b[2],a[3]+b[3]} end
local LIMITS = {attack={1,40},speed={0.7,1.4},reach={0.8,1.4},poise={0,30},
    charge={0.2,1.2},draw={0.3,1.4},range={12,60},spread={0.1,2},move={0.2,0.8},
    projectileSpeed={0.7,1.4},armorBreak={.5,2},crystalRadius={0,1.5},crystalDamageMultiplier={0,.5}}
local MULTIPLIERS={chargeMultiplier='charge',drawMultiplier='draw',rangeMultiplier='range',
    spreadMultiplier='spread',projectileSpeedMultiplier='projectileSpeed'}

---@param config table
---@param key string
---@return WeaponGeometry
local function Assemble(config,key)
    if geometryCache[key] then return geometryCache[key] end
    local weapon = config.weapon
    ---@type table<string, WeaponPart>
    local selected = {}
    local stats = {}
    for name,value in pairs(Parts.BaseStats[weapon]) do stats[name]=value end
    for _,slot in ipairs(Parts.Slots[weapon]) do
        local part = assert(Parts.Get(config.parts[slot]))
        selected[slot]=part
        for name,value in pairs(part.stats) do
            if MULTIPLIERS[name] then stats[name]=(stats[name] or 1)*value
            else stats[name]=(stats[name] or 0)+value end
        end
    end
    for modifier,target in pairs(MULTIPLIERS) do if stats[modifier] then stats[target]=stats[target]*stats[modifier] end end
    for name,limit in pairs(LIMITS) do
        if stats[name] then stats[name]=math.max(limit[1],math.min(limit[2],stats[name])) end
    end
    -- Grip is anchored at zero; connect down to pommel, then up to guard/blade.
    -- Bow grip/top = limbs/root, then limbs/top = tip/root.
    local offsets = {grip={0,0,0}}
    if weapon=="sword" then
        offsets.pommel=Sub(selected.grip.sockets.root,selected.pommel.sockets.top)
        offsets.guard=Sub(selected.grip.sockets.top,selected.guard.sockets.root)
        offsets.blade=Sub(Add(offsets.guard,selected.guard.sockets.top),selected.blade.sockets.root)
    else
        offsets.limbs=Sub(selected.grip.sockets.top,selected.limbs.sockets.root)
        offsets.tip=Sub(Add(offsets.limbs,selected.limbs.sockets.top),selected.tip.sockets.root)
    end
    ---@type table<string, WeaponCell>
    local sparse = {}
    local overlaps = 0
    -- Low -> high priority. A later slot owns overlaps, not a second voxel.
    for _,slot in ipairs(Parts.Slots[weapon]) do
        local off=offsets[slot]
        for _,cell in ipairs(Decode(selected[slot])) do
            local x,y,z = cell.x+off[1],cell.y+off[2],cell.z+off[3]
            local cellKey=Key(x,y,z)
            if sparse[cellKey] then overlaps=overlaps+1 end
            sparse[cellKey]={x=x,y=y,z=z,channel=cell.channel,slot=slot,feature=cell.feature}
            -- A selected arrowhead also decorates both bow tips symmetrically.
            if weapon=='bow' and slot=='tip' then
                sparse[Key(x,-y,z)]={x=x,y=-y,z=z,channel=cell.channel,slot=slot}
            end
        end
    end
    local cells = {}
    local low,high={math.huge,math.huge,math.huge},{-math.huge,-math.huge,-math.huge}
    for _,cell in pairs(sparse) do
        cells[#cells+1]=cell
        local coord={cell.x,cell.y,cell.z}
        for i=1,3 do low[i]=math.min(low[i],coord[i]); high[i]=math.max(high[i],coord[i]) end
    end
    assert(#cells>0 and #cells<=4000,"weapon voxel budget exceeded")
    table.sort(cells,function(a,b)
        if a.y~=b.y then return a.y<b.y end
        if a.z~=b.z then return a.z<b.z end
        return a.x<b.x
    end)
    local bounds={min={},max={},size={},gridMin=low,gridMax=high,dimensions={}}
    for i=1,3 do
        bounds.min[i]=(low[i]-0.5)*SIZE
        bounds.max[i]=(high[i]+0.5)*SIZE
        bounds.size[i]=(high[i]-low[i]+1)*SIZE
        bounds.dimensions[i]=math.floor(high[i]-low[i]+1)
    end
    -- Sword capsule: grip o========> blade tip, radius .12m.
    -- This exports geometry only; damage and reach scaling belong to Combat.
    ---@type table
    local hit={origin={0,0,0},dir={0,1,0}}
    if weapon=="sword" then
        hit.length=bounds.max[2]
        hit.radius=0.12
    else
        local launch=Add(offsets.grip,selected.grip.sockets.launch)
        hit.origin={launch[1]*SIZE,launch[2]*SIZE,launch[3]*SIZE}
        hit.dir={0,0,1}
    end
    return Cache(geometryCache,geometryOrder,key,{key=key,weapon=weapon,cells=cells,sparse=sparse,
        offsets=offsets,bounds=bounds,stats=stats,hit=hit,overlaps=overlaps})
end

-- Returned blueprints/geometry are shared read-only. Inputs are always copied.
---@param config table
---@return WeaponBlueprint?
---@return string? error
function Builder.Compile(config)
    if type(config)~="table" or not Parts.ValidateWeapon(config.weapon,config) then
        return nil,"invalid weapon configuration"
    end
    local normalized={weapon=config.weapon,parts={},colors={}}
    local ids={config.weapon}
    for _,slot in ipairs(Parts.Slots[config.weapon]) do
        normalized.parts[slot]=config.parts[slot]
        ids[#ids+1]=config.parts[slot]
    end
    local geometryKey=table.concat(ids,"|")
    for _,channel in ipairs(Parts.Channels) do
        normalized.colors[channel]=config.colors[channel]
        ids[#ids+1]=tostring(config.colors[channel])
    end
    local key=table.concat(ids,"|")
    if blueprintCache[key] then return blueprintCache[key] end
    local geometry=Assemble(normalized,geometryKey)
    return Cache(blueprintCache,blueprintOrder,key,{key=key,geometry=geometry,config=normalized,
        stats=geometry.stats,hit=geometry.hit,bounds=geometry.bounds})
end

---@param world VoxelPhysicsWorld
---@param config table validated single-weapon config
function Builder.ApplyPalette(world,config)
    -- Bank 0 has 256 slots; 160..191 are reserved. Enemy slots 200..239 untouched.
    local base=Builder.PaletteBase[config.weapon]
    for _,channel in ipairs({"primary","secondary","accent","dark"}) do
        local preset=Parts.ColorPresets[config.colors[channel=="dark" and "primary" or channel]]
        local rgb=preset.rgb
        local shade=channel=="dark" and 0.38 or 1
        local r,g,b=rgb[1]/255*shade,rgb[2]/255*shade,rgb[3]/255*shade
        local index=base+Builder.ChannelOffset[channel]
        world:SetPaletteEntry(index,Color(r,g,b,1),1000)
        world:SetPaletteEntryPBR(index,channel=="accent" and 0.3 or 0.55,
            config.weapon=="sword" and 0.65 or 0,0.5,Color(r,g,b,channel=="accent" and 0.35 or 0))
    end
end

-- Clone the engine's bound palette material, retaining VOXELPACKED shader defines.
-- Its PBR path multiplies MatDiffColor.a by palette alpha; transparent passes
-- therefore work without a custom shader or rebuilding voxel geometry.
---@param world VoxelPhysicsWorld
---@param name string
---@return Material
function Builder.FadeMaterial(world,name)
    local material=world:GetPaletteMaterial():Clone(name)
    local technique=material:GetTechnique(0):Clone(name.."Technique")
    for _,passName in ipairs({"deferred","prepass","material","depth","shadow","velocity"}) do
        technique:RemovePass(passName)
    end
    for _,passName in ipairs({"base","litbase","light"}) do
        local pass=technique:GetPass(passName)
        if pass then
            pass:SetBlendMode(passName=="light" and BLEND_ADDALPHA or BLEND_ALPHA)
            pass:SetDepthWrite(false)
            pass:SetDepthTestMode(CMP_LESSEQUAL)
        end
    end
    material:SetTechnique(0,technique)
    material:SetShaderParameter("VoxelJitter",Variant(0.0))
    return material
end

---@param mesh WeaponMesh
---@param alpha number
function Builder.SetOpacity(mesh,alpha)
    if mesh.disposed then return end
    local a=math.max(0,math.min(1,alpha))
    mesh.alpha=a
    mesh.node.enabled=a>0
    mesh.volume.material=a>=1 and mesh.opaque or mesh.fade
    if a>0 and a<1 then mesh.fade:SetShaderParameter("MatDiffColor",Variant(Color(1,1,1,a))) end
end

---@param mesh WeaponMesh?
function Builder.Dispose(mesh)
    if not mesh or mesh.disposed then return end
    mesh.disposed=true
    -- RemoveVolume unregisters the native volume and removes its node.
    mesh.world:RemoveVolume(mesh.volume)
    mesh.opaque:Dispose()
    mesh.fade:Dispose()
end

-- Pass the previous mesh to retain its native volume on no-op/colour-only edits.
-- Distinct worlds (game/preview) must have distinct mesh handles.
---@param world VoxelPhysicsWorld
---@param parent Node
---@param config table
---@param previous? WeaponMesh
---@return WeaponMesh?
---@return string? error
function Builder.Build(world,parent,config,previous)
    local blueprint,err=Builder.Compile(config)
    if not blueprint then return nil,err end
    local old=previous and not previous.disposed and previous or nil
    if old and old.world==world and old.blueprint.geometry.key==blueprint.geometry.key then
        if old.blueprint.key~=blueprint.key then Builder.ApplyPalette(world,blueprint.config) end
        old.blueprint=blueprint
        old.node:SetParent(parent)
        return old
    end
    Builder.ApplyPalette(world,blueprint.config)
    local d,minimum=blueprint.bounds.dimensions,blueprint.bounds.gridMin
    local volume=world:CreateVolume(d[1],d[2],d[3],SIZE,Vector3.ZERO,Quaternion())
    local grid=volume:GetGrid()
    local base=Builder.PaletteBase[config.weapon]
    for _,cell in ipairs(blueprint.geometry.cells) do
        local x,y,z=math.floor(cell.x-minimum[1]),math.floor(cell.y-minimum[2]),math.floor(cell.z-minimum[3])
        grid:SetSolid(x,y,z,true)
        grid:SetVoxelMaterial(x,y,z,base+Builder.ChannelOffset[cell.channel])
    end
    volume.destructible=false
    volume.evictable=false
    volume.collisionMask=0
    volume.collisionLayer=0
    local opaque=world:GetPaletteMaterial():Clone("WeaponOpaque_"..config.weapon)
    opaque:SetShaderParameter("VoxelJitter",Variant(0.0))
    volume.material=opaque
    volume:RebuildGeometry()
    local node=volume:GetNode()
    node.name="weapon_voxels_"..config.weapon
    node.temporary=true
    node:SetParent(parent)
    node.rotation=Quaternion()
    node.position=Vector3(blueprint.bounds.min[1],blueprint.bounds.min[2],blueprint.bounds.min[3])
    local mesh={volume=volume,node=node,world=world,blueprint=blueprint,opaque=opaque,
        fade=Builder.FadeMaterial(world,"WeaponFade_"..config.weapon),alpha=1,disposed=false}
    if old then Builder.SetOpacity(mesh,old.alpha); Builder.Dispose(old) end
    return mesh
end

--- Cooperative volume builds: ONLY in an already normally stepped world.
--- Detached RTT scenes must use BeginPreview/StepPreview below instead.
--- At most 96 cells and one native phase per step.
--- Native RebuildGeometry is indivisible; overBudget reports that Web measurement.
---@param world VoxelPhysicsWorld
---@param parent Node
---@param config table
---@param previous WeaponMesh?
---@return table
function Builder.BeginBuild(world,parent,config,previous)
    local copy={weapon=config.weapon,parts={},colors={}}
    for k,v in pairs(config.parts) do copy.parts[k]=v end
    for k,v in pairs(config.colors) do copy.colors[k]=v end
    return {world=world,parent=parent,config=copy,previous=previous,phase='compile',cursor=1,
        done=false,totalMs=0,maxStepMs=0,nativeMs=0,overBudget=false,steps=0}
end

---@param job table?
function Builder.CancelBuild(job)
    if not job or job.done then return end
    if job.volume then job.world:RemoveVolume(job.volume);job.volume=nil end
    if job.opaque then job.opaque:Dispose();job.opaque=nil end
    if job.fade then job.fade:Dispose();job.fade=nil end
    job.done,job.cancelled=true,true
end

-- The engine singleton uses instance dispatch; seconds become milliseconds.
-- Keep this call inside Clock's pcall: sandbox/binding failures are non-fatal.
local function ElapsedMs() return time:GetElapsedTime()*1000 end

---@param job table
---@param override? fun():number
---@return number?
local function Clock(job,override)
    if job.clockUnavailable then return nil end
    local ok,value=pcall(override or ElapsedMs)
    if not ok or type(value)~='number' or value~=value or value<0 or value==math.huge
        or (job.lastClockMs and value<job.lastClockMs) then
        -- Remain bounded by one phase / 96 cells; do not retry a bad clock for
        -- each voxel. Partial metrics are not a complete timing measurement.
        job.clockUnavailable=true
        return nil
    end
    job.lastClockMs=value
    return value
end

---@param job table
---@param budgetMs number?
---@param clock? fun():number Millisecond clock; optional injectable offline clock.
---@return boolean done
---@return WeaponMesh?
---@return string?
function Builder.StepBuild(job,budgetMs,clock)
    if job.done then return true,job.mesh,job.error end
    budgetMs=math.min(2,math.max(.1,budgetMs or 2))
    local start=Clock(job,clock)
    local phase=job.phase
    local ok,reason=pcall(function()
        if job.phase=='compile' then
            job.blueprint=assert(Builder.Compile(job.config))
            local old=job.previous
            if old and not old.disposed and old.world==job.world and old.blueprint.geometry.key==job.blueprint.geometry.key then
                if old.blueprint.key~=job.blueprint.key then Builder.ApplyPalette(job.world,job.config) end
                old.blueprint=job.blueprint;old.node:SetParent(job.parent)
                job.mesh,job.done=old,true
            else job.phase='create' end
        elseif job.phase=='create' then
            local b=job.blueprint.bounds
            job.volume=job.world:CreateVolume(b.dimensions[1],b.dimensions[2],b.dimensions[3],SIZE,Vector3.ZERO,Quaternion())
            job.volume.destructible=false;job.volume.evictable=false
            job.volume.collisionLayer=0;job.volume.collisionMask=0
            job.node=job.volume:GetNode();job.node.enabled=false;job.node.temporary=true
            job.node:SetParent(job.parent);job.node.rotation=Quaternion()
            job.node.position=Vector3(b.min[1],b.min[2],b.min[3])
            job.grid=job.volume:GetGrid();job.phase='materials'
        elseif job.phase=='materials' then
            Builder.ApplyPalette(job.world,job.config)
            job.opaque=job.world:GetPaletteMaterial():Clone('WeaponPreviewOpaque')
            job.opaque:SetShaderParameter('VoxelJitter',Variant(0.0))
            job.fade=Builder.FadeMaterial(job.world,'WeaponPreviewFade')
            job.volume.material=job.opaque;job.phase='fill'
        elseif job.phase=='fill' then
            local cells=job.blueprint.geometry.cells
            local minimum=job.blueprint.bounds.gridMin
            local last=math.min(#cells,job.cursor+95)
            local first=job.cursor
            while job.cursor<=last do
                local now=Clock(job,clock)
                -- Always advance at least one cell, even on a slow/coarse clock.
                if job.cursor>first and start and now and now-start>=budgetMs then break end
                local cell=cells[job.cursor]
                local x,y,z=cell.x-minimum[1],cell.y-minimum[2],cell.z-minimum[3]
                job.grid:SetSolid(x,y,z,true)
                job.grid:SetVoxelMaterial(x,y,z,Builder.PaletteBase[job.config.weapon]+Builder.ChannelOffset[cell.channel])
                job.cursor=job.cursor+1
            end
            if job.cursor>#cells then job.phase='geometry' end
        elseif job.phase=='geometry' then
            local before=Clock(job,clock)
            job.volume:RebuildGeometry()
            local after=Clock(job,clock)
            job.nativeMs=before and after and after-before or 0
            job.phase='publish'
        else
            local mesh={world=job.world,volume=job.volume,node=job.node,blueprint=job.blueprint,
                opaque=job.opaque,fade=job.fade,alpha=1,disposed=false}
            if job.previous and not job.previous.disposed then Builder.SetOpacity(mesh,job.previous.alpha);Builder.Dispose(job.previous)
            else Builder.SetOpacity(mesh,1) end
            job.mesh,job.done=mesh,true
        end
    end)
    local finish=Clock(job,clock)
    local elapsed=start and finish and finish-start or 0
    job.steps=job.steps+1;job.totalMs=job.totalMs+elapsed
    if elapsed>job.maxStepMs then job.slowestPhase=phase end
    job.maxStepMs=math.max(job.maxStepMs,elapsed);job.overBudget=job.overBudget or elapsed>budgetMs
    if not ok then Builder.CancelBuild(job);job.error=tostring(reason) end
    return job.done,job.mesh,job.error
end
-- Render-only preview: never create a second VoxelPhysicsWorld or submit a
-- VoxelVolume mesh job. The detached RTT scene has no physics pulse owner.
-- Greedily merge coplanar, same-channel exposed faces; internal faces vanish.
local function PreviewQuads(blueprint,quads)
    local planes,order={},{}
    local sparse=blueprint.geometry.sparse
    for i,cell in ipairs(blueprint.geometry.cells) do
        local xyz={cell.x,cell.y,cell.z}
        for axis=1,3 do
            local u,v=axis%3+1,(axis+1)%3+1
            for sign=-1,1,2 do
                local neighbor={cell.x,cell.y,cell.z};neighbor[axis]=neighbor[axis]+sign
                if not sparse[Key(neighbor[1],neighbor[2],neighbor[3])] then
                    local layer=xyz[axis]+(sign==1 and 1 or 0)
                    local key=axis..':'..sign..':'..layer
                    local plane=planes[key]
                    if not plane then
                        plane={axis=axis,sign=sign,layer=layer,rows={},minU=xyz[u],maxU=xyz[u],minV=xyz[v],maxV=xyz[v]}
                        planes[key]=plane;order[#order+1]=plane
                    end
                    local row=plane.rows[xyz[v]] or {};plane.rows[xyz[v]]=row;row[xyz[u]]=cell.channel
                    plane.minU=math.min(plane.minU,xyz[u]);plane.maxU=math.max(plane.maxU,xyz[u])
                    plane.minV=math.min(plane.minV,xyz[v]);plane.maxV=math.max(plane.maxV,xyz[v])
                end
            end
        end
        if i%32==0 then coroutine.yield() end
    end
    for _,plane in ipairs(order) do
        for v=plane.minV,plane.maxV do
            local row=plane.rows[v] or {}
            local u=plane.minU
            while u<=plane.maxU do
                local channel=row[u]
                if channel then
                    local w,h=1,1
                    while row[u+w]==channel do w=w+1 end
                    while true do
                        local nextRow=plane.rows[v+h];local same=nextRow~=nil
                        if same then for x=u,u+w-1 do if nextRow[x]~=channel then same=false;break end end end
                        if not same then break end
                        h=h+1
                    end
                    for y=v,v+h-1 do for x=u,u+w-1 do plane.rows[y][x]=nil end end
                    quads[#quads+1]={axis=plane.axis,sign=plane.sign,layer=plane.layer,u=u,v=v,w=w,h=h,channel=channel}
                    u=u+w
                else u=u+1 end
            end
            coroutine.yield() -- bounded row; the caller checks time between rows
        end
    end
end

---@param mesh table?
function Builder.DisposePreview(mesh)
    if not mesh or mesh.disposed then return end
    mesh.node:Remove();mesh.disposed=true
end

---@param job table?
function Builder.CancelPreview(job)
    if not job or job.done then return end
    if job.node then job.node:Remove();job.node=nil end
    job.worker=nil;job.done=true;job.cancelled=true
end

---@param parent Node
---@param config table
---@param previous table?
---@return table
function Builder.BeginPreview(parent,config,previous)
    return {parent=parent,blueprint=assert(Builder.Compile(config)),previous=previous,
        phase='quads',stage='quads',quads={},cursor=1,steps=0,totalMs=0,maxStepMs=0,nativeMs=0,overBudget=false,
        materialName='Materials/NomiVoxel.xml',materialLoaded=false,commitResult='not_called',setMaterialResult='not_called'}
end

local function PreviewFail(job,code,detail)
    job.failureCode=code
    error(code..': '..tostring(detail),0)
end
local function Short(value) return tostring(value):gsub('[\r\n]+',' '):sub(1,260) end
local function NativePreviewInfo(job)
    if not job.geometry then return end
    local ok,count=pcall(function() return job.geometry:GetNumVertices(0) end)
    job.nativeVertices=ok and type(count)=='number' and count==count and count>=0 and count or nil
    job.nativeVerticesDetail=job.nativeVertices or ('unavailable('..Short(count)..')')
    local boundsOK,bounds=pcall(function()
        local b=job.geometry.boundingBox
        return string.format('(%.3f,%.3f,%.3f)..(%.3f,%.3f,%.3f)',b.min.x,b.min.y,b.min.z,b.max.x,b.max.y,b.max.z)
    end)
    job.nativeBounds=boundsOK and bounds or ('unavailable('..Short(bounds)..')')
    local materialOK,material=pcall(function() return job.geometry:GetMaterial(0) end)
    job.materialBound=materialOK and tostring(material~=nil) or ('unavailable('..Short(material)..')')
end

--- Pure formatting for the panel's once-per-outcome/rate-limited log.
---@param job table?
---@return string
function Builder.PreviewDiagnostic(job)
    if not job then return 'job=none' end
    local b=job.blueprint and job.blueprint.bounds
    local bounds=b and string.format('(%.3f,%.3f,%.3f)..(%.3f,%.3f,%.3f)',
        b.min[1],b.min[2],b.min[3],b.max[1],b.max[2],b.max[3]) or 'unavailable'
    local quads=job.quads and #job.quads or 0
    return 'phase='..tostring(job.phase)..' stage='..tostring(job.stage)..' code='..tostring(job.failureCode or 'none')
        ..' detail='..Short(job.error or 'none')..' vertices='..tostring((job.cursor-1)*6)..'/'..tostring(quads*6)
        ..' quads='..quads..' triangles='..tostring(quads*2)..' native_vertices='..tostring(job.nativeVerticesDetail or 'not_queried')
        ..' material='..job.materialName..' loaded='..tostring(job.materialLoaded)..' bound='..tostring(job.materialBound or 'not_queried')
        ..' set_material='..job.setMaterialResult..' commit='..job.commitResult
        ..' bounds='..bounds..' native_bounds='..tostring(job.nativeBounds or 'not_queried')
end

local POSITIVE={1,2,3,1,3,4}
local NEGATIVE={1,4,3,1,3,2}
---@param geom CustomGeometry
---@param q table
---@param color Color
local function EmitQuad(geom,q,color)
    local axis,u,v=q.axis,q.axis%3+1,(q.axis+1)%3+1
    local normal={0,0,0};normal[axis]=q.sign
    local n=Vector3(normal[1],normal[2],normal[3])
    local corners={}
    for i,uv in ipairs({{q.u,q.v},{q.u+q.w,q.v},{q.u+q.w,q.v+q.h},{q.u,q.v+q.h}}) do
        local p={0,0,0};p[axis]=q.layer;p[u]=uv[1];p[v]=uv[2]
        -- Cells are centred on integer coordinates, as in Compile.bounds.
        corners[i]=Vector3((p[1]-.5)*SIZE,(p[2]-.5)*SIZE,(p[3]-.5)*SIZE)
    end
    for _,i in ipairs(q.sign==1 and POSITIVE or NEGATIVE) do
        geom:DefineVertex(corners[i]);geom:DefineNormal(n);geom:DefineColor(color)
    end
end

---@param job table
---@param budgetMs number?
---@param clock? fun():number
---@return boolean
---@return table?
---@return string?
function Builder.StepPreview(job,budgetMs,clock)
    if job.done then return true,job.mesh,job.error end
    local start=Clock(job,clock)
    local phase=job.phase
    budgetMs=math.min(2,math.max(.1,budgetMs or 2))
    local function Spent()
        local now=Clock(job,clock)
        return start and now and now-start>=budgetMs
    end
    local ok,reason=pcall(function()
        job.stage=phase
        if phase=='quads' then
            job.worker=job.worker or coroutine.create(function() PreviewQuads(job.blueprint,job.quads) end)
            for _=1,24 do
                local resumed,err=coroutine.resume(job.worker);assert(resumed,err)
                if coroutine.status(job.worker)=='dead' then job.worker=nil;job.phase='create';break end
                if Spent() then break end
            end
        elseif phase=='create' then
            if #job.quads==0 then PreviewFail(job,'no_quads','exposed face list empty') end
            job.stage='create_node'
            job.node=job.parent:CreateChild('ForgeCustomGeometry')
            if not job.node then PreviewFail(job,'node_nil','CreateChild returned nil') end
            job.node.enabled=false;job.node.temporary=true
            job.stage='create_custom_geometry'
            job.geometry=job.node:CreateComponent('CustomGeometry')
            if not job.geometry then PreviewFail(job,'custom_geometry_nil','CreateComponent returned nil') end
            job.stage='begin_geometry'
            job.geometry:BeginGeometry(0,TRIANGLE_LIST)
            job.stage='load_material'
            job.material=cache:GetResource('Material',job.materialName)
            job.materialLoaded=job.material~=nil
            if not job.material then PreviewFail(job,'material_nil',job.materialName) end
            job.geometry.castShadows=false
            job.stage='vertex_colors'
            job.colors={}
            for _,channel in ipairs({'primary','secondary','accent','dark'}) do
                local index=job.blueprint.config.colors[channel=='dark' and 'primary' or channel]
                ---@type number[]
                local rgb=Parts.ColorPresets[index].rgb
                local shade=channel=='dark' and .38 or 1
                job.colors[channel]=Color(rgb[1]/255*shade,rgb[2]/255*shade,rgb[3]/255*shade,1)
            end
            job.phase='emit'
        elseif phase=='emit' then
            job.stage='define_vertex_normal_color'
            local last=math.min(#job.quads,job.cursor+31)
            while job.cursor<=last do
                local q=job.quads[job.cursor];EmitQuad(job.geometry,q,job.colors[q.channel])
                job.cursor=job.cursor+1
                if Spent() then break end
            end
            if job.cursor>#job.quads then job.phase='commit' end
        elseif phase=='commit' then
            if job.cursor<=1 then PreviewFail(job,'no_vertices','no complete triangles submitted') end
            local before=Clock(job,clock)
            job.stage='commit'
            job.commitResult='calling'
            local committed=job.geometry:Commit()
            job.commitResult=committed==nil and 'nil(void)' or Short(committed)
            if committed==false then PreviewFail(job,'commit_false','Commit returned false') end
            local after=Clock(job,clock);job.nativeMs=before and after and after-before or 0
            -- Match BlockCharacter.CreateVoxel: bind material AFTER Commit.
            job.stage='set_material'
            job.setMaterialResult='calling'
            local bound=job.geometry:SetMaterial(0,job.material)
            job.setMaterialResult=bound==nil and 'nil(binding)' or Short(bound)
            if bound==false then PreviewFail(job,'set_material_false','SetMaterial(0, material) returned false') end
            job.node.enabled=true
            job.verifyFrames=0;job.phase='verify'
        elseif phase=='verify' then
            -- StepPreview is called once per Update: first query is a later
            -- frame. Unsupported introspection is diagnostic, not a mesh failure.
            job.stage='verify_vertices';job.verifyFrames=job.verifyFrames+1
            NativePreviewInfo(job)
            if job.nativeVertices==0 then
                if job.verifyFrames<3 then return end
                PreviewFail(job,'vertices_zero_after_3_frames','CPU vertices exist but native count stayed zero')
            end
            job.phase='publish'
        else
            job.node.enabled=true
            job.mesh={node=job.node,geometry=job.geometry,blueprint=job.blueprint,quads=job.quads,
                vertexCount=(job.cursor-1)*6,materialReady=true}
            Builder.DisposePreview(job.previous)
            job.done=true
        end
    end)
    local finish=Clock(job,clock);local elapsed=start and finish and finish-start or 0
    job.steps=job.steps+1;job.totalMs=job.totalMs+elapsed
    if elapsed>job.maxStepMs then job.slowestPhase=phase end
    job.maxStepMs=math.max(job.maxStepMs,elapsed);job.overBudget=job.overBudget or elapsed>budgetMs
    if not ok then
        job.error=tostring(reason);job.failureCode=job.failureCode or 'binding_or_lua_error'
        if job.commitResult=='calling' then job.commitResult='threw' end
        if job.setMaterialResult=='calling' then job.setMaterialResult='threw' end
        -- Preserve the exact failing verification sample (a second query could
        -- already return a different native count). Capture other phases before
        -- freeing their partially created geometry.
        if phase~='verify' then NativePreviewInfo(job) end
        Builder.CancelPreview(job);job.mesh=nil
    end
    return job.done,job.mesh,job.error
end
-- Zero-draw string has 6cm clearance. Draw positions -0.18/-0.35m are absolute;
-- voxel centres quantize to 3cm. This never changes Compile's hit/stats.
---@param blueprint WeaponBlueprint
---@param stage integer 0 | 1 | 2
---@return table
function Builder.BowVisual(blueprint,stage)
    local cells={}
    local half=assert(Parts.Get(blueprint.config.parts.limbs)).sockets.top[2]
    local mid=stage==0 and -.06 or (stage==1 and -.18 or -.35)
    for _,cell in ipairs(blueprint.geometry.cells) do
        if cell.feature~='string' then
            local bend=cell.slot=='limbs' and math.floor(stage*math.abs(cell.y)/half+.5) or (cell.slot=='tip' and stage or 0)
            cells[#cells+1]={x=cell.x,y=cell.y,z=cell.z-bend,channel=cell.channel,slot=cell.slot}
        end
    end
    local seen={}
    for side=-1,1,2 do
        for step=0,half*8 do
            local t=step/(half*8)
            local y=side*math.floor(half*t+.5)
            local z=math.floor((mid/SIZE)*(1-t)+(-2-stage)*t+.5)
            if y==0 then z=math.floor(mid/SIZE+.5) end
            local key=Key(0,y,z)
            if not seen[key] then
                cells[#cells+1]={x=0,y=y,z=z,channel='accent',slot='limbs',feature='string'};seen[key]=true
            end
        end
    end
    return {cells=cells,stringMidpoint={0,0,mid},stage=stage}
end

--- Rows run target(+Z) -> shooter(-Z), columns -X -> +X.
---@param blueprint WeaponBlueprint
---@return string
function Builder.BowTopASCII(blueprint)
    local rows={'Bow top: +Z target; X left -> right; G grip, W string, B bow back'}
    local b=blueprint.bounds
    for z=b.gridMax[3],b.gridMin[3],-1 do
        local row={}
        for x=b.gridMin[1],b.gridMax[1] do
            local mark='.'
            for _,cell in ipairs(blueprint.geometry.cells) do
                if cell.x==x and cell.z==z then mark=cell.feature=='string' and 'W' or (mark=='W' and mark or 'B') end
            end
            if x==0 and z==0 then mark='G' end
            row[#row+1]=mark
        end
        rows[#rows+1]=string.format('%+.2f %s',z*SIZE,table.concat(row))
    end
    rows[#rows+1]='-Z shooter; arrow at +X, direction +Z'
    return table.concat(rows,'\n')
end

--- Pool creation/edit time only, never called by Rig.Update. Main stepped world.
---@param world VoxelPhysicsWorld
---@param parent Node
---@param blueprint WeaponBlueprint
---@param cells table[]
---@param name string
---@return table
function Builder.VisualVolume(world,parent,blueprint,cells,name)
    local lo,hi={math.huge,math.huge,math.huge},{-math.huge,-math.huge,-math.huge}
    for _,c in ipairs(cells) do
        for i,n in ipairs({c.x,c.y,c.z}) do lo[i]=math.min(lo[i],n);hi[i]=math.max(hi[i],n) end
    end
    assert(#cells>0,'empty visual pool')
    local volume=world:CreateVolume(hi[1]-lo[1]+1,hi[2]-lo[2]+1,hi[3]-lo[3]+1,SIZE,Vector3.ZERO,Quaternion())
    volume.destructible=false;volume.evictable=false;volume.collisionLayer=0;volume.collisionMask=0
    local grid=volume:GetGrid()
    local base=Builder.PaletteBase[blueprint.config.weapon]
    for _,c in ipairs(cells) do
        grid:SetSolid(c.x-lo[1],c.y-lo[2],c.z-lo[3],true)
        grid:SetVoxelMaterial(c.x-lo[1],c.y-lo[2],c.z-lo[3],base+Builder.ChannelOffset[c.channel])
    end
    local material=Builder.FadeMaterial(world,name)
    volume.material=material;volume:RebuildGeometry()
    local node=volume:GetNode();node:SetParent(parent);node.name=name;node.temporary=true;node.enabled=false
    node.rotation=Quaternion();node.position=Vector3((lo[1]-.5)*SIZE,(lo[2]-.5)*SIZE,(lo[3]-.5)*SIZE)
    return {node=node,volume=volume,material=material,minimum=node.position}
end
return Builder
