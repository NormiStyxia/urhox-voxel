-- ====================================================================
-- RuinsTrees.lua — 方格枝干 + 叶片卡树冠
--
--   树干 / 枝：6.25cm 方格采样，方截面、硬法线；合并重叠枝根和共面表面。
--   每树一个可视网格，保留原隐藏碰撞，不把装饰精度带入物理模拟。
--   树冠：参考 MC 高清材质包 + 风格化游戏的"叶片卡"做法——每个叶团是几十张交叉的
--         像素叶贴图卡（RuinsLeafCard.shader，alpha 镂空），轮廓是一片片叶子，不是光滑的球。
--         卡片的光照法线取"叶团外法线"，整个树冠像一个体积那样明暗过渡；顶点色 r 记录
--         卡片离团心的深浅（内层压暗），g 记录每张卡的亮度差。一棵树的所有卡合成一个
--         CustomGeometry（一棵树一个 draw call）。
--   碰撞：一根隐藏的体素树干（诺米撞得到树，叶子不挡路）
-- ====================================================================

local Noise = require("ruins.Noise")

local M = {}

local sin, cos, sqrt, max, min, pi = math.sin, math.cos, math.sqrt, math.max, math.min, math.pi

local leafMats_ = {}
local barkMat_ = nil
local hiddenMat_ = nil

local function Mat(path)
    local m = Material:new()
    if not m:SetSurfaceShader(path) then
        print("RuinsTrees: shader failed " .. path)
        m:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    end
    return m
end

local function Shared()
    if barkMat_ == nil then
        barkMat_ = Mat("Shaders/BLGL/RuinsBark.shader")
        hiddenMat_ = Material:new()
        if not hiddenMat_:SetSurfaceShader("Shaders/BLGL/HiddenVoxel.shader") then hiddenMat_ = nil end
    end
end

-- 叶色（sRGB）：{ 暗, 亮 }
local GREENS = {
    { Vector3(0.09, 0.21, 0.07), Vector3(0.52, 0.72, 0.25) },
    { Vector3(0.08, 0.19, 0.09), Vector3(0.44, 0.66, 0.30) },
    { Vector3(0.12, 0.22, 0.06), Vector3(0.60, 0.74, 0.24) },
}
local GOLDS = { { Vector3(0.55, 0.30, 0.08), Vector3(1.00, 0.86, 0.42) } }

local function LeafMaterial(key, pal)
    local m = leafMats_[key]
    if m ~= nil then return m end
    m = Material:new()
    if m:SetSurfaceShader("Shaders/BLGL/RuinsLeafCard.shader") then
        local tex = cache:GetResource("Texture2D", "Textures/RuinsLeaves.png")
        if tex ~= nil then
            tex:SetAddressMode(COORD_U, ADDRESS_CLAMP)
            tex:SetAddressMode(COORD_V, ADDRESS_CLAMP)
            m:SetSurfaceTexture("leaf_tex", tex)
        end
        m:SetShaderParameter("leaf_dark", Variant(pal[1]))
        m:SetShaderParameter("leaf_light", Variant(pal[2]))
    else
        m:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        m:SetShaderParameter("MatDiffColor", Variant(Color(pal[2].x * 0.6, pal[2].y * 0.6, pal[2].z * 0.6)))
    end
    leafMats_[key] = m
    return m
end

-- 叶片卡建造器：累积多个叶团的卡片，最后一次性提交
---@class LeafBuilder
---@field geo CustomGeometry
---@field n integer
local LB = {}
LB.__index = LB

local function NewLeaves(parent)
    local node = parent:CreateChild("Leaves")
    local geo = node:CreateComponent("CustomGeometry")
    geo:BeginGeometry(0, TRIANGLE_LIST)
    return setmetatable({ geo = geo, n = 0, node = node }, LB)
end

-- 一个叶团：中心 c、半径 r（椭球：y 方向 0.75）；卡片尺寸随半径
function LB:Clump(c, r, rng, density)
    local geo = self.geo
    local count = math.floor((density or 26) * (r * r) / 2.2 + 10)
    local size = 0.55 + r * 0.32
    for _ = 1, count do
        -- 随机方向，越靠外越多（卡片中心落在 0.35r..1.0r 的壳里）
        local u, v = rng:Range(-1, 1), rng:Range(0, 2 * pi)
        local sxy = sqrt(1 - u * u)
        local dir = Vector3(sxy * cos(v), u, sxy * sin(v))
        local depth = 0.35 + 0.65 * math.sqrt(rng:Next())
        local p = c + Vector3(dir.x * r, dir.y * r * 0.75, dir.z * r) * depth
        -- 卡片朝向：大致朝外，带随机扭转；光照法线 = 外法线（略偏上）
        local nrm = (dir + Vector3(0, 0.35, 0)):Normalized()
        local t1 = nrm:CrossProduct(Vector3(rng:Range(-1, 1), rng:Range(-1, 1), rng:Range(-1, 1))):Normalized()
        if t1:LengthSquared() < 0.01 then t1 = Vector3(1, 0, 0) end
        local t2 = nrm:CrossProduct(t1):Normalized()
        -- 卡面不完全贴着外法线：混一点随机，交叉更乱更像叶丛
        local face = (nrm + Vector3(rng:Range(-0.6, 0.6), rng:Range(-0.6, 0.6), rng:Range(-0.6, 0.6))):Normalized()
        t1 = face:CrossProduct(t2):Normalized()
        t2 = face:CrossProduct(t1):Normalized()
        local hs = size * rng:Range(0.75, 1.15) * 0.5
        local a, b = t1 * hs, t2 * hs
        local shade = 0.45 + 0.55 * depth * (0.7 + 0.3 * (dir.y * 0.5 + 0.5))
        local col = Color(shade, rng:Next(), 0, 1)
        local q = { p - a - b, p + a - b, p + a + b, p - a + b }
        local uv = { Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0) }
        for _, idx in ipairs({ 1, 2, 3, 1, 3, 4 }) do
            geo:DefineVertex(q[idx])
            geo:DefineNormal(nrm)
            geo:DefineColor(col)
            geo:DefineTexCoord(uv[idx])
        end
        self.n = self.n + 1
    end
end

function LB:Finish(mat)
    self.geo:Commit()
    self.geo:SetMaterial(mat)
    self.geo.castShadows = true
    return self.n
end

-- 稀疏方格枝干。先合并整棵树的占据格，再贪心合并共面外表面。
local BARK_CELL = 0.0625
M.BARK_CELL = BARK_CELL
local Wood = {}
Wood.__index = Wood
local function CellKey(x, y, z) return x .. ":" .. y .. ":" .. z end
local function NewWood(parent)
    return setmetatable({ parent = parent, cells = {}, occupied = {} }, Wood)
end

function Wood:Path(pts, radius)
    local s = BARK_CELL
    for k = 1, #pts - 1 do
        local a, b = pts[k], pts[k + 1]
        local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
        local len2 = dx * dx + dy * dy + dz * dz
        for x = math.floor((min(a.x, b.x) - radius) / s), math.floor((max(a.x, b.x) + radius) / s) do
            for y = math.floor((min(a.y, b.y) - radius) / s), math.floor((max(a.y, b.y) + radius) / s) do
                for z = math.floor((min(a.z, b.z) - radius) / s), math.floor((max(a.z, b.z) + radius) / s) do
                    local px, py, pz = (x + 0.5) * s - a.x, (y + 0.5) * s - a.y, (z + 0.5) * s - a.z
                    local t = len2 > 0 and max(0, min(1, (px * dx + py * dy + pz * dz) / len2)) or 0
                    -- 方截面，不把圆管表面仅仅切成更多小面。
                    if max(math.abs(px - dx * t), math.abs(py - dy * t), math.abs(pz - dz * t)) <= radius then
                        local key = CellKey(x, y, z)
                        if not self.occupied[key] then
                            self.occupied[key] = true
                            self.cells[#self.cells + 1] = { x, y, z }
                        end
                    end
                end
            end
        end
    end
end

function Wood:Finish()
    local node = self.parent:CreateChild("Bark")
    local geo = node:CreateComponent("CustomGeometry")
    geo:BeginGeometry(0, TRIANGLE_LIST)
    local quads = 0
    for axis = 1, 3 do
        local u, v = axis % 3 + 1, (axis + 1) % 3 + 1
        for _, sign in ipairs({ -1, 1 }) do
            local planes = {}
            for _, c in ipairs(self.cells) do
                local neighbour = { c[1], c[2], c[3] }
                neighbour[axis] = neighbour[axis] + sign
                if not self.occupied[CellKey(neighbour[1], neighbour[2], neighbour[3])] then
                    local at = c[axis] + (sign > 0 and 1 or 0)
                    local plane = planes[at]
                    if not plane then plane = {}; planes[at] = plane end
                    local row = plane[c[v]]
                    if not row then row = {}; plane[c[v]] = row end
                    row[c[u]] = true
                end
            end
            local normal = { 0, 0, 0 }; normal[axis] = sign
            local n = Vector3(normal[1], normal[2], normal[3])
            for at, plane in pairs(planes) do
                local rows = {}; for row in pairs(plane) do rows[#rows + 1] = row end
                table.sort(rows)
                for _, y in ipairs(rows) do
                    local starts = {}; for x in pairs(plane[y]) do starts[#starts + 1] = x end
                    table.sort(starts)
                    for _, x in ipairs(starts) do
                        if plane[y][x] then
                            local w, h = 1, 1
                            while plane[y][x + w] do w = w + 1 end
                            while plane[y + h] do
                                local full = true
                                for i = x, x + w - 1 do if not plane[y + h][i] then full = false; break end end
                                if not full then break end
                                h = h + 1
                            end
                            for j = y, y + h - 1 do
                                for i = x, x + w - 1 do plane[j][i] = nil end
                            end
                            local corners = { { x, y }, { x + w, y }, { x + w, y + h }, { x, y + h } }
                            -- 引擎正面顺时针；硬法线与各轴面严格一致。
                            local indices = sign > 0 and { 1, 3, 2, 1, 4, 3 } or { 1, 2, 3, 1, 3, 4 }
                            for _, i in ipairs(indices) do
                                local p = {}; p[axis] = at; p[u] = corners[i][1]; p[v] = corners[i][2]
                                geo:DefineVertex(Vector3(p[1] * BARK_CELL, p[2] * BARK_CELL, p[3] * BARK_CELL))
                                geo:DefineNormal(n)
                                geo:DefineTexCoord(Vector2(corners[i][1] * BARK_CELL, corners[i][2] * BARK_CELL))
                            end
                            quads = quads + 1
                        end
                    end
                end
            end
        end
    end
    geo:Commit()
    geo:SetMaterial(barkMat_)
    geo.castShadows = true
    self.cells, self.occupied = nil, nil
    return quads
end

---@param scene Scene
---@param world VoxelPhysicsWorld
---@param x number
---@param gy number 地面高度
---@param z number
---@param o table { h, r, trunk, gold, lean, leanA }
function M.Tree(scene, world, x, gy, z, o)
    Shared()
    local rng = Noise.Rng(math.floor(x * 31 + z * 17) + 7)
    local h = o.h or 7
    local cr = o.r or 3.2
    local tr = o.trunk or 0.45
    local lean = o.lean or 0
    local la = o.leanA or 0
    local lx, lz = cos(la) * lean, sin(la) * lean
    local root = scene:CreateChild("Tree")
    root.position = Vector3(x, gy, z)
    local wood = NewWood(root)
    -- 主干：弯曲路径（二次曲线 + 小噪声），分三段越来越细，根部外扩
    local function TrunkAt(t)
        local wob = (Noise.Value2(t * 3, x, 5) - 0.5) * 0.3
        return Vector3(lx * t * t + wob, t * h, lz * t * t - wob)
    end
    local cuts = { 0.0, 0.38, 0.72, 1.0 }
    for s = 1, 3 do
        local pts = {}
        for k = 0, 4 do
            local t = cuts[s] + (cuts[s + 1] - cuts[s]) * k / 4
            pts[#pts + 1] = TrunkAt(t)
        end
        wood:Path(pts, tr * (1.0 - 0.28 * (s - 1)))
    end
    -- 根部隆起：4 条短根
    for i = 0, 3 do
        local a = i * pi / 2 + rng:Range(-0.4, 0.4)
        local d = Vector3(cos(a), 0, sin(a))
        wood:Path({ Vector3(0, 0.9, 0) + d * (tr * 0.2), Vector3(0, 0.35, 0) + d * (tr * 1.0), d * (tr * 2.0) + Vector3(0, -0.1, 0) }, tr * 0.38)
    end
    -- 树冠：顶团 + 3–5 个侧团（每个侧团一根枝伸过去）+ 填缝小团，全部是叶片卡
    local top = TrunkAt(1.0)
    local gi = rng:Int(1, #GREENS)
    local key = o.gold and "gold" or ("green" .. gi)
    local pal = o.gold and GOLDS[1] or GREENS[gi]
    local leaves = NewLeaves(root)
    leaves:Clump(top + Vector3(0, cr * 0.25, 0), cr * 0.95, rng)
    local nb = rng:Int(3, 5)
    local a0 = rng:Range(0, 2 * pi)
    for i = 1, nb do
        local a = a0 + i / nb * 2 * pi + rng:Range(-0.4, 0.4)
        local d = rng:Range(cr * 0.55, cr * 0.9)
        local p = top + Vector3(cos(a) * d, -rng:Range(0.3, 1.6), sin(a) * d)
        local fork = TrunkAt(rng:Range(0.6, 0.85))
        local mid = (fork + p) * 0.5 + Vector3(0, 0.5, 0)
        wood:Path({ fork, mid, p }, tr * 0.32)
        leaves:Clump(p + Vector3(0, 0.3, 0), cr * rng:Range(0.55, 0.75), rng)
    end
    for i = 1, 2 do
        local a = rng:Range(0, 2 * pi)
        leaves:Clump(top + Vector3(cos(a) * cr * 0.4, cr * rng:Range(-0.1, 0.35), sin(a) * cr * 0.4), cr * 0.55, rng)
    end
    leaves:Finish(LeafMaterial(key, pal))
    wood:Finish()
    -- 碰撞：隐藏的方形体素树干
    if world ~= nil and hiddenMat_ ~= nil then
        local s = 0.25
        local w = math.tointeger(math.max(2, math.floor(tr * 1.6 / s + 0.5))) or 2
        local nyv = math.tointeger(math.floor(h * 0.7 / s)) or 8
        local v = world:CreateVolume(w, nyv, w, s, Vector3(x - w * s * 0.5, gy - 0.25, z - w * s * 0.5))
        v:GetGrid():FillBox(0, 0, 0, w - 1, nyv - 1, w - 1, true)
        v.destructible = false
        v.material = hiddenMat_
        world:FinalizeVolume(v)
        v:RebuildGeometry()
    end
    return root
end

-- 时晶：六棱柱 + 尖顶，倾斜插在地里（纯装饰，无碰撞）
local crystalModel_ = nil
local crystalMat_ = nil
---@param scene Scene
function M.Crystal(scene, x, gy, z, h, r, tilt, a, violet)
    if crystalModel_ == nil then
        crystalMat_ = Mat("Shaders/BLGL/RuinsCrystal.shader")
        -- 单位尺寸（几何体以中心为原点，高 1、半径 1）：节点缩放成柱身 0.8h + 尖顶 0.2h
        crystalModel_ = { body = CylinderGeometry(1.0, 0.9, 1.0, 6, 1, false):ToModel(),
            tip = ConeGeometry(1.0, 1.0, 6, 1, true):ToModel() }
    end
    local root = scene:CreateChild("Crystal")
    root.position = Vector3(x, gy - 0.15, z)
    root.rotation = Quaternion(a * 57.2958, Vector3.UP) * Quaternion(tilt * 57.2958, Vector3.RIGHT)
    local col = violet and Color(1.15, 0.85, 1.05) or Color(1, 1, 1)
    local bn = root:CreateChild("Body")
    bn.position = Vector3(0, h * 0.4, 0)
    bn.scale = Vector3(r, h * 0.8, r)
    local sm = bn:CreateComponent("StaticModel")
    sm.model = crystalModel_.body
    sm.material = crystalMat_
    sm.instanceColor = col
    sm.castShadows = true
    local tn = root:CreateChild("Tip")
    tn.position = Vector3(0, h * 0.8 + h * 0.1, 0)
    tn.scale = Vector3(r, h * 0.2, r)
    local tm = tn:CreateComponent("StaticModel")
    tm.model = crystalModel_.tip
    tm.material = crystalMat_
    tm.instanceColor = col
    tm.castShadows = true
    return root
end

-- 灌木：两三个贴地叶团（叶片卡）
---@param scene Scene
function M.Bush(scene, x, gy, z, r, rng)
    Shared()
    local root = scene:CreateChild("Bush")
    root.position = Vector3(x, gy, z)
    local k = rng:Int(1, #GREENS)
    local leaves = NewLeaves(root)
    local n = rng:Int(2, 3)
    for i = 1, n do
        local a = rng:Range(0, 2 * pi)
        local d = (i == 1) and 0 or r * 0.55
        leaves:Clump(Vector3(cos(a) * d, r * 0.5, sin(a) * d), r * rng:Range(0.7, 0.95), rng, 34)
    end
    leaves:Finish(LeafMaterial("green" .. k, GREENS[k]))
    return root
end

return M
