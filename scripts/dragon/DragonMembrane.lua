-- ====================================================================
-- DragonMembrane.lua — 连续蒙皮翼膜
--
-- 翼膜是一整张体素阶梯外形的薄网格（每格 = 翼骨体素大小，上下两层 + 外缘侧壁），
-- 挂在胸骨下。变形不靠刚性薄片，而是一张跟着骨骼走的「控制三角网」：
--   控制点 O 翼根 / E 肘 / W 腕 / Ji 指关节 / Ti 指尖 跟随各自翼骨，B 贴体点跟随腰，
--   P5 = 腕到贴体点连线上的插值点（后缘绷直）。
-- 每个网格顶点在静止姿态下归属一个控制三角形，GPU 里按该三角形当前的仿射变换移动
-- （assets/Shaders/BLGL/DragonMembrane.shader）。相邻控制三角形共边，边上映射一致，
-- 所以膜在任何折叠角度下都是连续的一张皮，不会再裂开 / 散开。
-- ====================================================================

local Spec = require("dragon.DragonSpec")

local Membrane = {}
Membrane.MAX_TRI = 16      -- 每侧控制三角形上限（shader 数组 32 个）
Membrane.THICK = 0.04      -- 翼膜厚度（米）；翼骨 2–3 格厚，明显厚于膜
Membrane.SHADER = "Shaders/BLGL/DragonMembrane.shader"

local function Sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function Cross(a, b)
    return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end
local function Normalize(a)
    local l = math.sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
    if l < 1e-9 then return nil end
    return { a[1] / l, a[2] / l, a[3] / l }
end

-- 列向量 c1,c2,c3 组成的 3x3 矩阵求逆，返回逆矩阵的三行
local function Inv3(c1, c2, c3)
    local r1, r2, r3 = Cross(c2, c3), Cross(c3, c1), Cross(c1, c2)
    local det = c1[1] * r1[1] + c1[2] * r1[2] + c1[3] * r1[3]
    local k = 1.0 / det
    for i = 1, 3 do r1[i], r2[i], r3[i] = r1[i] * k, r2[i] * k, r3[i] * k end
    return { r1, r2, r3 }
end

function Membrane.CreateMaterial()
    local mat = Material:new()
    if not mat:SetSurfaceShader(Membrane.SHADER) then
        print("DragonMembrane: failed to load " .. Membrane.SHADER)
    end
    return mat
end

-- 平面重心坐标（翼局部 x,z），返回最小分量（<0 表示在三角形外，越小越远）
local function MinBary(px, pz, a, b, c)
    local v0x, v0z = b[1] - a[1], b[2] - a[2]
    local v1x, v1z = c[1] - a[1], c[2] - a[2]
    local v2x, v2z = px - a[1], pz - a[2]
    local den = v0x * v1z - v1x * v0z
    local l1 = (v2x * v1z - v1x * v2z) / den
    local l2 = (v0x * v2z - v2x * v0z) / den
    return math.min(1.0 - l1 - l2, l1, l2)
end

---@param rig DragonRig
---@param opts table { sfx, sign, lay, region, color, material, triBase, spec }
function Membrane.Build(rig, opts)
    local sfx, sign, lay = opts.sfx, opts.sign, opts.lay
    local spec = opts.spec or Spec
    local w, W, E, B, O = lay.w, lay.W, lay.E, lay.B, lay.O
    local chest = rig.bones.chest
    local cp = rig.pivots.chest
    local root = { w.root[1] * sign, w.root[2], w.root[3] }
    local function WP(p) return { root[1] + p[1] * sign, root[2] + p[2], root[3] + p[3] } end
    local function ToL(p) local q = WP(p); return { q[1] - cp[1], q[2] - cp[2], q[3] - cp[3] } end

    ---@type table
    local side = { sfx = sfx, sign = sign, pts = {}, order = {}, tris = {}, triBase = opts.triBase }
    local function Pt(key, bone, p)
        local bn = (bone == "waist") and bone or (bone .. sfx)
        local pv = rig.pivots[bn]
        local q = WP(p)
        side.pts[key] = { node = rig.bones[bn], off = Vector3(q[1] - pv[1], q[2] - pv[2], q[3] - pv[3]),
            rest = ToL(p), plane = { p[1], p[3] } }
        side.order[#side.order + 1] = key
    end
    local function Lerp(key, ka, kb, f)
        ---@type {rest: number[], plane: number[]}, {rest: number[], plane: number[]}
        local a, b = side.pts[ka], side.pts[kb]
        local r, pl = {}, {}
        for i = 1, 3 do r[i] = a.rest[i] + (b.rest[i] - a.rest[i]) * f end
        for i = 1, 2 do pl[i] = a.plane[i] + (b.plane[i] - a.plane[i]) * f end
        side.pts[key] = { lerp = { ka, kb, f }, rest = r, plane = pl }
        side.order[#side.order + 1] = key
    end

    Pt("O", "wing", O)
    Pt("E", "wfore", E)
    Pt("W", "whand", W)
    for i, f in ipairs(lay.fp) do
        Pt("J" .. i, "wf" .. i, f.joint)
        Pt("T" .. i, "wf" .. i .. "m", f.tip)
    end
    Pt("B", "waist", B)
    local f5 = lay.fans[5]
    Lerp("P5", "W", "B", f5.J / f5.L)

    local function Tri(a, b, c) side.tris[#side.tris + 1] = { a, b, c } end
    Tri("O", "E", "B")   -- 肱骨膜：翼根—肘—贴体点
    Tri("E", "W", "B")   -- 前臂膜：肘—腕—贴体点
    for g = 1, 3 do      -- 指间膜：内段扇形 + 外段两片
        local a, b = tostring(g), tostring(g + 1)
        Tri("W", "J" .. a, "J" .. b)
        Tri("J" .. a, "T" .. a, "T" .. b)
        Tri("J" .. a, "T" .. b, "J" .. b)
    end
    Tri("W", "J4", "P5") -- 第四指到后缘
    Tri("J4", "T4", "P5")
    Tri("T4", "B", "P5")
    assert(#side.tris <= Membrane.MAX_TRI)

    for _, t in ipairs(side.tris) do
        local R0, R1, R2 = side.pts[t[1]].rest, side.pts[t[2]].rest, side.pts[t[3]].rest
        local e1, e2 = Sub(R1, R0), Sub(R2, R0)
        local n = Normalize(Cross(e1, e2))
        t.R0, t.inv, t.n = R0, Inv3(e1, e2, n), n
    end

    -- 静止平面点 → 所属控制三角形（重心坐标最「靠里」的那个；外缘的点取最近的三角形外推）
    local cornerTri = {}
    ---@return number
    local function TriAt(ci, ck, x, z)
        local key = ci * 65536 + ck
        local v = cornerTri[key]
        if v ~= nil then return v end
        local best, bestV = 0, -1e9
        for ti, t in ipairs(side.tris) do
            local m = MinBary(x, z, side.pts[t[1]].plane, side.pts[t[2]].plane, side.pts[t[3]].plane)
            if m > bestV then best, bestV = ti, m end
        end
        v = best - 1 + side.triBase
        cornerTri[key] = v
        return v
    end

    -- 平面扫描出翼膜格子（与翼骨同尺寸的体素格）；扫描范围按翼尺寸缩放
    local s = spec.VOXEL_WING
    local u = w.unit or 1.0
    local cells = {}
    local list = {}
    local x0, x1 = math.min(-0.3 * u, B[1] - 2 * s), 7.2 * u
    local z0, z1 = math.min(-2.9 * u, B[3] - 2 * s), 1.2 * u
    for k = math.floor(z0 / s), math.floor(z1 / s) do
        local z = k * s
        for i = math.floor(x0 / s), math.floor(x1 / s) do
            local x = i * s
            local reg = opts.region(lay, x, z)
            if reg ~= nil then
                local idx = opts.color(lay, x, z, reg)
                local c = spec.PALETTE[idx]
                local e = spec.EMISSIVE[idx]
                local col = Color(c[1], c[2], c[3], e and e[4] or 0.0)
                cells[i * 65536 + k] = true
                list[#list + 1] = { i, k, col }
            end
        end
    end

    local node = chest:CreateChild("membrane" .. sfx)
    local geom = node:CreateComponent("CustomGeometry")
    geom:SetNumGeometries(1)
    geom:BeginGeometry(0, TRIANGLE_LIST)
    local h = 0.5 * (spec.membraneThick or Membrane.THICK)
    local nv = 0
    local function V(ci, ck, layer, nrm, col)
        local x, z = (ci - 0.5) * s, (ck - 0.5) * s
        local p = ToL({ x, 0, z })
        geom:DefineVertex(Vector3(p[1], p[2] + layer * h, p[3]))
        geom:DefineNormal(nrm)
        geom:DefineColor(col)
        geom:DefineTexCoord(Vector2(TriAt(ci, ck, x, z), 0))
        nv = nv + 1
    end
    -- 四个角（ci,ck,layer）按顺序组成一个面
    local function Quad(q, nrm, col)
        V(q[1], q[2], q[3], nrm, col); V(q[4], q[5], q[6], nrm, col); V(q[7], q[8], q[9], nrm, col)
        V(q[1], q[2], q[3], nrm, col); V(q[7], q[8], q[9], nrm, col); V(q[10], q[11], q[12], nrm, col)
    end
    local UP, DN = Vector3(0, 1, 0), Vector3(0, -1, 0)
    local NX, PX = Vector3(-sign, 0, 0), Vector3(sign, 0, 0)
    local NZ, PZ = Vector3(0, 0, -1), Vector3(0, 0, 1)
    for _, c in ipairs(list) do
        local i, k, col = c[1], c[2], c[3]
        local i1, k1 = i + 1, k + 1
        Quad({ i, k, 1, i1, k, 1, i1, k1, 1, i, k1, 1 }, UP, col)
        Quad({ i, k, -1, i, k1, -1, i1, k1, -1, i1, k, -1 }, DN, col)
        if not cells[(i - 1) * 65536 + k] then Quad({ i, k, 1, i, k1, 1, i, k1, -1, i, k, -1 }, NX, col) end
        if not cells[(i + 1) * 65536 + k] then Quad({ i1, k, 1, i1, k, -1, i1, k1, -1, i1, k1, 1 }, PX, col) end
        if not cells[i * 65536 + (k - 1)] then Quad({ i, k, 1, i, k, -1, i1, k, -1, i1, k, 1 }, NZ, col) end
        if not cells[i * 65536 + (k + 1)] then Quad({ i, k1, 1, i1, k1, 1, i1, k1, -1, i, k1, -1 }, PZ, col) end
    end
    -- 顶点在 GPU 里才移动，剔除用的是静止包围盒：加一个退化三角形把包围盒撑到翅膀的活动范围
    local white = Color(1, 1, 1, 0)
    local bu = math.max(1.0, u)
    for _, p in ipairs({ Vector3(-9 * bu, -6 * bu, -9 * bu), Vector3(9 * bu, 10 * bu, 9 * bu), Vector3(9 * bu, -6 * bu, -9 * bu) }) do
        geom:DefineVertex(p)
        geom:DefineNormal(UP)
        geom:DefineColor(white)
        geom:DefineTexCoord(Vector2(0, 1))
    end
    geom:Commit()
    geom:SetMaterial(opts.material)
    geom.castShadows = true

    side.node, side.geom, side.cells, side.verts = node, geom, #list, nv
    side.cur, side.lastN = {}, {}
    return side
end

-- 当前控制点（膜节点局部坐标）
local function UpdatePoints(side)
    local node = side.node
    for _, key in ipairs(side.order) do
        local p = side.pts[key]
        if p.lerp == nil then
            local v = node:WorldToLocal(p.node:LocalToWorld(p.off))
            side.cur[key] = { v.x, v.y, v.z }
        else
            local a, b, f = side.cur[p.lerp[1]], side.cur[p.lerp[2]], p.lerp[3]
            side.cur[key] = { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f }
        end
    end
end

-- 写一侧的三角形矩阵：A = [e1' e2' n'] · [e1 e2 n]^-1，t = C0 - A·R0
local function WriteSide(side, buf)
    UpdatePoints(side)
    for ti = 1, Membrane.MAX_TRI do
        local t = side.tris[ti]
        if t == nil then
            buf:WriteFloat(1); buf:WriteFloat(0); buf:WriteFloat(0); buf:WriteFloat(0)
            buf:WriteFloat(0); buf:WriteFloat(1); buf:WriteFloat(0); buf:WriteFloat(0)
            buf:WriteFloat(0); buf:WriteFloat(0); buf:WriteFloat(1); buf:WriteFloat(0)
        else
            local C0, C1, C2 = side.cur[t[1]], side.cur[t[2]], side.cur[t[3]]
            local e1, e2 = Sub(C1, C0), Sub(C2, C0)
            local n = Normalize(Cross(e1, e2)) or side.lastN[ti] or t.n
            side.lastN[ti] = n
            local r1, r2, r3 = t.inv[1], t.inv[2], t.inv[3]
            local R0 = t.R0
            for r = 1, 3 do
                local a, b, c = e1[r], e2[r], n[r]
                local m1 = a * r1[1] + b * r2[1] + c * r3[1]
                local m2 = a * r1[2] + b * r2[2] + c * r3[2]
                local m3 = a * r1[3] + b * r2[3] + c * r3[3]
                buf:WriteFloat(m1); buf:WriteFloat(m2); buf:WriteFloat(m3)
                buf:WriteFloat(C0[r] - (m1 * R0[1] + m2 * R0[2] + m3 * R0[3]))
            end
        end
    end
end

---@param sides table[] 右翼、左翼（triBase 0 / 16）
---@param material Material
function Membrane.Update(sides, material)
    local buf = VectorBuffer()
    for _, side in ipairs(sides) do WriteSide(side, buf) end
    material:SetShaderParameter("tri_rows", Variant(buf))
end

-- 调试：画控制三角网
---@param dbg DebugRenderer
function Membrane.Draw(sides, dbg, col)
    for _, side in ipairs(sides) do
        local node = side.node
        for _, t in ipairs(side.tris) do
            local a, b, c = side.cur[t[1]], side.cur[t[2]], side.cur[t[3]]
            if a ~= nil and b ~= nil and c ~= nil then
                local pa = node:LocalToWorld(Vector3(a[1], a[2], a[3]))
                local pb = node:LocalToWorld(Vector3(b[1], b[2], b[3]))
                local pc = node:LocalToWorld(Vector3(c[1], c[2], c[3]))
                dbg:AddLine(pa, pb, col, false)
                dbg:AddLine(pb, pc, col, false)
                dbg:AddLine(pc, pa, col, false)
            end
        end
    end
end

return Membrane
