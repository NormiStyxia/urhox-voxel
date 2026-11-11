-- ====================================================================
-- VoxelBrush.lua — 在一个（可绕 Y 旋转的）局部坐标框里画体素，再一次性定型
--
--   local b = Brush.New(world, { origin = Vector3, yaw = 0, min = {x,y,z}, max = {x,y,z}, size = 0.25 })
--   b:Box(x0,y0,z0, x1,y1,z1, mat)          局部米坐标（含 cell 中心落在盒内的格）
--   b:Shape(x0,y0,z0, x1,y1,z1, fn)          fn(cx,cy,cz, i,j,k) → 材质 / nil（不改） / false（挖空）
--   b:Finish{ destructible, dynamic, visual } → VoxelVolume
--
-- mat 可以是槽位号，也可以是 function(cx,cy,cz,i,j,k) → 槽位（随机配色 / 纹样）。
-- 体积原点在局部 min 角；旋转后的世界位置由 origin + R * min 给出。
-- ====================================================================

local M = {}

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

---@class VoxelBrush
---@field world VoxelPhysicsWorld
---@field volume VoxelVolume
---@field grid VoxelGrid
---@field s number
---@field nx integer
---@field ny integer
---@field nz integer
---@field lmin number[]
---@field origin Vector3
---@field rot Quaternion
---@field yaw number
---@field count integer
local B = {}
B.__index = B

---@param world VoxelPhysicsWorld
function M.New(world, o)
    local self = setmetatable({}, B)
    self.world = world
    self.s = o.size or 0.25
    local s = self.s
    local lmin = { floor(o.min[1] / s) * s, floor(o.min[2] / s) * s, floor(o.min[3] / s) * s }
    self.lmin = lmin
    self.nx = math.tointeger(max(1, ceil((o.max[1] - lmin[1]) / s - 1e-6))) or 1
    self.ny = math.tointeger(max(1, ceil((o.max[2] - lmin[2]) / s - 1e-6))) or 1
    self.nz = math.tointeger(max(1, ceil((o.max[3] - lmin[3]) / s - 1e-6))) or 1
    self.origin = o.origin or Vector3(0, 0, 0)
    self.yaw = o.yaw or 0
    self.rot = Quaternion(self.yaw, Vector3.UP)
    local pos = self.origin + self.rot * Vector3(lmin[1], lmin[2], lmin[3])
    self.volume = world:CreateVolume(self.nx, self.ny, self.nz, s, pos, self.rot)
    self.grid = self.volume:GetGrid()
    self.count = 0
    return self
end

-- 局部米坐标 → 格索引范围（cell 中心落在 [a,b] 内）
function B:Range(a, b, axis)
    local s, lo = self.s, self.lmin[axis]
    local n = (axis == 1 and self.nx) or (axis == 2 and self.ny) or self.nz
    local i0 = max(0, ceil((a - lo) / s - 0.5 - 1e-6))
    local i1 = min(n - 1, floor((b - lo) / s - 0.5 + 1e-6))
    return math.tointeger(i0) or 0, math.tointeger(i1) or -1
end

function B:Center(i, j, k)
    local s, lo = self.s, self.lmin
    return lo[1] + (i + 0.5) * s, lo[2] + (j + 0.5) * s, lo[3] + (k + 0.5) * s
end

function B:Set(i, j, k, mat)
    local g = self.grid
    if mat == false then
        g:SetSolid(i, j, k, false)
    else
        g:SetSolid(i, j, k, true)
        g:SetVoxelMaterial(i, j, k, mat)
    end
end

-- 局部坐标单点（越界忽略）
function B:Point(x, y, z, mat)
    local s, lo = self.s, self.lmin
    local i, j, k = floor((x - lo[1]) / s), floor((y - lo[2]) / s), floor((z - lo[3]) / s)
    if i < 0 or j < 0 or k < 0 or i >= self.nx or j >= self.ny or k >= self.nz then return end
    self:Set(i, j, k, mat)
end

function B:Box(x0, y0, z0, x1, y1, z1, mat)
    local i0, i1 = self:Range(min(x0, x1), max(x0, x1), 1)
    local j0, j1 = self:Range(min(y0, y1), max(y0, y1), 2)
    local k0, k1 = self:Range(min(z0, z1), max(z0, z1), 3)
    if i1 < i0 or j1 < j0 or k1 < k0 then return end
    local g = self.grid
    if type(mat) == "number" then
        g:FillBox(i0, j0, k0, i1, j1, k1, true)
        g:PaintBox(i0, j0, k0, i1, j1, k1, mat)
    elseif mat == false then
        g:FillBox(i0, j0, k0, i1, j1, k1, false)
    else
        for i = i0, i1 do
            for j = j0, j1 do
                for k = k0, k1 do
                    local cx, cy, cz = self:Center(i, j, k)
                    local m = mat(cx, cy, cz, i, j, k)
                    if m ~= nil then self:Set(i, j, k, m) end
                end
            end
        end
    end
end

function B:Carve(x0, y0, z0, x1, y1, z1) self:Box(x0, y0, z0, x1, y1, z1, false) end

-- 通用形状：fn(cx,cy,cz,i,j,k) → 材质 / false / nil
function B:Shape(x0, y0, z0, x1, y1, z1, fn)
    local i0, i1 = self:Range(min(x0, x1), max(x0, x1), 1)
    local j0, j1 = self:Range(min(y0, y1), max(y0, y1), 2)
    local k0, k1 = self:Range(min(z0, z1), max(z0, z1), 3)
    for i = i0, i1 do
        for k = k0, k1 do
            for j = j0, j1 do
                local cx, cy, cz = self:Center(i, j, k)
                local m = fn(cx, cy, cz, i, j, k)
                if m ~= nil then self:Set(i, j, k, m) end
            end
        end
    end
end

local function Resolve(mat, cx, cy, cz, i, j, k)
    if type(mat) == "function" then return mat(cx, cy, cz, i, j, k) end
    return mat
end

-- 竖直圆柱（cx,cz 圆心，半径 r，y0..y1）
function B:Cylinder(cx, cz, r, y0, y1, mat)
    local r2 = r * r
    self:Shape(cx - r, y0, cz - r, cx + r, y1, cz + r, function(x, y, z, i, j, k)
        local dx, dz = x - cx, z - cz
        if dx * dx + dz * dz <= r2 then return Resolve(mat, x, y, z, i, j, k) end
    end)
end

function B:Sphere(cx, cy, cz, r, mat)
    local r2 = r * r
    self:Shape(cx - r, cy - r, cz - r, cx + r, cy + r, cz + r, function(x, y, z, i, j, k)
        local dx, dy, dz = x - cx, y - cy, z - cz
        if dx * dx + dy * dy + dz * dz <= r2 then return Resolve(mat, x, y, z, i, j, k) end
    end)
end

function B:Ellipsoid(cx, cy, cz, rx, ry, rz, mat)
    self:Shape(cx - rx, cy - ry, cz - rz, cx + rx, cy + ry, cz + rz, function(x, y, z, i, j, k)
        local dx, dy, dz = (x - cx) / rx, (y - cy) / ry, (z - cz) / rz
        if dx * dx + dy * dy + dz * dz <= 1.0 then return Resolve(mat, x, y, z, i, j, k) end
    end)
end

function B:IsSolidLocal(x, y, z)
    local s, lo = self.s, self.lmin
    local i, j, k = floor((x - lo[1]) / s), floor((y - lo[2]) / s), floor((z - lo[3]) / s)
    if i < 0 or j < 0 or k < 0 or i >= self.nx or j >= self.ny or k >= self.nz then return false end
    return self.grid:IsSolid(i, j, k)
end

-- 读出全部实心体素：{ {i,j,k,mat}, ... }（TimeObject 用）
function B:Collect()
    local list = {}
    local g = self.grid
    for i = 0, self.nx - 1 do
        for j = 0, self.ny - 1 do
            for k = 0, self.nz - 1 do
                if g:IsSolid(i, j, k) then
                    list[#list + 1] = { i, j, k, math.tointeger(g:GetVoxelMaterial(i, j, k)) or 0 }
                end
            end
        end
    end
    return list
end

-- 定型：o = { destructible, dynamic, visual, density, keepEmpty }
function B:Finish(o)
    o = o or {}
    local v = self.volume
    if v:GetSolidCount() == 0 and not o.keepEmpty then
        self.world:RemoveVolume(v)
        return nil
    end
    v.destructible = o.destructible == true
    v.evictable = false
    if o.visual then
        -- 不定型：只渲染、无物理体（悬浮装饰 / 回溯中的残片）
    elseif o.dynamic then
        v.density = o.density or 2200.0
        self.world:FinalizeVolumeAsDynamic(v)
    else
        self.world:FinalizeVolume(v)
    end
    v:RebuildGeometry()
    return v
end

return M
