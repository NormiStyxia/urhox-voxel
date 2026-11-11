-- ====================================================================
-- DragonRig.lua — 体素巨龙的节点层级 + 原生 VoxelVolume 部件（纯视觉体积，不建物理体）
--
-- 结构：
--   root（全局位移/朝向） → body（身体姿态：高度/俯仰/侧倾） → pelvis → waist → chest …
--   每根骨骼是一个 Node，静止姿态下所有骨骼旋转为单位四元数；骨骼下挂一个纯视觉
--   VoxelVolume（不 Finalize、无物理体，同 VoxelTown 视觉轮/旋翼做法），
--   由节点层级驱动。
-- 翅膀：翼根 wing → 前臂 wfore → 腕 whand → 四根指骨 wf1..4（各两节 wfNm），
--   以及挂在前臂上的虚拟后缘指 wf5。翼膜是一整张连续蒙皮网格（DragonMembrane），
--   由翼骨上的控制点驱动、GPU 变形，任何折叠角度下都连成一张皮。
-- 部件注册表 parts[bone] = { volume, node, voxels } 供后续体素破坏 / 重组使用。
-- ====================================================================

local Spec = require("dragon.DragonSpec")
local Sculpt = require("dragon.DragonSculpt")
local Membrane = require("dragon.DragonMembrane")

---@class DragonRig
---@field root Node
---@field body Node
---@field bones table<string, Node>
---@field pivots table<string, number[]>
---@field parents table<string, string>
---@field parts table<string, table>
---@field strips table[]
---@field order string[]
---@field sides table<string, table>
---@field curlAxis table<string, {axis: Vector3, mirror: boolean}>
---@field restPos table<string, Vector3>
---@field sockets table<string, Node>
---@field world VoxelPhysicsWorld
---@field spec table 型号规格（DragonSpec 或 DragonVariants.Get 的结果）
---@field size number 整体尺度（中号 = 1）
local Rig = {}
Rig.__index = Rig

local Q_IDENT = Quaternion(1, 0, 0, 0)

-- 关节欧拉角（度）→ 四元数，统一顺序 R = Rz * Ry * Rx（与 DragonSculpt.RotMatrix 一致）
function Rig.Euler(x, y, z)
    return Quaternion(z or 0, Vector3.FORWARD) * Quaternion(y or 0, Vector3.UP) * Quaternion(x or 0, Vector3.RIGHT)
end

-- 左右镜像（关于 YZ 平面）：x 轴旋转不变，y / z 轴旋转取反
function Rig.MirrorQuat(q)
    return Quaternion(q.w, q.x, -q.y, -q.z)
end

local function V3(t) return Vector3(t[1], t[2], t[3]) end
local function Sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end

-- 龙专用材质：克隆调色板材质，去掉 VOXELJITTER（逐体素随机明暗，在生物表面上像噪点），保留 AO
function Rig.CleanMaterial(world)
    local base = world:GetPaletteMaterial()
    local mat = base:Clone("DragonVoxelMaterial")
    local tech = base:GetTechnique(0)
    if mat == nil or tech == nil then return base end
    local t2 = tech:Clone("DragonVoxelTechnique")
    for _, pn in ipairs({ "base", "litbase", "light", "deferred", "prepass", "material" }) do
        local pass = t2:GetPass(pn)
        if pass ~= nil then
            pass:SetVertexShaderDefines((pass.vertexShaderDefines:gsub("VOXELJITTER", "")))
            pass:SetPixelShaderDefines((pass.pixelShaderDefines:gsub("VOXELJITTER", "")))
        end
    end
    mat:SetTechnique(0, t2)
    return mat
end

-- ---------------------------------------------------------------- 体积创建
local function MakeVolume(world, material, voxels, s, origin, pivot, parentNode, name)
    if #voxels == 0 then return nil end
    local i0, j0, k0, i1, j1, k1 = 1e9, 1e9, 1e9, -1e9, -1e9, -1e9
    for _, v in ipairs(voxels) do
        if v[1] < i0 then i0 = v[1] end
        if v[1] > i1 then i1 = v[1] end
        if v[2] < j0 then j0 = v[2] end
        if v[2] > j1 then j1 = v[2] end
        if v[3] < k0 then k0 = v[3] end
        if v[3] > k1 then k1 = v[3] end
    end
    local dx, dy, dz = math.floor(i1 - i0 + 1), math.floor(j1 - j0 + 1), math.floor(k1 - k0 + 1)
    local vol = world:CreateVolume(dx, dy, dz, s, Vector3.ZERO, Quaternion())
    local g = vol:GetGrid()
    for _, v in ipairs(voxels) do
        local x, y, z = math.floor(v[1] - i0), math.floor(v[2] - j0), math.floor(v[3] - k0)
        g:SetSolid(x, y, z, true)
        g:SetVoxelMaterial(x, y, z, v[4])
    end
    vol.destructible = true
    vol.material = material
    vol:RebuildGeometry()
    local node = vol:GetNode()
    node.temporary = true
    node.name = "vox_" .. name
    node:SetParent(parentNode)
    node.rotation = Quaternion()
    node.position = Vector3(origin[1] + i0 * s - pivot[1], origin[2] + j0 * s - pivot[2], origin[3] + k0 * s - pivot[3])
    return { volume = vol, node = node, voxels = #voxels, size = s }
end

-- ---------------------------------------------------------------- 尾巴：沿节轴体素化 + 环纹
-- 世界轴对齐的格子切斜向下的尾巴，侧面会变成一级级台阶（乐高感）。这里每节尾巴改在
-- 「自己的方向」上建格子：局部 Z = 这节的轴线（指向尾尖），Y = 与轴垂直的上方，X = 侧向，
-- 切出来是一段笔直的方截面棱柱，不再有台阶；体积节点再转回这个方向。
-- 颜色按圈：沿轴每 RING 米一圈，深浅交替，节与节交界一圈最深；腹面白甲连续、同样按圈分格。
Rig.TAIL_ALIGN = true
-- 颈（neck1..4）与四肢（armU/armL/legU/legL/legM）同样沿节轴体素化；手脚太小，仍用世界网格
Rig.LIMB_ALIGN = true
local RING = 0.16  -- 一圈的长度（米，中号）；型号尺度另乘

-- 尾巴各节的轴：返回 a(根端), b(尾端) 世界静止坐标，取这节体块（锥形胶囊）的两端
local function TailAxis(prims, bone)
    for _, p in ipairs(prims) do
        if p.bone == bone and p.type == "cone" and not p.joint then return p.a, p.b, p.r end
    end
    return nil
end

-- 局部 → 世界旋转（列向量 ex, ey, ez）
local function TailFrame(a, b)
    local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local l = math.sqrt(dx * dx + dy * dy + dz * dz)
    local ez = { dx / l, dy / l, dz / l }
    -- 侧向 = 世界 X（尾巴在 YZ 平面内），上方 = ez × ex
    -- 四肢轴带侧向分量：先把世界 X 对轴正交化，保证旋转是正交的
    local dot = ez[1]
    local ex = { 1 - dot * ez[1], -dot * ez[2], -dot * ez[3] }
    local el = math.sqrt(ex[1] * ex[1] + ex[2] * ex[2] + ex[3] * ex[3])
    ex = { ex[1] / el, ex[2] / el, ex[3] / el }
    local ey = { ez[2] * ex[3] - ez[3] * ex[2], ez[3] * ex[1] - ez[1] * ex[3], ez[1] * ex[2] - ez[2] * ex[1] }
    if ey[2] < 0 then ey = { -ey[1], -ey[2], -ey[3] }; ex = { -1, 0, 0 } end
    return ex, ey, ez, l
end

-- 环纹配色：t = 沿整条链的弧长（米），v = 在截面上的高度（-1 腹 .. 1 背），edge = 是否在节交界
-- limb = true：四肢不画腹甲和背脊条，只有环纹
local function RingColor(P, t, v, side, nodeSeam, ringLen, limb)
    local ring = math.floor(t / ringLen)
    local f = t / ringLen - ring
    if not limb and v < -0.35 and side < 0.8 then
        -- 腹甲：白色，按圈分格，格缝浅灰
        if f < 0.2 then return P.WHITE_S end
        return P.WHITE
    end
    -- 节交界：一圈中蓝（不用最深色，避免整条尾巴发黑）
    if nodeSeam then return P.BLUE_M end
    -- 背脊：一条中蓝
    if not limb and v > 0.75 then return P.BLUE_M end
    -- 两侧：每圈前沿一道中蓝窄环，其余为主色，奇偶圈在两档浅蓝间交替
    if f < 0.22 then return P.BLUE_M end
    return (ring % 2 == 0) and P.BLUE_L or P.BLUE_L2
end

-- 沿轴体素化的骨骼 → 所属链（链内弧长连续，环纹跨节对齐）；limb 链不画腹甲 / 背脊
local function AlignedChain(name)
    if Rig.TAIL_ALIGN and name:match("^tail%d$") then return "tail", false end
    if not Rig.LIMB_ALIGN then return nil end
    if name:match("^neck%d$") then return "neck", false end
    local limb, side = name:match("^(%a+)_([RL])$")
    if limb == "armU" or limb == "armL" then return "arm_" .. side, true end
    if limb == "legU" or limb == "legL" or limb == "legM" then return "leg_" .. side, true end
    return nil
end

-- 沿节轴体素化一节：返回局部格子的体素 { i, j, k, color }、局部原点（相对枢轴）、旋转、节长
local function VoxelizeAligned(prims, bone, s, pivot, spec, arc0, limb)
    local a, b = TailAxis(prims, bone)
    if a == nil then return nil end
    local ex, ey, ez, len = TailFrame(a, b)
    -- 体块起点在轴上相对枢轴的位置（中号两者重合，型号变体可能略有偏移）
    local az0 = (a[1] - pivot[1]) * ez[1] + (a[2] - pivot[2]) * ez[2] + (a[3] - pivot[3]) * ez[3]
    -- 轴线在截面上相对枢轴的偏移（四肢体块的轴不一定穿过枢轴），截面高度 / 侧距以轴线为准
    local ax0 = (a[1] - pivot[1]) * ex[1] + (a[2] - pivot[2]) * ex[2] + (a[3] - pivot[3]) * ex[3]
    local ay0 = (a[1] - pivot[1]) * ey[1] + (a[2] - pivot[2]) * ey[2] + (a[3] - pivot[3]) * ey[3]
    -- 包围：这节自身体块 + 背刺等，用 Sculpt 的场求值（含邻接节搭接）
    local own, cands = {}, {}
    ---@type number[]
    local bmin = { 1e9, 1e9, 1e9 }
    ---@type number[]
    local bmax = { -1e9, -1e9, -1e9 }
    for _, p in ipairs(prims) do
        if p.bone == bone then
            own[#own + 1] = p
            for k = 1, 3 do
                bmin[k] = math.min(bmin[k], p.bmin[k]); bmax[k] = math.max(bmax[k], p.bmax[k])
            end
        end
    end
    for _, p in ipairs(prims) do
        if p.bmax[1] >= bmin[1] - s and p.bmin[1] <= bmax[1] + s and p.bmax[2] >= bmin[2] - s
            and p.bmin[2] <= bmax[2] + s and p.bmax[3] >= bmin[3] - s and p.bmin[3] <= bmax[3] + s then
            cands[#cands + 1] = p
        end
    end
    -- 局部包围盒：把世界 AABB 的 8 个角投到局部轴
    ---@type number[]
    local lmin = { 1e9, 1e9, 1e9 }
    ---@type number[]
    local lmax = { -1e9, -1e9, -1e9 }
    for cx = 0, 1 do for cy = 0, 1 do for cz = 0, 1 do
        local w = { cx == 0 and bmin[1] or bmax[1], cy == 0 and bmin[2] or bmax[2], cz == 0 and bmin[3] or bmax[3] }
        local d = { w[1] - pivot[1], w[2] - pivot[2], w[3] - pivot[3] }
        local l = { d[1] * ex[1] + d[2] * ex[2] + d[3] * ex[3], d[1] * ey[1] + d[2] * ey[2] + d[3] * ey[3],
            d[1] * ez[1] + d[2] * ez[2] + d[3] * ez[3] }
        for k = 1, 3 do lmin[k] = math.min(lmin[k], l[k]); lmax[k] = math.max(lmax[k], l[k]) end
    end end end
    -- 侧向对称：格子在 X 上以 0 为中心（中线落在体素中心，左右各一半）
    local hx = math.max(-lmin[1], lmax[1])
    local i0, i1 = -math.floor(hx / s + 0.5) - 1, math.floor(hx / s + 0.5) + 1
    local j0, j1 = math.floor(lmin[2] / s) - 1, math.floor(lmax[2] / s) + 1
    local k0, k1 = math.floor(lmin[3] / s) - 1, math.floor(lmax[3] / s) + 1
    local P = Spec.PAL
    local S = spec.size or 1.0
    local ringLen = RING * S
    -- 这节的半径（用于截面高度归一化）：取锥两端半径插值
    local r0, r1 = nil, nil
    local body = own[1]
    for _, p in ipairs(own) do if p.type == "cone" and not p.joint then r0, r1, body = p.ra, p.rb, p end end
    r0, r1 = r0 or 0.2, r1 or 0.2
    local out = {}
    for k = k0, k1 do
        local lz = (k + 0.5) * s
        for j = j0, j1 do
            local ly = (j + 0.5) * s
            for i = i0, i1 do
                local lx = i * s  -- X 以 0 为中心（中线一列）
                local x = pivot[1] + ex[1] * lx + ey[1] * ly + ez[1] * lz
                local y = pivot[2] + ex[2] * lx + ey[2] * ly + ez[2] * lz
                local z = pivot[3] + ex[3] * lx + ey[3] * ly + ez[3] * lz
                local d, best = Sculpt.EvalField(cands, x, y, z)
                if d <= 0 and best ~= nil and y >= 0 then  -- y >= 0：贴地裁切（同 clampGround）
                    local take = (best.bone == bone)
                    if not take and best.joint == nil then
                        -- 和下一节搭接：两节格子方向不同，交界处会出现楔形缝；
                        -- 沿轴往尾端多伸 1.5 格（截面仍取下一节的形状），把缝盖住
                        local t = lz - az0
                        if t > len - s * 0.5 and t < len + s * 1.5 and best.type == "cone" then take, best = true, body end
                    elseif not take then
                        -- 关节球（属于父骨骼、藏在内部）：自身体块内部够深的点也归自己
                        local dOwn = 1e9
                        for _, q in ipairs(own) do dOwn = math.min(dOwn, Sculpt.Eval(q, x, y, z)) end
                        if dOwn < -1.5 * s then take, best = true, body end
                    end
                    if take then
                        local c
                        local c0 = best.color
                        if type(c0) == "function" then c0 = c0(x, y, z, best) end
                        if best.type == "cone" and not best.joint and c0 ~= P.BLUE_D then
                            -- 节身：按圈配色（四肢关节护甲 BLUE_D 保留原色）
                            local t = lz - az0
                            local u = math.max(0, math.min(1, t / len))
                            local r = r0 + (r1 - r0) * u
                            local v = (ly - ay0) / math.max(r, 1e-3)
                            local side = math.abs(lx - ax0) / math.max(r, 1e-3)
                            local seam = (t < s * 0.99) or (t > len - s * 0.99)
                            c = RingColor(P, arc0 + t, v, side, seam, ringLen, limb)
                        else
                            c = c0
                        end
                        out[#out + 1] = { i - i0, j - j0, k - k0, c }
                    end
                end
            end
        end
    end
    local origin = { i0 * s - 0.5 * s, j0 * s, k0 * s }  -- 局部（相对枢轴），体素中心 = origin + (idx+0.5)s
    local rot = Quaternion(Vector3(ex[1], ex[2], ex[3]), Vector3(ey[1], ey[2], ey[3]), Vector3(ez[1], ez[2], ez[3]))
    return out, origin, rot, len
end

-- 已在局部格子里的体素直接建体积（不再做世界轴对齐）
local function MakeVolumeLocal(world, material, voxels, s, origin, rot, parentNode, name)
    if #voxels == 0 then return nil end
    local dx, dy, dz = 0, 0, 0
    for _, v in ipairs(voxels) do
        if v[1] + 1 > dx then dx = v[1] + 1 end
        if v[2] + 1 > dy then dy = v[2] + 1 end
        if v[3] + 1 > dz then dz = v[3] + 1 end
    end
    local vol = world:CreateVolume(math.floor(dx), math.floor(dy), math.floor(dz), s, Vector3.ZERO, Quaternion())
    local g = vol:GetGrid()
    for _, v in ipairs(voxels) do
        g:SetSolid(v[1], v[2], v[3], true)
        g:SetVoxelMaterial(v[1], v[2], v[3], v[4])
    end
    vol.destructible = true
    vol.material = material
    vol:RebuildGeometry()
    local node = vol:GetNode()
    node.temporary = true
    node.name = "vox_" .. name
    node:SetParent(parentNode)
    node.rotation = rot
    node.position = rot * Vector3(origin[1], origin[2], origin[3])
    return { volume = vol, node = node, voxels = #voxels, size = s }
end

-- ---------------------------------------------------------------- 翼膜区域
-- 平面点 (x, z)（翼局部，y=0）→ 区域描述 { kind, gap, strip, outer, t } 或 nil
local function Polar(cx, cz, x, z)
    local dx, dz = x - cx, z - cz
    return math.deg(math.atan(-dz, dx)), math.sqrt(dx * dx + dz * dz)
end

local function InTri(px, pz, a, b, c)
    local function cross(o, p, q) return (p[1] - o[1]) * (q[3] - o[3]) - (p[3] - o[3]) * (q[1] - o[1]) end
    local P = { px, 0, pz }
    local d1, d2, d3 = cross(a, b, P), cross(b, c, P), cross(c, a, P)
    local neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    local pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (neg and pos)
end

local function WingLayout(w)
    local fp = Spec.FingerPoints(w)
    local W, E, B = w.wrist, w.elbow, w.flank
    local O = { 0, 0, 0 }
    local fans = {}
    for i, f in ipairs(w.fingers) do
        fans[i] = { a = f.a, L = f.L, J = f.L * w.joint }
    end
    local a5, L5 = Polar(W[1], W[3], B[1], B[3])
    fans[5] = { a = a5, L = L5, J = L5 * w.joint }
    return { w = w, fp = fp, W = W, E = E, B = B, O = O, fans = fans, u = w.unit or 1.0 }
end

local function MembraneRegion(lay, x, z)
    local w, W, fans = lay.w, lay.W, lay.fans
    local N = w.strips
    local a, r = Polar(W[1], W[3], x, z)
    if r > 0.12 * lay.u then
        for g = 1, 4 do
            local f0, f1 = fans[g], fans[g + 1]
            if a >= f0.a and a < f1.a then
                local t = (a - f0.a) / (f1.a - f0.a)
                local sc = (g == 4) and 0.1 or w.scallop
                local R = (f0.L + (f1.L - f0.L) * t) * (1.0 - sc * math.sin(math.pi * t))
                if r <= R then
                    local k = math.min(N - 1, math.floor(t * N))
                    local tc = (k + 0.5) / N
                    local split = f0.J + (f1.J - f0.J) * tc
                    return { kind = "hand", gap = g, strip = k, outer = r > split, t = tc, r = r, R = R, a = a }
                end
                return nil
            end
        end
    end
    local E, B, O = lay.E, lay.B, lay.O
    if InTri(x, z, E, W, B) then
        local aB = Polar(E[1], E[3], B[1], B[3])
        local aW = Polar(E[1], E[3], W[1], W[3])
        local ap = Polar(E[1], E[3], x, z)
        -- 角度跨越 ±180 时归一
        local function norm(v, ref) while v - ref > 180 do v = v - 360 end while v - ref < -180 do v = v + 360 end return v end
        aW, ap = norm(aW, aB), norm(ap, aB)
        local t = math.max(0, math.min(0.999, (ap - aB) / (aW - aB)))
        local k = math.floor(t * N)
        return { kind = "fore", strip = k, t = (k + 0.5) / N, tr = t }
    end
    if InTri(x, z, O, E, B) then
        local aB = Polar(0, 0, B[1], B[3])
        local aE = Polar(0, 0, E[1], E[3])
        local ap = Polar(0, 0, x, z)
        local t = math.max(0, math.min(0.999, (ap - aB) / (aE - aB)))
        local k = math.floor(t * N)
        return { kind = "hum", strip = k, t = (k + 0.5) / N }
    end
    return nil
end

local function MembraneColor(lay, x, z, reg)
    local P = Spec.PAL
    local u = lay.u
    -- 离最近翼骨线的距离（平面内）
    local W = lay.W
    local best = 1e9
    local function segDist(a, b)
        local abx, abz = b[1] - a[1], b[3] - a[3]
        local t = ((x - a[1]) * abx + (z - a[3]) * abz) / (abx * abx + abz * abz)
        t = math.max(0, math.min(1, t))
        local dx, dz = x - (a[1] + abx * t), z - (a[3] + abz * t)
        return math.sqrt(dx * dx + dz * dz)
    end
    for _, f in ipairs(lay.fp) do best = math.min(best, segDist(W, f.tip)) end
    best = math.min(best, segDist(lay.E, W), segDist(lay.O, lay.E))
    if best < 0.16 * u then return P.MEM_EDGE end
    -- 后缘起的阶梯叠层（参考图翼膜的分层台阶）
    local depth
    if reg.kind == "hand" then depth = reg.R - reg.r else depth = best end
    local band = math.floor((depth + 0.07 * u * math.floor(x / (0.3 * u))) / (0.42 * u))
    if band % 2 == 1 then return P.MEM2 end
    return P.MEM
end

-- ---------------------------------------------------------------- 构建
---@param scene Scene
---@param world VoxelPhysicsWorld
---@param parent Node|nil
---@param spec table|nil 型号规格，缺省为中号 DragonSpec
---@return DragonRig
function Rig.Build(scene, world, parent, spec)
    local t0 = os.clock()
    local self = setmetatable({}, Rig)
    spec = spec or Spec
    self.spec = spec
    self.size = spec.size or 1.0
    self.bones, self.pivots, self.parents, self.parts, self.strips, self.order = {}, {}, {}, {}, {}, {}
    self.sides = {}
    self.curlAxis = {}
    self.world = world

    for idx, c in pairs(spec.PALETTE) do
        world:SetPaletteEntry(idx, Color(c[1], c[2], c[3]), 6.0)
    end
    for idx, e in pairs(spec.EMISSIVE) do
        world:SetPaletteEntryPBR(idx, 0.3, 0.0, 0.5, Color(e[1], e[2], e[3], e[4]))
    end
    local material = Rig.CleanMaterial(world)
    self.membraneMaterial = Membrane.CreateMaterial()
    self.membranes = {}

    self.root = (parent or scene):CreateChild("Dragon")
    local prims, bones = spec.Expand()

    local function AddBone(name, parentName, pivot)
        local pnode = parentName and self.bones[parentName] or self.root
        local node = pnode:CreateChild(name)
        local pp = parentName and self.pivots[parentName] or { 0, 0, 0 }
        node.position = Vector3(pivot[1] - pp[1], pivot[2] - pp[2], pivot[3] - pp[3])
        self.bones[name] = node
        self.pivots[name] = pivot
        self.parents[name] = parentName
        self.order[#self.order + 1] = name
        return node
    end

    for _, b in ipairs(bones) do AddBone(b.name, b.parent, b.pivot) end
    self.body = self.bones.body

    -- 躯干 / 四肢 / 头尾
    local nVox = 0
    local chainArc = {}
    for _, b in ipairs(bones) do
        local s = spec.VoxelSizeOf(b.name)
        local origin = { -0.5 * s, 0.0, -0.5 * s }
        local part = nil
        local chain, limb = AlignedChain(b.name)
        local vox, lo, rot, len = nil, nil, nil, nil
        if chain ~= nil then
            -- 尾 / 颈 / 四肢：沿节轴体素化 + 环纹（见 VoxelizeAligned）
            vox, lo, rot, len = VoxelizeAligned(prims, b.name, s, b.pivot, spec, chainArc[chain] or 0.0, limb)
        end
        if vox ~= nil then
            part = MakeVolumeLocal(world, material, vox, s, lo, rot, self.bones[b.name], b.name)
            chainArc[chain] = (chainArc[chain] or 0.0) + len
        else
            -- 不复制外壳（overlap=false）：关节缝由 DragonSpec 的关节球（挂父骨骼、只占内部）填
            local wvox = Sculpt.VoxelizePart(prims, b.name, s, origin, { clampGround = true, overlap = false })
            part = MakeVolume(world, material, wvox, s, origin, b.pivot, self.bones[b.name], b.name)
        end
        if part ~= nil then
            part.bone = b.name
            self.parts[b.name] = part
            nVox = nVox + part.voxels
        end
    end
    local tBody = os.clock() - t0

    -- 翅膀
    self:BuildWing("_R", 1.0, world, material)
    self:BuildWing("_L", -1.0, world, material)
    for _, part in pairs(self.parts) do
        if part.wing then nVox = nVox + part.voxels end
    end

    -- 挂点
    self.sockets = {}
    for _, s in ipairs(spec.SOCKETS) do
        local n = self.bones[s.bone]:CreateChild("socket_" .. s.name)
        n.position = V3(s.offset)
        self.sockets[s.name] = n
    end

    -- 记录静止位置
    self.restPos = {}
    for name, node in pairs(self.bones) do self.restPos[name] = node.position end

    local nParts = 0
    for _ in pairs(self.parts) do nParts = nParts + 1 end
    print(string.format("DragonRig[%s]: %d bones, %d voxel parts, %d voxels, body %.2fs, total %.2fs",
        spec.id or "medium", #self.order, nParts, nVox, tBody, os.clock() - t0))
    return self
end

-- 一侧翅膀：sign = +1 右翼，-1 左翼（几何沿 X 镜像）
function Rig:BuildWing(sfx, sign, world, material)
    local spec = self.spec
    local lay = WingLayout(spec.WING)
    local w, W, E, B, O = lay.w, lay.W, lay.E, lay.B, lay.O
    local root = { w.root[1] * sign, w.root[2], w.root[3] }
    local function M(p) return { p[1] * sign, p[2], p[3] } end
    -- 节点：枢轴用世界静止坐标
    local function WP(p) return { root[1] + p[1] * sign, root[2] + p[2], root[3] + p[3] } end
    local function Add(name, parentName, pivot)
        local pnode = self.bones[parentName]
        local node = pnode:CreateChild(name)
        local pp = self.pivots[parentName]
        node.position = Vector3(pivot[1] - pp[1], pivot[2] - pp[2], pivot[3] - pp[3])
        self.bones[name] = node
        self.pivots[name] = pivot
        self.parents[name] = parentName
        self.order[#self.order + 1] = name
        return node
    end
    Add("wing" .. sfx, "chest", root)
    Add("wfore" .. sfx, "wing" .. sfx, WP(E))
    Add("whand" .. sfx, "wfore" .. sfx, WP(W))
    for i, f in ipairs(lay.fp) do
        Add("wf" .. i .. sfx, "whand" .. sfx, WP(W))
        Add("wf" .. i .. "m" .. sfx, "wf" .. i .. sfx, WP(f.joint))
        -- 指尖弯曲轴：翼平面内、垂直于指骨（右翼坐标，左翼由四元数镜像）
        local a = math.rad(w.fingers[i].a)
        self.curlAxis["wf" .. i .. "m" .. sfx] = { axis = Vector3(math.sin(a), 0, math.cos(a)), mirror = sign < 0 }
    end
    -- 虚拟后缘指：挂在前臂上，指向贴体点
    local f5 = lay.fans[5]
    local a5 = math.rad(f5.a)
    Add("wf5" .. sfx, "wfore" .. sfx, WP(W))
    Add("wf5m" .. sfx, "wf5" .. sfx, WP({ W[1] + math.cos(a5) * f5.J, 0, W[3] - math.sin(a5) * f5.J }))

    local s = spec.VOXEL_WING
    -- 翼局部格点：体素中心落在 s 的整数倍（膜层正好是 y=0 一层）
    local originL = { -0.5 * s, -0.5 * s, -0.5 * s }
    -- 世界静止坐标下的格点原点（体素中心对齐翼根 + i*s）
    local function OriginW()
        return { root[1] - 0.5 * s, root[2] - 0.5 * s, root[3] - 0.5 * s }
    end
    local function Mirror(vox)
        if sign > 0 then return vox end
        local out = {}
        for n, v in ipairs(vox) do out[n] = { -v[1], v[2], v[3], v[4] } end
        return out
    end

    -- 翼骨
    local bprims = spec.WingBonePrims(spec.WING)
    local boneNames = { "wing", "wfore", "whand" }
    for i = 1, 4 do
        boneNames[#boneNames + 1] = "wf" .. i
        boneNames[#boneNames + 1] = "wf" .. i .. "m"
    end
    for _, bn in ipairs(boneNames) do
        local vox = Mirror(Sculpt.VoxelizePart(bprims, bn, s, originL))
        local name = bn .. sfx
        local part = MakeVolume(world, material, vox, s, OriginW(), self.pivots[name], self.bones[name], name)
        if part ~= nil then
            part.bone, part.wing = name, true
            self.parts[name] = part
        end
    end

    -- 翼膜：一整张连续蒙皮网格（DragonMembrane），不再拆成刚性薄片
    local mem = Membrane.Build(self, {
        sfx = sfx, sign = sign, lay = lay, region = MembraneRegion, color = MembraneColor,
        material = self.membraneMaterial, triBase = (sign > 0) and 0 or Membrane.MAX_TRI,
        spec = spec,
    })
    self.membranes[#self.membranes + 1] = mem
    self.parts["membrane" .. sfx] = { node = mem.node, mesh = mem.geom, voxels = mem.cells, bone = "chest",
        wing = true, membrane = true }
    self.sides[sfx] = { lay = lay, sign = sign }
end

-- 销毁整条龙（切换型号用）：先从体素世界移除各部件体积，再删节点
function Rig:Destroy()
    for _, part in pairs(self.parts) do
        if part.volume ~= nil then self.world:RemoveVolume(part.volume) end
    end
    self.parts = {}
    if self.root ~= nil then self.root:Remove() end
    self.root = nil
end

-- ---------------------------------------------------------------- 运行时
---@param name string
---@param q Quaternion
function Rig:SetRot(name, q)
    local n = self.bones[name]
    if n ~= nil then n.rotation = q end
end

function Rig:ResetPose()
    for name, node in pairs(self.bones) do
        node.rotation = Quaternion()
        node.position = self.restPos[name]
    end
end

-- 翼膜：按当前翼骨姿态更新控制三角网（GPU 蒙皮）
function Rig:UpdateMembranes()
    Membrane.Update(self.membranes, self.membraneMaterial)
end

-- 世界坐标下的骨骼枢轴
function Rig:WorldPivot(name)
    return self.bones[name].worldPosition
end

-- 部件访问（供体素破坏）：返回 VoxelVolume 或 nil
function Rig:GetPartVolume(name)
    local p = self.parts[name]
    return p and p.volume or nil
end

-- 世界点 → 最近的命中区
function Rig:HitZoneAt(worldPoint, extra)
    local best, bestD = nil, 1e9
    for _, z in ipairs(self.spec.HIT_ZONES) do
        local node = self.bones[z.bone]
        if node ~= nil then
            local c = node:LocalToWorld(V3(z.offset))
            local d = (c - worldPoint):Length() - z.radius
            if d < bestD then bestD, best = d, z end
        end
    end
    if best ~= nil and bestD <= (extra or 0) then return best end
    return nil
end

local COL_BONE = Color(1.0, 0.85, 0.2)
local COL_WING = Color(0.3, 1.0, 0.6)
local COL_HIT = Color(1.0, 0.3, 0.3)
local COL_STRIP = Color(0.5, 0.7, 1.0, 0.6)

---@param dbg DebugRenderer
function Rig:DrawSkeleton(dbg, showStrips)
    if showStrips then Membrane.Draw(self.membranes, dbg, COL_STRIP) end
    for _, name in ipairs(self.order) do
        local pn = self.parents[name]
        if pn ~= nil then
            local a = self.bones[pn].worldPosition
            local b = self.bones[name].worldPosition
            local col = (name:sub(1, 1) == "w") and COL_WING or COL_BONE
            dbg:AddLine(a, b, col, false)
            dbg:AddCross(b, 0.08, col, false)
        end
    end
end

---@param dbg DebugRenderer
function Rig:DrawHitZones(dbg)
    for _, z in ipairs(self.spec.HIT_ZONES) do
        local node = self.bones[z.bone]
        if node ~= nil then
            local c = node:LocalToWorld(V3(z.offset))
            dbg:AddSphere(Sphere(c, z.radius), COL_HIT, false)
        end
    end
end

return Rig
