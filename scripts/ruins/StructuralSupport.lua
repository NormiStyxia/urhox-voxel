-- 补齐原生断裂的单连通块边界：底座全毁后，原体积可能仍保持 static。
-- 只检查受到伤害的普通静态物件；时之冻结/回溯和不可破坏建筑不参与。
local M = {}
---@type table<VoxelVolume, boolean>
local pending = {}

---@param volume VoxelVolume
function M.Queue(volume)
    if volume ~= nil then pending[volume] = true end
end

---@param world VoxelPhysicsWorld
---@param volume VoxelVolume
local function Unsupported(world, volume)
    local grid, node = volume:GetGrid(), volume:GetNode()
    local dims, size = grid:GetDimensions(), volume.voxelSize
    -- 使用实心格下表面而非 Volume 原点/包围盒底：底座删空后原点不会变。
    -- 只探测紧邻的承载面，不能把几米以下的地板误当成仍在支撑。
    for x = 0, dims.x - 1 do
        for z = 0, dims.z - 1 do
            for y = 0, dims.y - 1 do
                if grid:IsSolid(x, y, z) and (y == 0 or not grid:IsSolid(x, y - 1, z)) then
                    local face = node:LocalToWorld(Vector3((x + .5) * size, y * size, (z + .5) * size))
                    local hit = world:RaycastGridSingle(Ray(face + Vector3(0, .015, 0), Vector3.DOWN), .075, volume.collisionMask, volume)
                    if hit.hit and hit.volume.collisionMask ~= 0 and hit.volume:IsCollidable()
                        and hit.normal.y > .3 then return false end
                end
            end
        end
    end
    return true
end

---@param world VoxelPhysicsWorld
---@param volume VoxelVolume
local function Release(world, volume)
    local node, grid = volume:GetNode(), volume:GetGrid()
    local dims = grid:GetDimensions()
    local piece = world:CreateVolume(dims.x, dims.y, dims.z, volume.voxelSize, node.worldPosition, node.worldRotation)
    local target = piece:GetGrid()
    for x = 0, dims.x - 1 do
        for y = 0, dims.y - 1 do
            for z = 0, dims.z - 1 do
                if grid:IsSolid(x, y, z) then
                    target:SetSolid(x, y, z, true)
                    target:SetVoxelMaterial(x, y, z, grid:GetVoxelMaterial(x, y, z))
                end
            end
        end
    end
    piece:SetPaletteBank(volume:GetPaletteBank())
    piece.material = volume.material
    piece.destructible, piece.evictable = volume.destructible, volume.evictable
    piece.density, piece.friction, piece.restitution = volume.density, volume.friction, volume.restitution
    piece.collisionLayer, piece.collisionMask = volume.collisionLayer, volume.collisionMask
    piece.collisionGroup = volume.collisionGroup
    piece.gravityFactor, piece.useGravity, piece.ccdEnabled = 1.0, true, true
    piece:GetNode().name = node.name .. "_Fallen"
    local record = {volumeId = volume.volumeId, fragmentId = piece.volumeId,
        voxels = volume:GetSolidCount(), anchored = false, position = node.worldPosition}
    -- 旧体积先清空再注销：外部保留的门堆引用仍能读到正确的剩余数量，
    -- 原位静态碰撞立即移除，不依赖 GC，也不重复 Finalize 同一个 body。
    grid:FillBox(0, 0, 0, dims.x - 1, dims.y - 1, dims.z - 1, false)
    volume.collisionMask = 0
    world:RemoveVolume(volume)
    world:FinalizeVolumeAsDynamic(piece)
    piece:RebuildGeometry()
    piece:Activate()
    print(string.format("StructuralSupport: released volume=%d fragment=%d voxels=%d", record.volumeId, record.fragmentId, record.voxels))
    return record
end

---@param world VoxelPhysicsWorld
---@return table[]
function M.Update(world)
    local work = pending
    pending = {}
    local records = {}
    for volume in pairs(work) do
        if volume:GetScene() == world:GetScene() and volume.destructible and volume:IsStatic()
            and volume.collisionMask ~= 0 and volume:GetSolidCount() > 0 and Unsupported(world, volume) then
            records[#records + 1] = Release(world, volume)
        end
    end
    return records
end

function M.Reset() pending = {} end
return M
