-- ====================================================================
-- DragonSculpt.lua — SDF 体块 → 分骨骼体素集合（纯 Lua 数值运算）
--
-- 整条龙在「静止参考姿态」下用一组带骨骼标签的 SDF 体块描述（椭球 / 锥形胶囊 /
-- 圆角盒 / 鳍片 / 菱形片）。体素化时：
--   1. 全局形体 = 所有体块的平滑并集，体素中心 SDF ≤ 0 即实心；
--   2. 归属 = 原始距离最小的体块所属骨骼（每个体素只属于一根骨骼，静止时零重叠）；
--   3. 关节搭接 = 该骨骼自身体块内部、且六邻居全实心的「深层」体素，额外复制一份给
--      该骨骼。它们在静止姿态下被外表面包住看不见，关节弯曲时填补裂缝。
-- 颜色由体块的 colorer 按世界坐标计算，重复体素颜色一致。
-- 纯数字运算，不在循环里创建 Vector3。
-- ====================================================================

local M = {}

local sqrt, abs, max, min, floor = math.sqrt, math.abs, math.max, math.min, math.floor

-- 小整数哈希 → [0,1)
function M.Hash3(i, j, k)
    local h = (i * 73856093) ~ (j * 19349663) ~ (k * 83492791)
    h = (h ~ (h >> 13)) * 1274126177
    h = h ~ (h >> 16)
    return (h & 0xffff) / 65536.0
end

-- 欧拉角（度）→ 3x3 行矩阵，顺序与 DragonRig 一致：R = Rz * Ry * Rx
function M.RotMatrix(ex, ey, ez)
    local rx, ry, rz = math.rad(ex or 0), math.rad(ey or 0), math.rad(ez or 0)
    local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    -- UrhoX 左手系：Rx 把 +Y 转向 +Z，Ry 把 +Z 转向 +X，Rz 把 +X 转向 +Y
    local Rx = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
    local Ry = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
    local Rz = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
    local function mul(a, b)
        local r = {}
        for i = 0, 2 do
            for j = 0, 2 do
                r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
            end
        end
        return r
    end
    return mul(Rz, mul(Ry, Rx))
end

-- ---------------------------------------------------------------- SDF
local function sdEllipsoid(px, py, pz, rx, ry, rz)
    local k0 = sqrt((px / rx) ^ 2 + (py / ry) ^ 2 + (pz / rz) ^ 2)
    if k0 < 1e-6 then return -min(rx, ry, rz) end
    local k1 = sqrt((px / (rx * rx)) ^ 2 + (py / (ry * ry)) ^ 2 + (pz / (rz * rz)) ^ 2)
    return k0 * (k0 - 1.0) / k1
end

local function sdBox(px, py, pz, hx, hy, hz, r)
    local qx, qy, qz = abs(px) - hx + r, abs(py) - hy + r, abs(pz) - hz + r
    local ox, oy, oz = max(qx, 0), max(qy, 0), max(qz, 0)
    return sqrt(ox * ox + oy * oy + oz * oz) + min(max(qx, qy, qz), 0.0) - r
end

-- 锥形胶囊（两端半径不同的圆锥台 + 球帽，近似距离）
local function sdCone(px, py, pz, p)
    local ax, ay, az = px - p.ax, py - p.ay, pz - p.az
    local t = (ax * p.dx + ay * p.dy + az * p.dz) * p.invLen2
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local cx, cy, cz = ax - p.dx * t, ay - p.dy * t, az - p.dz * t
    return sqrt(cx * cx + cy * cy + cz * cz) - (p.ra + (p.rb - p.ra) * t)
end

-- 2D 三角形有符号距离（顶点逆时针或顺时针均可）
local function sdTri2(px, py, ax, ay, bx, by, cx, cy)
    local e0x, e0y, e1x, e1y, e2x, e2y = bx - ax, by - ay, cx - bx, cy - by, ax - cx, ay - cy
    local v0x, v0y, v1x, v1y, v2x, v2y = px - ax, py - ay, px - bx, py - by, px - cx, py - cy
    local function seg(vx, vy, ex, ey)
        local t = (vx * ex + vy * ey) / (ex * ex + ey * ey)
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
        local qx, qy = vx - ex * t, vy - ey * t
        return qx * qx + qy * qy
    end
    local d = min(seg(v0x, v0y, e0x, e0y), seg(v1x, v1y, e1x, e1y), seg(v2x, v2y, e2x, e2y))
    local s = e0x * e2y - e0y * e2x
    local s0 = s * (v0x * e0y - v0y * e0x)
    local s1 = s * (v1x * e1y - v1y * e1x)
    local s2 = s * (v2x * e2y - v2y * e2x)
    -- 按绕向归一后，三条边都在内侧即在内部（iq 的 sdTriangle）
    local inside = (s0 >= 0 and s1 >= 0 and s2 >= 0)
    local dd = sqrt(d)
    return inside and -dd or dd
end

-- 2D 菱形（半轴 a, b）
local function sdRhombus2(px, py, a, b)
    px, py = abs(px), abs(py)
    -- 到边 (a,0)-(0,b) 的有符号距离
    local nx, ny = b, a
    local l = sqrt(nx * nx + ny * ny)
    return (px * nx + py * ny - a * b) / l
end

local function extrude(d2, w, halfT)
    local dw = abs(w) - halfT
    if d2 < 0 and dw < 0 then return max(d2, dw) end
    local a, b = max(d2, 0), max(dw, 0)
    return sqrt(a * a + b * b)
end

-- 预处理体块：建局部坐标所需的常量、AABB
function M.Prepare(prim)
    local t = prim.type
    if prim.rot ~= nil then
        prim.m = M.RotMatrix(prim.rot[1], prim.rot[2], prim.rot[3])
    end
    local ext = 0.5
    if t == "ellipsoid" then
        prim.cx, prim.cy, prim.cz = prim.c[1], prim.c[2], prim.c[3]
        ext = max(prim.r[1], prim.r[2], prim.r[3])
        if prim.m == nil then
            prim.bmin = { prim.cx - prim.r[1], prim.cy - prim.r[2], prim.cz - prim.r[3] }
            prim.bmax = { prim.cx + prim.r[1], prim.cy + prim.r[2], prim.cz + prim.r[3] }
        end
    elseif t == "box" then
        prim.cx, prim.cy, prim.cz = prim.c[1], prim.c[2], prim.c[3]
        ext = sqrt(prim.h[1] ^ 2 + prim.h[2] ^ 2 + prim.h[3] ^ 2)
        prim.round = prim.round or 0.0
    elseif t == "cone" then
        prim.ax, prim.ay, prim.az = prim.a[1], prim.a[2], prim.a[3]
        prim.dx, prim.dy, prim.dz = prim.b[1] - prim.a[1], prim.b[2] - prim.a[2], prim.b[3] - prim.a[3]
        local l2 = prim.dx ^ 2 + prim.dy ^ 2 + prim.dz ^ 2
        prim.invLen2 = l2 > 1e-9 and 1.0 / l2 or 0.0
        prim.ra, prim.rb = prim.r[1], prim.r[2]
        local rr = max(prim.ra, prim.rb)
        prim.bmin = { min(prim.a[1], prim.b[1]) - rr, min(prim.a[2], prim.b[2]) - rr, min(prim.a[3], prim.b[3]) - rr }
        prim.bmax = { max(prim.a[1], prim.b[1]) + rr, max(prim.a[2], prim.b[2]) + rr, max(prim.a[3], prim.b[3]) + rr }
    elseif t == "fin" then
        -- 鳍片：base 为底边中点，u = 沿底边方向（指向后），v = 高度方向，厚度沿 u×v
        prim.cx, prim.cy, prim.cz = prim.base[1], prim.base[2], prim.base[3]
        local ux, uy, uz = prim.u[1], prim.u[2], prim.u[3]
        local ul = sqrt(ux * ux + uy * uy + uz * uz)
        ux, uy, uz = ux / ul, uy / ul, uz / ul
        local vx, vy, vz = prim.v[1], prim.v[2], prim.v[3]
        -- 正交化 v
        local dp = vx * ux + vy * uy + vz * uz
        vx, vy, vz = vx - dp * ux, vy - dp * uy, vz - dp * uz
        local vl = sqrt(vx * vx + vy * vy + vz * vz)
        vx, vy, vz = vx / vl, vy / vl, vz / vl
        prim.fu = { ux, uy, uz }
        prim.fv = { vx, vy, vz }
        prim.fw = { uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx }
        prim.sweep = prim.sweep or 0.0
        prim.thick = prim.thick or 0.12
        ext = max(prim.len * 0.5 + abs(prim.sweep), prim.h) + prim.thick
    elseif t == "rhombus" then
        -- 菱形片：中心 c，长轴 u（半长 a），短轴 v（半长 b），厚度沿 u×v
        prim.cx, prim.cy, prim.cz = prim.c[1], prim.c[2], prim.c[3]
        local u, v = prim.u, prim.v
        prim.fu, prim.fv = u, v
        prim.fw = { u[2] * v[3] - u[3] * v[2], u[3] * v[1] - u[1] * v[3], u[1] * v[2] - u[2] * v[1] }
        ext = max(prim.a, prim.b) + prim.thick
    end
    if prim.bmin == nil then
        local cx, cy, cz = prim.cx, prim.cy, prim.cz
        prim.bmin = { cx - ext, cy - ext, cz - ext }
        prim.bmax = { cx + ext, cy + ext, cz + ext }
    end
    local pad = (prim.k or 0.0) + (prim.plate or 0.0) + 0.02
    for i = 1, 3 do
        prim.bmin[i] = prim.bmin[i] - pad
        prim.bmax[i] = prim.bmax[i] + pad
    end
    return prim
end

-- 体块原始距离
function M.Eval(prim, x, y, z)
    local t = prim.type
    if t == "cone" then return sdCone(x, y, z, prim) end
    local px, py, pz = x - prim.cx, y - prim.cy, z - prim.cz
    local m = prim.m
    if m ~= nil then
        -- 逆旋转 = 转置
        px, py, pz = m[1] * px + m[4] * py + m[7] * pz, m[2] * px + m[5] * py + m[8] * pz, m[3] * px + m[6] * py + m[9] * pz
    end
    if t == "ellipsoid" then
        return sdEllipsoid(px, py, pz, prim.r[1], prim.r[2], prim.r[3])
    elseif t == "box" then
        return sdBox(px, py, pz, prim.h[1], prim.h[2], prim.h[3], prim.round)
    elseif t == "fin" then
        local u, v, w = prim.fu, prim.fv, prim.fw
        local pu = px * u[1] + py * u[2] + pz * u[3]
        local pv = px * v[1] + py * v[2] + pz * v[3]
        local pw = px * w[1] + py * w[2] + pz * w[3]
        local hl = prim.len * 0.5
        -- 底边越靠根部越厚：厚度随高度线性收窄
        local d2 = sdTri2(pu, pv, -hl, 0.0, hl, 0.0, hl + prim.sweep, prim.h)
        local th = prim.thick * 0.5 * (1.0 - 0.5 * max(0, min(1, pv / prim.h)))
        return extrude(d2, pw, th)
    elseif t == "rhombus" then
        local u, v, w = prim.fu, prim.fv, prim.fw
        local pu = px * u[1] + py * u[2] + pz * u[3]
        local pv = px * v[1] + py * v[2] + pz * v[3]
        local pw = px * w[1] + py * w[2] + pz * w[3]
        return extrude(sdRhombus2(pu, pv, prim.a, prim.b), pw, prim.thick * 0.5)
    end
    return 1e9
end

-- 多项式平滑最小值
local function smin(a, b, k)
    if k <= 0 then return min(a, b) end
    local h = max(k - abs(a - b), 0.0) / k
    return min(a, b) - h * h * k * 0.25
end
M.SMin = smin

-- 鳞甲浮雕：按世界坐标分块，部分鳞片外凸 plate 米（形成参考图那种阶梯叠片轮廓）
local PLATE_X, PLATE_Y, PLATE_Z = 0.26, 0.18, 0.26
function M.PlateCell(x, y, z)
    -- 行与行之间错位半块，像瓦片
    local j = floor(y / PLATE_Y)
    local off = (j % 2) * 0.5
    return floor(x / PLATE_X + off), j, floor(z / PLATE_Z + off)
end

---在体块列表上求值：返回 全局 SDF、最近体块
---@return number, table|nil
local function EvalField(cands, x, y, z)
    local d, best, bestD = 1e9, nil, 1e9
    for i = 1, #cands do
        local p = cands[i]
        if x >= p.bmin[1] and x <= p.bmax[1] and y >= p.bmin[2] and y <= p.bmax[2]
            and z >= p.bmin[3] and z <= p.bmax[3] then
            local di = M.Eval(p, x, y, z)
            if p.plate ~= nil and di < 0.25 then
                local ci, cj, ck = M.PlateCell(x, y, z)
                if M.Hash3(ci, cj, ck) < 0.45 then di = di - p.plate end
            end
            if p.paint then
                -- 涂色体块：不参与形体，只给落在它内部的体素换归属 / 颜色（型号变体的眼睛、腮红）；
                -- mask(x, y, z) 可再裁出任意轮廓（杏仁眼等），返回 false 的点不归它
                if di < 0 and (p.mask == nil or p.mask(x, y, z)) then
                    local dr = di - (p.prio or 0)
                    if dr < bestD then bestD, best = dr, p end
                end
            else
                -- 归属：原始距离最小者；prio 让小细节（瞳孔等）压过包住它的体块
                local dr = (di < 0) and (di - (p.prio or 0)) or di
                if dr < bestD then bestD, best = dr, p end
                d = smin(d, di, p.k or 0.0)
            end
        end
    end
    return d, best
end
M.EvalField = EvalField

---体素化一个部件
---@param prims table 全部体块（已 Prepare）
---@param bone string 部件所属骨骼
---@param s number 体素尺寸
---@param origin number[] 全局格点原点（体素中心 = origin + (i+0.5)*s）
---@param opts table|nil { overlap = false 关闭关节搭接 }
---@return table voxels { {i,j,k,color}, ... }
function M.VoxelizePart(prims, bone, s, origin, opts)
    opts = opts or {}
    local own = {}
    ---@type number[]
    local bmin = { 1e9, 1e9, 1e9 }
    ---@type number[]
    local bmax = { -1e9, -1e9, -1e9 }
    for _, p in ipairs(prims) do
        if p.bone == bone then
            own[#own + 1] = p
            for a = 1, 3 do
                bmin[a] = min(bmin[a], p.bmin[a])
                bmax[a] = max(bmax[a], p.bmax[a])
            end
        end
    end
    if #own == 0 then return {} end
    local cands = {}
    for _, p in ipairs(prims) do
        if p.bmax[1] >= bmin[1] - s and p.bmin[1] <= bmax[1] + s and p.bmax[2] >= bmin[2] - s
            and p.bmin[2] <= bmax[2] + s and p.bmax[3] >= bmin[3] - s and p.bmin[3] <= bmax[3] + s then
            cands[#cands + 1] = p
        end
    end
    local ox, oy, oz = origin[1], origin[2], origin[3]
    local i0, i1 = floor((bmin[1] - ox) / s) - 1, floor((bmax[1] - ox) / s) + 1
    local j0, j1 = floor((bmin[2] - oy) / s) - 1, floor((bmax[2] - oy) / s) + 1
    local k0, k1 = floor((bmin[3] - oz) / s) - 1, floor((bmax[3] - oz) / s) + 1
    if j0 < 0 and opts.clampGround then j0 = 0 end
    local nx, ny, nz = i1 - i0 + 1, j1 - j0 + 1, k1 - k0 + 1
    local inside, owner = {}, {}
    local function idx(i, j, k) return ((k - k0) * ny + (j - j0)) * nx + (i - i0) + 1 end
    for k = k0, k1 do
        local z = oz + (k + 0.5) * s
        for j = j0, j1 do
            local y = oy + (j + 0.5) * s
            for i = i0, i1 do
                local x = ox + (i + 0.5) * s
                local d, best = EvalField(cands, x, y, z)
                if d <= 0 and best ~= nil then
                    local n = idx(i, j, k)
                    inside[n] = true
                    owner[n] = best
                end
            end
        end
    end
    local out = {}
    for k = k0 + 1, k1 - 1 do
        local z = oz + (k + 0.5) * s
        for j = j0 + 1, j1 - 1 do
            local y = oy + (j + 0.5) * s
            for i = i0 + 1, i1 - 1 do
                local n = idx(i, j, k)
                if inside[n] then
                    local p = owner[n]
                    local x = ox + (i + 0.5) * s
                    local take = (p.bone == bone)
                    if not take and opts.overlap ~= false then
                        -- 关节搭接：自身体块内部 + 两格内邻居全实心（离外表面至少 2 格，
                        -- 关节转动时不会顶出皮肤和邻接部件的表面打架闪烁）
                        local deep = true
                        for dd = 1, 2 do
                            deep = deep and inside[idx(i + dd, j, k)] and inside[idx(i - dd, j, k)]
                                and inside[idx(i, j + dd, k)] and inside[idx(i, j - dd, k)]
                                and inside[idx(i, j, k + dd)] and inside[idx(i, j, k - dd)]
                        end
                        if deep then
                            local dOwn = 1e9
                            for _, q in ipairs(own) do
                                dOwn = min(dOwn, M.Eval(q, x, y, z))
                            end
                            if dOwn < -0.5 * s then
                                take = true
                                -- 颜色用自己的体块算（内部不可见，任选）
                                p = own[1]
                            end
                        end
                    end
                    if take then
                        local c = p.color
                        if type(c) == "function" then c = c(x, y, z, p) end
                        out[#out + 1] = { i, j, k, c }
                    end
                end
            end
        end
    end
    return out
end

return M
