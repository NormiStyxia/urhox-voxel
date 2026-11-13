-- Pure compilation + a small engine adapter. No physics finalization, ever.
-- Integer cell coordinates denote centres; the volume's min corner is min-0.5.
local Parts = require("combat.WeaponParts")

---@class WeaponCell
---@field x integer
---@field y integer
---@field z integer
---@field channel string
---@field slot string

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
                        z=part.origin[3]+iz-1, channel=part.palette[char], slot=part.slot}
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
            sparse[cellKey]={x=x,y=y,z=z,channel=cell.channel,slot=slot}
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

--- Preview builds are cooperative: at most 96 cells and one native phase per step.
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

---@param job table
---@param budgetMs number?
---@param clock? fun():number Millisecond clock; optional injectable offline clock.
---@return boolean done
---@return WeaponMesh?
---@return string?
function Builder.StepBuild(job,budgetMs,clock)
    if job.done then return true,job.mesh,job.error end
    budgetMs=math.min(2,math.max(.1,budgetMs or 2))
    clock=clock or function() return GetTime():GetSystemTime() end
    local start=clock()
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
            while job.cursor<=last do
                if clock()-start>=budgetMs then break end
                local cell=cells[job.cursor]
                local x,y,z=cell.x-minimum[1],cell.y-minimum[2],cell.z-minimum[3]
                job.grid:SetSolid(x,y,z,true)
                job.grid:SetVoxelMaterial(x,y,z,Builder.PaletteBase[job.config.weapon]+Builder.ChannelOffset[cell.channel])
                job.cursor=job.cursor+1
            end
            if job.cursor>#cells then job.phase='geometry' end
        elseif job.phase=='geometry' then
            local before=clock()
            job.volume:RebuildGeometry()
            job.nativeMs=clock()-before
            job.phase='publish'
        else
            local mesh={world=job.world,volume=job.volume,node=job.node,blueprint=job.blueprint,
                opaque=job.opaque,fade=job.fade,alpha=1,disposed=false}
            if job.previous and not job.previous.disposed then Builder.SetOpacity(mesh,job.previous.alpha);Builder.Dispose(job.previous)
            else Builder.SetOpacity(mesh,1) end
            job.mesh,job.done=mesh,true
        end
    end)
    local elapsed=math.max(0,clock()-start)
    job.steps=job.steps+1;job.totalMs=job.totalMs+elapsed
    job.maxStepMs=math.max(job.maxStepMs,elapsed);job.overBudget=job.overBudget or elapsed>budgetMs
    if not ok then Builder.CancelBuild(job);job.error=tostring(reason) end
    return job.done,job.mesh,job.error
end
return Builder
