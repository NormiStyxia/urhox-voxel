-- 实体树的外壳网格：按面合并同色格，不生成内部盒面，也不保留上万个临时几何对象。
local M = {}
local floor = math.floor

---@param grid {size:number, cells:table<string, HomeTreeCell?>, order:HomeTreeCell[]}
---@param parent Node
---@param name string
---@param palette Color[]
---@param material Material
---@return integer, integer
function M.Build(grid, parent, name, palette, material)
    local cells, order, size = grid.cells, grid.order, grid.size
    if #order == 0 then return 0, 0 end
    local node = parent:CreateChild(name)
    local mesh = node:CreateComponent("CustomGeometry")
    mesh:BeginGeometry(0, TRIANGLE_LIST)
    local quads, covered = 0, 0
    local function key(x, y, z) return x .. ":" .. y .. ":" .. z end
    -- 循环坐标保证 U × V 指向对应轴正方向。
    local function coordinates(axis, p, u, v)
        if axis == 1 then return p, u, v end
        if axis == 2 then return v, p, u end
        return u, v, p
    end
    local function point(axis, p, u, v)
        local x, y, z = coordinates(axis, p, u, v)
        return Vector3(x * size, y * size, z * size)
    end
    for axis = 1, 3 do
        for _, sign in ipairs({ -1, 1 }) do
            -- 每层只收集真正朝空气的面；相邻实心格即使不同色也不画内部面。
            local planes = {}
            for _, cell in ipairs(order) do
                local p, u, v
                if axis == 1 then p, u, v = cell.x, cell.y, cell.z
                elseif axis == 2 then p, u, v = cell.y, cell.z, cell.x
                else p, u, v = cell.z, cell.x, cell.y end
                local x, y, z = coordinates(axis, p + sign, u, v)
                if not cells[key(x, y, z)] then
                    local layer = planes[p]
                    if not layer then layer = {}; planes[p] = layer end
                    local row = layer[v]
                    if not row then row = {}; layer[v] = row end
                    row[u] = cell.tone * 256 + cell.ao
                end
            end
            local levels = {}
            for p in pairs(planes) do levels[#levels + 1] = p end
            table.sort(levels)
            for _, p in ipairs(levels) do
                local layer = planes[p]
                local rows = {}
                for v in pairs(layer) do rows[#rows + 1] = v end
                table.sort(rows)
                for _, v in ipairs(rows) do
                    local row = layer[v]
                    local columns = {}
                    for u in pairs(row) do columns[#columns + 1] = u end
                    table.sort(columns)
                    for _, u in ipairs(columns) do
                        local code = row[u]
                        if code then
                            local width, height = 1, 1
                            while row[u + width] == code do width = width + 1 end
                            while layer[v + height] do
                                local full = true
                                for j = 0, width - 1 do
                                    if layer[v + height][u + j] ~= code then full = false; break end
                                end
                                if not full then break end
                                height = height + 1
                            end
                            for i = 0, height - 1 do
                                for j = 0, width - 1 do layer[v + i][u + j] = nil end
                            end
                            local at = p + (sign > 0 and 1 or 0)
                            local corners = { point(axis, at, u, v), point(axis, at, u + width, v),
                                point(axis, at, u + width, v + height), point(axis, at, u, v + height) }
                            local normal = axis == 1 and Vector3(sign, 0, 0)
                                or (axis == 2 and Vector3(0, sign, 0) or Vector3(0, 0, sign))
                            local tint = assert(palette[floor(code / 256)])
                            local color = Color(tint.r, tint.g, tint.b, (code % 256) / 255)
                            local indices = sign > 0 and { 1, 2, 3, 1, 3, 4 } or { 1, 3, 2, 1, 4, 3 }
                            for _, index in ipairs(indices) do
                                mesh:DefineVertex(corners[index])
                                mesh:DefineNormal(normal)
                                mesh:DefineColor(color)
                            end
                            quads, covered = quads + 1, covered + width * height
                        end
                    end
                end
                planes[p] = nil
            end
        end
    end
    mesh:Commit()
    mesh:SetMaterial(material)
    mesh.castShadows = true
    return quads, covered
end
return M
