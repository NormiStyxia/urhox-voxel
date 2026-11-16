-- Compatibility for engines whose ApplyDamage return value is not the removed
-- voxel count. VoxelDamaged is synchronous and carries the actual count. Observe
-- is forwarded by RuinsPuzzles' existing world handler: do not install another
-- global subscription and replace its gate-progress handler.
local M = {}
---@type {world: VoxelPhysicsWorld, volume: VoxelVolume?, removed: integer, observed: boolean}?
local current

---@param world VoxelPhysicsWorld
---@param data VoxelDamagedEventData
function M.Observe(world, data)
    local scope = current
    if not scope or scope.world ~= world then return end
    -- Compare identities only. Native callbacks may split/remove the volume;
    -- never retain a grid or query the old volume after applying damage.
    if scope.volume and data:GetPtr('Volume') ~= scope.volume then return end
    scope.removed = scope.removed + math.max(0, data:GetInt('Removed'))
    scope.observed = true
end

local function Apply(world, volume, fn, ...)
    local parent = current
    local scope = {world=world, volume=volume, removed=0, observed=false}
    current = scope
    local ok, raw = pcall(fn, world, ...)
    current = parent -- also restore on errors and nested damage calls
    if not ok then error(raw, 0) end
    -- Retain the documented return contract for callers without an event bridge
    -- and future engines. An observed event is authoritative, never added twice.
    return scope.observed and scope.removed or raw, raw
end

---@param world VoxelPhysicsWorld
---@param volume VoxelVolume
---@param center Vector3
---@param radius number
---@param power number
---@return integer removed
---@return integer nativeReturn
function M.Volume(world, volume, center, radius, power)
    return Apply(world, volume, world.ApplyDamage, volume, center, radius, power)
end

---@param world VoxelPhysicsWorld
---@param center Vector3
---@param radius number
---@param power number
---@return integer removed
---@return integer nativeReturn
function M.AtWorldPoint(world, center, radius, power)
    return Apply(world, nil, world.ApplyDamageAtWorldPoint, center, radius, power)
end

return M
