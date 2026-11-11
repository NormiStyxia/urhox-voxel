-- ====================================================================
-- DragonSkin.lua — 龙的鳞片外皮：把每个部件的体素数据重建成「倒角网格」，再配鳞片着色
--
-- 网格：二值 Surface Nets。每个体素角点（被 2×2×2 个体素共享）若内外混合，就放一个顶点，
--   位置 = 12 条棱上实心 / 空心交界中点的平均；每个外露体素面连成一个四边形。
--   效果是方块的棱角被倒成斜面，外形保留体素的块面感，但不再是一格格正方体。
--   之后做 SMOOTH 次拉普拉斯平滑（默认 1 次，不要太圆）。
-- 颜色：每个四边形用它所属体素的调色板颜色，顶点不跨颜色共享 → 眼睛 / 口腔 / 腹甲边界保持清晰；
--   法线按共享角点平滑，光照是连续的。
-- 着色：DragonSkin.shader（鱼鳞 / 腹甲横纹 / 素面三类，见 UV.x）。
-- 原 VoxelVolume 保留（隐藏），破坏系统以后照样用 parts[bone].volume。
-- ====================================================================

local Spec = require("dragon.DragonSpec")

local M = {}
M.SHADER = "Shaders/BLGL/DragonSkin.shader"
M.SMOOTH = 1         -- 平滑次数
M.SMOOTH_K = 0.4    -- 每次向邻点平均靠拢的比例

-- 表面类型（写进 UV.x）：0 鱼鳞，1 腹甲横纹，2 素面（眼、爪、口、角刺）
local KIND = {}
do
    local P = Spec.PAL
    for _, k in ipairs({ P.BLUE_L, P.BLUE_M, P.BLUE_D, P.BLUE_P, P.BLUE_L2 }) do KIND[k] = 0 end
    for _, k in ipairs({ P.WHITE, P.WHITE_S }) do KIND[k] = 1 end
end
M.KIND = KIND

function M.CreateMaterial()
    local mat = Material:new()
    if not mat:SetSurfaceShader(M.SHADER) then print("DragonSkin: failed to load " .. M.SHADER) end
    return mat
end

-- 6 个面方向：{ 法线轴, 符号 }
local DIRS = { { 1, 1 }, { 1, -1 }, { 2, 1 }, { 2, -1 }, { 3, 1 }, { 3, -1 } }
-- 面上 4 个角点在另外两轴上的偏移（环绕顺序）
local QUAD = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } }

-- voxels：{ {x, y, z, mat}, ... }，x/y/z 为体积内 0 起的格坐标；s 体素边长
-- colorOf(mat) → r, g, b, emissive
---@param parent Node
---@param material Material
---@return Node|nil
function M.Build(parent, name, voxels, dims, s, material, colorOf, position)
    if #voxels == 0 then return nil end
    local X, Y = dims[1] + 2, dims[2] + 2
    local function VK(x, y, z) return (x + 1) + (y + 1) * X + (z + 1) * X * Y end
    local occ = {}
    for _, v in ipairs(voxels) do occ[VK(v[1], v[2], v[3])] = v[4] end

    -- 角点 key（0..dims）
    local CX, CY = dims[1] + 1, dims[2] + 1
    local function CK(x, y, z) return x + y * CX + z * CX * CY end
    local cpos = {}  -- key → {x, y, z}（格单位）
    local function Corner(cx, cy, cz)
        local key = CK(cx, cy, cz)
        local p = cpos[key]
        if p ~= nil then return key end
        local sx, sy, sz, n = 0, 0, 0, 0
        -- 12 条棱：沿 x 的 4 条、沿 y 的 4 条、沿 z 的 4 条（端点为 2×2×2 体素中心）
        for a = 0, 1 do
            for b = 0, 1 do
                local y, z = cy - 1 + a, cz - 1 + b
                if (occ[VK(cx - 1, y, z)] ~= nil) ~= (occ[VK(cx, y, z)] ~= nil) then
                    sx, sy, sz, n = sx + cx, sy + y + 0.5, sz + z + 0.5, n + 1
                end
                local x = cx - 1 + a
                z = cz - 1 + b
                if (occ[VK(x, cy - 1, z)] ~= nil) ~= (occ[VK(x, cy, z)] ~= nil) then
                    sx, sy, sz, n = sx + x + 0.5, sy + cy, sz + z + 0.5, n + 1
                end
                y = cy - 1 + b
                if (occ[VK(x, y, cz - 1)] ~= nil) ~= (occ[VK(x, y, cz)] ~= nil) then
                    sx, sy, sz, n = sx + x + 0.5, sy + y + 0.5, sz + cz, n + 1
                end
            end
        end
        if n == 0 then cpos[key] = { cx, cy, cz } else cpos[key] = { sx / n, sy / n, sz / n } end
        return key
    end

    -- 外露面 → 四边形
    local quads = {}  -- { k1, k2, k3, k4, axis, sign, mat }
    local nbr = {}    -- 角点邻接（平滑用）
    local function Link(a, b)
        local la = nbr[a]
        if la == nil then la = {}; nbr[a] = la end
        la[b] = true
    end
    for _, v in ipairs(voxels) do
        local x, y, z, m = v[1], v[2], v[3], v[4]
        for _, d in ipairs(DIRS) do
            local ax, sg = d[1], d[2]
            local nx, ny, nz = x, y, z
            if ax == 1 then nx = x + sg elseif ax == 2 then ny = y + sg else nz = z + sg end
            if occ[VK(nx, ny, nz)] == nil then
                local ks = {}
                for qi, q in ipairs(QUAD) do
                    local c = { x, y, z }
                    c[ax] = c[ax] + ((sg > 0) and 1 or 0)
                    local b1, b2 = (ax % 3) + 1, ((ax + 1) % 3) + 1
                    c[b1] = c[b1] + q[1]
                    c[b2] = c[b2] + q[2]
                    ks[qi] = Corner(c[1], c[2], c[3])
                end
                quads[#quads + 1] = { ks[1], ks[2], ks[3], ks[4], ax, sg, m }
                for qi = 1, 4 do Link(ks[qi], ks[(qi % 4) + 1]); Link(ks[(qi % 4) + 1], ks[qi]) end
            end
        end
    end

    -- 拉普拉斯平滑（只动角点位置）
    for _ = 1, M.SMOOTH do
        local nextPos = {}
        for key, p in pairs(cpos) do
            local l = nbr[key]
            if l ~= nil then
                local sx, sy, sz, n = 0, 0, 0, 0
                for k2 in pairs(l) do
                    local q = cpos[k2]
                    sx, sy, sz, n = sx + q[1], sy + q[2], sz + q[3], n + 1
                end
                local k = M.SMOOTH_K
                nextPos[key] = { p[1] + (sx / n - p[1]) * k, p[2] + (sy / n - p[2]) * k, p[3] + (sz / n - p[3]) * k }
            else
                nextPos[key] = p
            end
        end
        cpos = nextPos
    end

    -- 角点法线：累加四边形面积加权法线（朝外：与面方向同侧）
    local cn = {}
    local qn = {}
    for i, q in ipairs(quads) do
        local p1, p2, p3, p4 = cpos[q[1]], cpos[q[2]], cpos[q[3]], cpos[q[4]]
        local ax, ay, az = p3[1] - p1[1], p3[2] - p1[2], p3[3] - p1[3]
        local bx, by, bz = p4[1] - p2[1], p4[2] - p2[2], p4[3] - p2[3]
        local nx, ny, nz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
        local face = { 0, 0, 0 }
        face[q[5]] = q[6]
        if nx * face[1] + ny * face[2] + nz * face[3] < 0 then nx, ny, nz = -nx, -ny, -nz end
        qn[i] = { nx, ny, nz }
        for j = 1, 4 do
            local k = q[j]
            local a = cn[k]
            if a == nil then cn[k] = { nx, ny, nz } else a[1], a[2], a[3] = a[1] + nx, a[2] + ny, a[3] + nz end
        end
    end

    local node = parent:CreateChild(name)
    node.position = position
    local geom = node:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, TRIANGLE_LIST)
    local ccache = {}
    local function Emit(key, col, uv)
        local p, n = cpos[key], cn[key]
        local l = math.sqrt(n[1] * n[1] + n[2] * n[2] + n[3] * n[3])
        if l < 1e-9 then l = 1 end
        geom:DefineVertex(Vector3(p[1] * s, p[2] * s, p[3] * s))
        geom:DefineNormal(Vector3(n[1] / l, n[2] / l, n[3] / l))
        geom:DefineColor(col)
        geom:DefineTexCoord(uv)
    end
    for _, q in ipairs(quads) do
        local m = q[7]
        local cc = ccache[m]
        if cc == nil then
            local r, g, b, e = colorOf(m)
            cc = { Color(r, g, b, e), Vector2(KIND[m] or 2, s) }
            ccache[m] = cc
        end
        local col, uv = cc[1], cc[2]
        Emit(q[1], col, uv); Emit(q[2], col, uv); Emit(q[3], col, uv)
        Emit(q[1], col, uv); Emit(q[3], col, uv); Emit(q[4], col, uv)
    end
    geom:Commit()
    geom:SetMaterial(material)
    geom.castShadows = true
    return node
end

return M
