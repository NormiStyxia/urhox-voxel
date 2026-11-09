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

local function WingLayout()
    local w = Spec.WING
    local fp = Spec.FingerPoints(w)
    local W, E, B = w.wrist, w.elbow, w.flank
    local O = { 0, 0, 0 }
    local fans = {}
    for i, f in ipairs(w.fingers) do
        fans[i] = { a = f.a, L = f.L, J = f.L * w.joint }
    end
    local a5, L5 = Polar(W[1], W[3], B[1], B[3])
    fans[5] = { a = a5, L = L5, J = L5 * w.joint }
    return { w = w, fp = fp, W = W, E = E, B = B, O = O, fans = fans }
end

local function MembraneRegion(lay, x, z)
    local w, W, fans = lay.w, lay.W, lay.fans
    local N = w.strips
    local a, r = Polar(W[1], W[3], x, z)
    if r > 0.12 then
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
    if best < 0.16 then return P.MEM_EDGE end
    -- 后缘起的阶梯叠层（参考图翼膜的分层台阶）
    local depth
    if reg.kind == "hand" then depth = reg.R - reg.r else depth = best end
    local band = math.floor((depth + 0.07 * math.floor(x / 0.3)) / 0.42)
    if band % 2 == 1 then return P.MEM2 end
    return P.MEM
end

-- ---------------------------------------------------------------- 构建
---@param scene Scene
---@param world VoxelPhysicsWorld
---@param parent Node|nil
---@return DragonRig
function Rig.Build(scene, world, parent)
    local t0 = os.clock()
    local self = setmetatable({}, Rig)
    self.bones, self.pivots, self.parents, self.parts, self.strips, self.order = {}, {}, {}, {}, {}, {}
    self.sides = {}
    self.curlAxis = {}
    self.world = world

    for idx, c in pairs(Spec.PALETTE) do
        world:SetPaletteEntry(idx, Color(c[1], c[2], c[3]), 6.0)
    end
    for idx, e in pairs(Spec.EMISSIVE) do
        world:SetPaletteEntryPBR(idx, 0.3, 0.0, 0.5, Color(e[1], e[2], e[3], e[4]))
    end
    local material = Rig.CleanMaterial(world)
    self.membraneMaterial = Membrane.CreateMaterial()
    self.membranes = {}

    self.root = (parent or scene):CreateChild("Dragon")
    local prims, bones = Spec.Expand()

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
    for _, b in ipairs(bones) do
        local s = Spec.VoxelSizeOf(b.name)
        local origin = { -0.5 * s, 0.0, -0.5 * s }
        -- 不复制外壳（overlap=false）：关节缝由 DragonSpec 的关节球（挂父骨骼、只占内部）填
        local vox = Sculpt.VoxelizePart(prims, b.name, s, origin, { clampGround = true, overlap = false })
        local part = MakeVolume(world, material, vox, s, origin, b.pivot, self.bones[b.name], b.name)
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
    for _, s in ipairs(Spec.SOCKETS) do
        local n = self.bones[s.bone]:CreateChild("socket_" .. s.name)
        n.position = V3(s.offset)
        self.sockets[s.name] = n
    end

    -- 记录静止位置
    self.restPos = {}
    for name, node in pairs(self.bones) do self.restPos[name] = node.position end

    local nParts = 0
    for _ in pairs(self.parts) do nParts = nParts + 1 end
    print(string.format("DragonRig: %d bones, %d voxel parts, %d voxels, body %.2fs, total %.2fs",
        #self.order, nParts, nVox, tBody, os.clock() - t0))
    return self
end

-- 一侧翅膀：sign = +1 右翼，-1 左翼（几何沿 X 镜像）
function Rig:BuildWing(sfx, sign, world, material)
    local lay = WingLayout()
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

    local s = Spec.VOXEL_WING
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
    local bprims = Spec.WingBonePrims()
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
    })
    self.membranes[#self.membranes + 1] = mem
    self.parts["membrane" .. sfx] = { node = mem.node, mesh = mem.geom, voxels = mem.cells, bone = "chest",
        wing = true, membrane = true }
    self.sides[sfx] = { lay = lay, sign = sign }
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
    for _, z in ipairs(Spec.HIT_ZONES) do
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
    for _, z in ipairs(Spec.HIT_ZONES) do
        local node = self.bones[z.bone]
        if node ~= nil then
            local c = node:LocalToWorld(V3(z.offset))
            dbg:AddSphere(Sphere(c, z.radius), COL_HIT, false)
        end
    end
end

return Rig
