-- Data-model adapter for enemy voxel turnarounds and visual-only runtime pieces.
-- The model owns root-space cells and palette roles. This adapter only allocates
-- an isolated palette bank, builds local volumes, and preserves the destroy path.
local Adapter = {}
local banks = setmetatable({}, {__mode = 'k'})

local function loadModel(modelOrName)
    if type(modelOrName) == 'table' then
        if type(modelOrName.Build) == 'function' then return modelOrName end
        if modelOrName.size and modelOrName.palette and modelOrName.parts then
            return {Build = function() return modelOrName end}
        end
    end
    assert(type(modelOrName) == 'string', 'enemy model or module name expected')
    return require('combat.enemies.models.' .. modelOrName)
end

local function paletteState(world)
    local state = banks[world]
    if state then return state end
    local count = 1
    local ok, value = pcall(function() return world:GetPaletteBankCount() end)
    if ok and type(value) == 'number' then count = math.max(1, value) end
    state = {nextBank = count, byPalette = {}}
    banks[world] = state
    return state
end

local function paletteKey(model)
    local fields = {}
    for _, entry in ipairs(model.palette) do
        local rgb = entry.rgb
        fields[#fields + 1] = table.concat({
            tostring(rgb[1]), tostring(rgb[2]), tostring(rgb[3]),
            tostring(entry.roughness or 0.85), tostring(entry.metallic or 0),
            tostring(entry.emission or 0),
        }, ',')
    end
    return table.concat(fields, ';')
end

local function currentBankCount(world, fallback)
    local ok, value = pcall(function() return world:GetPaletteBankCount() end)
    if ok and type(value) == 'number' then return math.max(fallback, value) end
    return fallback
end

local function bankLimit(world)
    local ok, value = pcall(function() return world:GetPaletteBankLimit() end)
    if ok and type(value) == 'number' then return value end
    return nil
end

local function applyPalette(world, model, bank)
    for slot, entry in ipairs(model.palette) do
        local rgb = entry.rgb
        local index = bank * 256 + slot
        world:SetPaletteEntry(index, Color(rgb[1] / 255, rgb[2] / 255, rgb[3] / 255), 100)
        local emission = entry.emission or 0
        world:SetPaletteEntryPBR(index, entry.roughness or 0.85, entry.metallic or 0, 0.5,
            Color(rgb[1] / 255, rgb[2] / 255, rgb[3] / 255, emission))
    end
end

local function bounds(cells)
    local loX, loY, loZ = math.huge, math.huge, math.huge
    local hiX, hiY, hiZ = -math.huge, -math.huge, -math.huge
    for _, cell in ipairs(cells) do
        loX, loY, loZ = math.min(loX, cell[1]), math.min(loY, cell[2]), math.min(loZ, cell[3])
        hiX, hiY, hiZ = math.max(hiX, cell[1]), math.max(hiY, cell[2]), math.max(hiZ, cell[3])
    end
    return loX, loY, loZ, hiX, hiY, hiZ
end

---@param world VoxelPhysicsWorld
---@param parent Node
---@param modelOrName table|string model table or module basename
---@return table visual
function Adapter.Build(world, parent, modelOrName)
    local model = loadModel(modelOrName)
    local data = model.Build()
    assert(data and data.size and data.palette and data.parts, 'invalid enemy voxel model')
    assert(#data.palette <= 6, 'enemy model palette exceeds six colours')
    local state = paletteState(world)
    local key = paletteKey(data)
    local bank = state.byPalette[key]
    if bank == nil then
        state.nextBank = currentBankCount(world, state.nextBank)
        local limit = bankLimit(world)
        if limit and state.nextBank >= limit then
            error('enemy model palette banks exhausted: '..state.nextBank..'/'..limit)
        end
        bank = state.nextBank
        state.nextBank = bank + 1
        applyPalette(world, data, bank)
        -- Publish only after every RGB/PBR slot succeeds. A failed PBR call
        -- leaves the bank unclaimed so a retry cannot reuse a half-written key.
        state.byPalette[key] = bank
    end

    local root = parent:CreateChild('enemy_model_visual')
    local visual = {root = root, world = world, bank = bank, parts = {}, data = data, removed = false}
    local ok, reason = pcall(function()
        for _, part in ipairs(data.parts) do
            assert(#part.cells > 0, 'empty enemy model part: ' .. tostring(part.id))
            local minX, minY, minZ, maxX, maxY, maxZ = bounds(part.cells)
            local volume = world:CreateVolume(maxX - minX + 1, maxY - minY + 1, maxZ - minZ + 1,
                data.size, Vector3.ZERO, Quaternion())
            -- Keep the authored pivot in meters on the handle.  The visual
            -- driver reparents this node below its neutral body pose, so it
            -- must restore the model's original center before applying a
            -- posePart delta.  Copy the values to avoid sharing the model's
            -- mutable table with runtime transforms.
            local pivot = part.pivot or {0, 0, 0}
            local handle = {id = part.id, volume = volume,
                pivotPosition = {pivot[1] or 0, pivot[2] or 0, pivot[3] or 0}}
            visual.parts[#visual.parts + 1] = handle
            volume:SetPaletteBank(bank)
            local grid = volume:GetGrid()
            for _, cell in ipairs(part.cells) do
                local x, y, z = cell[1] - minX, cell[2] - minY, cell[3] - minZ
                grid:SetSolid(x, y, z, true)
                grid:SetVoxelMaterial(x, y, z, cell[4])
            end
            volume.destructible, volume.evictable = false, false
            volume.collisionLayer, volume.collisionMask = 0, 0
            volume:RebuildGeometry()
            local pivotNode = root:CreateChild(part.id .. '_pivot')
            pivotNode.position = Vector3(pivot[1], pivot[2], pivot[3])
            local node = volume:GetNode()
            node:SetParent(pivotNode)
            node.position = Vector3(minX * data.size - pivot[1], minY * data.size - pivot[2],
                minZ * data.size - pivot[3])
            node.rotation = Quaternion()
            handle.node, handle.pivot = node, pivotNode
        end
    end)
    if not ok then
        for _, part in ipairs(visual.parts) do world:RemoveVolume(part.volume) end
        root:Remove()
        error(reason, 0)
    end
    return visual
end

---@param visual table returned by Adapter.Build
function Adapter.Destroy(visual)
    if not visual or visual.removed then return end
    visual.removed = true
    for _, part in ipairs(visual.parts) do
        visual.world:RemoveVolume(part.volume)
    end
    visual.root:Remove()
    visual.parts = {}
end

return Adapter
