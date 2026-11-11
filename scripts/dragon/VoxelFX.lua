-- ====================================================================
-- VoxelFX.lua — 体素风特效工具箱（龙息先用，之后的破坏特效也走这里）
--
--   * 像素贴图：硬边小图（方块 / 十字星 / 雪花 / 像素云团），最近邻采样，不做柔边
--   * Emitter：引擎粒子发射器的薄封装（大量粒子：吐息流、烟、火花）；
--     颜色按阶梯跳变（Steps），不做平滑渐变
--   * Motes：Lua 驱动的像素公告板粒子（需要自定义轨迹的：螺旋汇聚、绕束旋转、弹跳火星）
--   * Debris：真正的小立方体碎块（重力、落地弹跳、旋转、结尾逐级缩小）
--   * Crystal：程序化体素晶簇（真正的 VoxelVolume，从地里升起、碎裂成立方体碎块）
--   * GroundPainter：把地面体素临时改色（结霜 / 灼烧），可按半径蔓延和退回
-- 全部为纯视觉，不建物理体。
-- ====================================================================

local M = {}

local function Clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
local function Hash(n) return (math.sin(n * 127.1 + 311.7) * 43758.5453) % 1 end
M.Hash = Hash

-- ---------------------------------------------------------------- 像素贴图
-- 每种贴图是一张小图（字符画），'#' 实心、'+' 半亮、'.' 透明；放大显示时保持硬边。
local SPRITES = {
    square = {
        "######",
        "#++++#",
        "#++++#",
        "#++++#",
        "#++++#",
        "######",
    },
    cross = {
        "..#..",
        "..#..",
        "#####",
        "..#..",
        "..#..",
    },
    star = {
        "...#...",
        "...#...",
        "..+#+..",
        "###+###",
        "..+#+..",
        "...#...",
        "...#...",
    },
    flake = {
        "#..#..#",
        ".#.#.#.",
        "..###..",
        "###+###",
        "..###..",
        ".#.#.#.",
        "#..#..#",
    },
    cloud = {
        "...####...",
        "..######..",
        ".###++###.",
        "###++++###",
        "##++++++##",
        "##++++++##",
        "###++++###",
        ".###++###.",
        "..######..",
        "...####...",
    },
    dot = {
        "##",
        "##",
    },
}

---@type table<string, Texture2D>
local texCache = {}

---@return Texture2D
function M.Texture(kind)
    local cached = texCache[kind]
    if cached ~= nil then return cached end
    ---@type string[]
    local rows = SPRITES[kind] or SPRITES.square
    local h, w = #rows, #rows[1]
    -- 外留 1 像素透明边，避免最近邻采样在边缘取到相邻像素
    local W, H = w + 2, h + 2
    local img = Image()
    img:SetSize(W, H, 4)
    for y = 0, H - 1 do
        for x = 0, W - 1 do img:SetPixel(x, y, Color(0, 0, 0, 0)) end
    end
    for y = 1, h do
        local row = rows[y] or ""
        for x = 1, w do
            local ch = row:sub(x, x)
            if ch == "#" then img:SetPixel(x, y, Color(1, 1, 1, 1))
            elseif ch == "+" then img:SetPixel(x, y, Color(0.72, 0.72, 0.72, 1)) end
        end
    end
    local tex = Texture2D:new()
    tex:SetNumLevels(1)
    tex:SetFilterMode(FILTER_NEAREST)
    tex:SetData(img, true)
    texCache[kind] = tex
    return tex
end

-- 像素粒子材质（VoxelSprite.shader）：硬边、像素抖动淡出；glow = true 时颜色进 HDR 发光
function M.Material(kind, glow)
    local m = Material:new()
    if not m:SetSurfaceShader("Shaders/BLGL/VoxelSprite.shader") then
        print("VoxelFX: VoxelSprite.shader failed, fallback to particle technique")
        m:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffUnlitParticleAlpha.xml"))
        m:SetTexture(TU_DIFFUSE, M.Texture(kind))
        return m
    end
    m:SetSurfaceTexture("sprite_tex", M.Texture(kind))
    local rows = SPRITES[kind] or SPRITES.square
    m:SetShaderParameter("cells", Variant(#rows + 2))
    m:SetShaderParameter("glow", Variant(glow and 1.35 or 1.0))
    return m
end

-- 阶梯颜色：steps = { {t, Color}, ... }，每段颜色保持到下一个时间点再跳变
function M.Steps(fx, steps)
    for i, s in ipairs(steps) do
        fx:AddColorTime(s[2], s[1])
        local nxt = steps[i + 1]
        if nxt ~= nil then fx:AddColorTime(s[2], nxt[1] - 0.001) end
    end
end

-- ---------------------------------------------------------------- 引擎粒子发射器
---@class VoxelFXEmitter
---@field node Node
---@field fx ParticleEffect
---@field em ParticleEmitter
---@field on boolean
---@field rate number|nil

---@param parent Node
---@param o table { kind, additive, n, face, setup = function(fx) }
---@return VoxelFXEmitter
function M.Emitter(parent, name, o)
    local node = parent:CreateChild(name)
    local fx = ParticleEffect:new()
    fx:SetMaterial(M.Material(o.kind or "square", o.additive))
    fx:SetNumParticles(o.n or 300)
    fx:SetRelative(false)
    fx:SetUpdateInvisible(true)
    fx:SetMinEmissionRate(0)
    fx:SetMaxEmissionRate(0)
    o.setup(fx)
    local em = node:CreateComponent("ParticleEmitter")
    em:SetEffect(fx)
    em.castShadows = false
    if o.face ~= nil then em:SetFaceCameraMode(o.face) end
    em:SetEmitting(false)
    return { node = node, fx = fx, em = em, on = false }
end

---@param e VoxelFXEmitter
function M.SetEmit(e, on)
    if e.on ~= on then
        e.on = on
        e.em:SetEmitting(on)
    end
end

-- 调整发射率（同一个发射器在不同阶段喷得多 / 少）
---@param e VoxelFXEmitter
function M.SetRate(e, rate)
    if e.rate ~= rate then
        e.rate = rate
        e.fx:SetMinEmissionRate(rate * 0.85)
        e.fx:SetMaxEmissionRate(rate * 1.15)
    end
end

-- ---------------------------------------------------------------- Lua 驱动的像素粒子
---@class VoxelFXMotes
local Motes = {}
Motes.__index = Motes

---@param parent Node
function M.Motes(parent, name, n, kind, additive)
    local self = setmetatable({}, Motes)
    local node = parent:CreateChild(name)
    local bb = node:CreateComponent("BillboardSet")
    bb:SetMaterial(M.Material(kind, additive))
    bb:SetRelative(false)
    bb:SetSorted(false)
    bb.castShadows = false
    bb:SetNumBillboards(n)
    for i = 0, n - 1 do bb:GetBillboard(i).enabled = false end
    bb:Commit()
    self.bb, self.n, self.list, self.free = bb, n, {}, {}
    for i = n, 1, -1 do self.free[#self.free + 1] = i - 1 end
    return self
end

-- p = { pos, vel, life, size, colors = {Color...}（按寿命均分阶梯）, grav, drag, bounce, ground, fn(m, dt) }
function Motes:Spawn(p)
    local idx = table.remove(self.free)
    if idx == nil then return nil end
    p.idx, p.age = idx, 0.0
    p.vel = p.vel or Vector3(0, 0, 0)
    p.size = p.size or 0.1
    self.list[#self.list + 1] = p
    return p
end

function Motes:Update(dt)
    local bb, list = self.bb, self.list
    local keep = {}
    for _, m in ipairs(list) do
        m.age = m.age + dt
        local u = m.age / m.life
        if u >= 1 then
            bb:GetBillboard(m.idx).enabled = false
            self.free[#self.free + 1] = m.idx
        else
            if m.fn ~= nil then
                m.fn(m, dt, u)
            else
                if m.grav ~= nil then m.vel = m.vel + Vector3(0, -m.grav * dt, 0) end
                if m.drag ~= nil then m.vel = m.vel * math.max(0, 1 - m.drag * dt) end
                m.pos = m.pos + m.vel * dt
                if m.ground ~= nil and m.pos.y < m.ground then
                    m.pos = Vector3(m.pos.x, m.ground, m.pos.z)
                    local b = m.bounce or 0
                    m.vel = Vector3(m.vel.x * 0.6, -m.vel.y * b, m.vel.z * 0.6)
                end
            end
            local b = bb:GetBillboard(m.idx)
            b.enabled = true
            b.position = m.pos
            -- 尺寸也按阶梯：结尾两级缩小
            local s = m.size * ((u > 0.85) and 0.5 or ((u > 0.7) and 0.75 or 1.0))
            b.size = Vector2(s, s)
            local cs = m.colors
            local ci = math.min(#cs, math.floor(u * #cs) + 1)
            b.color = cs[ci]
            b.rotation = 0
            keep[#keep + 1] = m
        end
    end
    self.list = keep
    bb:Commit()
end

function Motes:Count() return #self.list end

function Motes:Clear()
    for _, m in ipairs(self.list) do
        self.bb:GetBillboard(m.idx).enabled = false
        self.free[#self.free + 1] = m.idx
    end
    self.list = {}
    self.bb:Commit()
end

-- ---------------------------------------------------------------- 立方体碎块
---@class VoxelFXDebrisItem
---@field node Node
---@field sm StaticModel
---@field pos Vector3
---@field vel Vector3

---@class VoxelFXDebris
local Debris = {}
Debris.__index = Debris

---@type table<string, Material>
local matCache = {}
-- 体素块材质（VoxelCube.shader）：纯色 + 自发光 + 边缘压暗；按颜色缓存
local function CubeMaterial(c, glow)
    local key = string.format("%.2f_%.2f_%.2f_%.2f", c.r, c.g, c.b, glow or 0)
    local m = matCache[key]
    if m ~= nil then return m end
    m = Material:new()
    local g = glow or 0
    if m:SetSurfaceShader("Shaders/BLGL/VoxelCube.shader") then
        m:SetShaderParameter("base_color", Variant(Color(c.r, c.g, c.b, 1.0)))
        m:SetShaderParameter("emit_color", Variant(Color(c.r * g, c.g * g, c.b * g, 1.0)))
    else
        m:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        m:SetShaderParameter("MatDiffColor", Variant(Color(c.r, c.g, c.b, 1.0)))
        m:SetShaderParameter("MatEmissiveColor", Variant(Color(c.r * g, c.g * g, c.b * g)))
    end
    matCache[key] = m
    return m
end
M.CubeMaterial = CubeMaterial

---@param parent Node
function M.Debris(parent, n)
    local self = setmetatable({}, Debris)
    self.items, self.free, self.live = {}, {}, {}
    local model = cache:GetResource("Model", "Models/Box.mdl")
    for i = 1, n do
        local node = parent:CreateChild("Cube" .. i)
        local sm = node:CreateComponent("StaticModel")
        sm:SetModel(model)
        sm.castShadows = (i % 3 == 0)
        node.enabled = false
        self.items[i] = { node = node, sm = sm }
        self.free[#self.free + 1] = self.items[i]
    end
    return self
end

-- p = { pos, vel, size, color, glow, life, spin, groundFn, bounce }
function Debris:Spawn(p)
    local it = table.remove(self.free)
    if it == nil then return nil end
    it.pos, it.vel, it.size, it.life, it.age = p.pos, p.vel or Vector3.ZERO, p.size or 0.1, p.life or 1.5, 0
    it.rot = Quaternion(math.random() * 360, math.random() * 360, math.random() * 360)
    it.spinAxis = Vector3(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5):Normalized()
    it.spin = p.spin or 360
    it.groundFn, it.bounce = p.groundFn, p.bounce or 0.35
    it.grav = p.grav or 22
    it.sm:SetMaterial(CubeMaterial(p.color, p.glow))
    it.node.enabled = true
    self.live[#self.live + 1] = it
    return it
end

function Debris:Update(dt)
    local keep = {}
    for _, it in ipairs(self.live) do
        it.age = it.age + dt
        local u = it.age / it.life
        if u >= 1 then
            it.node.enabled = false
            self.free[#self.free + 1] = it
        else
            it.vel = it.vel + Vector3(0, -it.grav * dt, 0)
            local p = Vector3(it.pos.x + it.vel.x * dt, it.pos.y + it.vel.y * dt, it.pos.z + it.vel.z * dt)
            local gy = it.groundFn ~= nil and it.groundFn(p.x, p.z) or -1e9
            local half = it.size * 0.5
            if p.y < gy + half then
                p = Vector3(p.x, gy + half, p.z)
                if math.abs(it.vel.y) > 1.2 then
                    it.vel = Vector3(it.vel.x * 0.55, -it.vel.y * it.bounce, it.vel.z * 0.55)
                    it.spin = it.spin * 0.6
                else
                    it.vel = Vector3(it.vel.x * 0.8, 0, it.vel.z * 0.8)
                    it.spin = it.spin * 0.9
                end
            end
            it.pos = p
            it.rot = Quaternion(it.spin * dt, it.spinAxis) * it.rot
            it.node.position = p
            it.node.rotation = it.rot
            -- 结尾逐级缩小（体素感：一档一档变小）
            local s = it.size * ((u > 0.9) and 0.35 or ((u > 0.78) and 0.65 or 1.0))
            it.node.scale = Vector3(s, s, s)
            keep[#keep + 1] = it
        end
    end
    self.live = keep
end

function Debris:Clear()
    for _, it in ipairs(self.live) do
        it.node.enabled = false
        self.free[#self.free + 1] = it
    end
    self.live = {}
end

-- ---------------------------------------------------------------- 体素晶簇
---@class VoxelFXCrystal
---@field holder Node
---@field volume VoxelVolume
---@field height number
---@field radius number
---@field voxels integer
---@field off Vector3
---@field base Vector3
---@field delay number
---@field yaw number
---@field state string
---@field grow number
---@field age number
---@field lean number
---@field out Vector3
---@field glint number

-- 一簇 = 一根主晶 + 若干侧晶，每根是倾斜的六棱锥台（截面用六边形距离）。
-- opts = { voxel, height, radius, count, seed, tip, mats = { body, edge, glow, light?, dark?, root? } }
-- 着色：每个六边形棱面按固定「伪光照」分亮 / 中 / 暗三档，棱线亮色竖条，顶端发光，根部冻土色带
-- 返回 { holder(Node), volume, height, colors = {Color...}, voxels }
---@param world VoxelPhysicsWorld
---@param parent Node
function M.Crystal(world, material, parent, name, opts)
    local s = opts.voxel
    local seed = opts.seed or 1
    local spikes = {}
    local count = opts.count or 3
    for i = 1, count do
        local main = (i == 1)
        local a = Hash(seed * 7.3 + i * 1.9) * math.pi * 2
        local tilt = main and (Hash(seed + 0.3) * 12) or (22 + Hash(seed * 3.1 + i) * 22)
        local h = opts.height * (main and 1.0 or (0.42 + 0.3 * Hash(seed * 1.7 + i * 5.1)))
        local r = opts.radius * (main and 1.0 or (0.55 + 0.25 * Hash(seed * 9.1 + i)))
        local off = main and 0 or (opts.radius * (0.7 + 0.5 * Hash(seed * 4.4 + i)))
        spikes[i] = { base = { math.cos(a) * off, 0, math.sin(a) * off }, h = h, r = r,
            dir = { math.cos(a) * math.sin(math.rad(tilt)), math.cos(math.rad(tilt)), math.sin(a) * math.sin(math.rad(tilt)) },
            spin = Hash(seed * 2.2 + i) * math.pi }
    end
    -- 包围盒
    local ext = opts.radius * 2.6 + opts.height * 0.5
    local nx = math.floor(2 * ext / s) + 2
    local ny = math.floor((opts.height * 1.05) / s) + 3
    local ox, oz = -nx * s * 0.5, -nx * s * 0.5
    local oy = -2 * s -- 根部埋进地面两格
    local vox = {}
    for ix = 0, nx - 1 do
        for iy = 0, ny - 1 do
            for iz = 0, nx - 1 do
                local x, y, z = ox + (ix + 0.5) * s, oy + (iy + 0.5) * s, oz + (iz + 0.5) * s
                ---@type {u: number, depth: number, edgeOff: number, shade: number}|nil
                local best, bestDepth = nil, 0
                for _, sp in ipairs(spikes) do
                    local px, py, pz = x - sp.base[1], y - sp.base[2], z - sp.base[3]
                    local t = px * sp.dir[1] + py * sp.dir[2] + pz * sp.dir[3]
                    if t > -2.5 * s and t < sp.h then
                        local qx, qy, qz = px - sp.dir[1] * t, py - sp.dir[2] * t, pz - sp.dir[3] * t
                        -- 径向两轴：任取与 dir 垂直的基
                        local ux, uy, uz = sp.dir[2], -sp.dir[1], 0
                        local ul = math.sqrt(ux * ux + uy * uy)
                        if ul < 1e-4 then ux, uy, uz, ul = 1, 0, 0, 1 end
                        ux, uy = ux / ul, uy / ul
                        local vx = sp.dir[2] * uz - sp.dir[3] * uy
                        local vy = sp.dir[3] * ux - sp.dir[1] * uz
                        local vz = sp.dir[1] * uy - sp.dir[2] * ux
                        local a2 = qx * ux + qy * uy + qz * uz
                        local b2 = qx * vx + qy * vy + qz * vz
                        local cs, sn = math.cos(sp.spin), math.sin(sp.spin)
                        a2, b2 = a2 * cs - b2 * sn, a2 * sn + b2 * cs
                        -- 六边形距离
                        local hex = math.max(math.abs(a2) * 0.866 + math.abs(b2) * 0.5, math.abs(b2))
                        local u = math.max(0, t) / sp.h
                        -- 顶部收尖（tip 以上线性收到尖；tip 大 = 更粗的柱状晶）
                        local tip = opts.tip or 0.62
                        local rr = sp.r * ((u < tip) and (1.0 - 0.15 * u) or ((1 - 0.15 * tip) * (1 - u) / (1 - tip)))
                        local depth = rr - hex
                        if depth > 0 and depth > bestDepth then
                            -- 所在棱面：六边形的 6 个面法线在 30° + 60°k；离面中心越远越靠近棱线
                            local ang = math.deg(math.atan(b2, a2))
                            local k = math.floor((ang - 30) / 60 + 0.5)
                            local fc = 30 + 60 * k
                            local off = math.abs(ang - fc)
                            -- 面法线转回体积空间，和固定的「伪光照」方向点乘 → 每个棱面一个明暗档
                            local fa = math.rad(fc) - sp.spin
                            local na, nb = math.cos(fa), math.sin(fa)
                            local nx3, ny3, nz3 = ux * na + vx * nb, uy * na + vy * nb, uz * na + vz * nb
                            local shade = nx3 * 0.62 + ny3 * 0.35 + nz3 * -0.7
                            best, bestDepth = { u = u, depth = depth, edgeOff = off, shade = shade }, depth
                        end
                    end
                end
                if best ~= nil then
                    local mats = opts.mats
                    local m
                    local h = Hash(ix * 3.1 + iy * 7.7 + iz * 1.3 + seed)
                    if best.u > 0.84 then m = mats.glow
                    elseif best.depth < s * 1.2 then
                        if best.edgeOff > 22 then m = mats.edge          -- 棱线：亮色竖条
                        elseif h > 0.93 then m = mats.glow               -- 零星闪点
                        elseif best.shade > 0.3 then m = mats.light or mats.edge
                        elseif best.shade < -0.25 then m = mats.dark or mats.body
                        else m = mats.body end
                        -- 根部一圈：冻土色带，像从地里挤出来
                        if best.u < 0.07 and mats.root ~= nil then m = mats.root end
                    else m = mats.body end
                    vox[#vox + 1] = { ix, iy, iz, m }
                end
            end
        end
    end
    local vol = world:CreateVolume(nx, ny, nx, s, Vector3.ZERO, Quaternion())
    local g = vol:GetGrid()
    for _, v in ipairs(vox) do
        g:SetSolid(v[1], v[2], v[3], true)
        g:SetVoxelMaterial(v[1], v[2], v[3], v[4])
    end
    vol.material = material
    vol:RebuildGeometry()
    local holder = parent:CreateChild(name)
    local node = vol:GetNode()
    node.temporary = true
    node:SetParent(holder)
    node.position = Vector3(ox, oy, oz)
    node.rotation = Quaternion()
    holder.enabled = false
    ---@type VoxelFXCrystal
    return { holder = holder, volume = vol, height = opts.height, radius = opts.radius, voxels = #vox }
end

-- ---------------------------------------------------------------- 地面改色
---@class VoxelFXGround
local Ground = {}
Ground.__index = Ground

-- volume：地面体积（单层）；origin：体积最小角世界坐标；cell：体素边长；layer：被改色的 y 层
---@param volume VoxelVolume
function M.GroundPainter(volume, origin, cell, layer)
    local self = setmetatable({}, Ground)
    self.volume, self.origin, self.cell, self.layer = volume, origin, cell, layer or 0
    self.grid = volume:GetGrid()
    local d = self.grid:GetDimensions()
    self.nx, self.nz = d.x, d.z
    self.saved = {}  -- key → 原材质
    self.dirty = nil
    return self
end

local function Key(i, k) return i * 4096 + k end

---@param i integer
---@param k integer
function Ground:Mark(i, k)
    ---@type integer[]|nil
    local d = self.dirty
    if d == nil then self.dirty = { i, k, i, k }
    else
        if i < d[1] then d[1] = i end
        if k < d[2] then d[2] = k end
        if i > d[3] then d[3] = i end
        if k > d[4] then d[4] = k end
    end
end

-- 以 (x, z) 为圆心、半径 radius 内尚未改色的格子按 pick(i, k, dist01) 改色
function Ground:Paint(x, z, radius, pick)
    local c, o = self.cell, self.origin
    local ci, ck = (x - o.x) / c, (z - o.z) / c
    local R = radius / c
    local i0, i1 = math.max(0, math.floor(ci - R)), math.min(self.nx - 1, math.floor(ci + R))
    local k0, k1 = math.max(0, math.floor(ck - R)), math.min(self.nz - 1, math.floor(ck + R))
    local y = self.layer
    for i = i0, i1 do
        for k = k0, k1 do
            local dx, dz = i + 0.5 - ci, k + 0.5 - ck
            local d = math.sqrt(dx * dx + dz * dz)
            -- 边缘带一点随机，蔓延轮廓不是正圆
            if d <= R * (0.82 + 0.18 * Hash(i * 13.1 + k * 7.9)) then
                local key = Key(i, k)
                local m = pick(i, k, d / math.max(R, 1e-3))
                if m ~= nil then
                    if self.saved[key] == nil then self.saved[key] = self.grid:GetVoxelMaterial(i, y, k) end
                    if self.grid:GetVoxelMaterial(i, y, k) ~= m then
                        self.grid:SetVoxelMaterial(i, y, k, m)
                        self:Mark(i, k)
                    end
                end
            end
        end
    end
end

-- 退回：离圆心超过 radius 的已改色格子恢复原色（radius <= 0 全部恢复）
function Ground:Recede(x, z, radius)
    local c, o, y = self.cell, self.origin, self.layer
    local R = radius / c
    local ci, ck = (x - o.x) / c, (z - o.z) / c
    for key, m in pairs(self.saved) do
        local i, k = key // 4096, key % 4096
        local dx, dz = i + 0.5 - ci, k + 0.5 - ck
        if radius <= 0 or math.sqrt(dx * dx + dz * dz) > R * (0.82 + 0.18 * Hash(i * 13.1 + k * 7.9)) then
            self.grid:SetVoxelMaterial(i, y, k, m)
            self.saved[key] = nil
            self:Mark(i, k)
        end
    end
end

function Ground:HasPaint() return next(self.saved) ~= nil end

-- 把累积的改动提交为一次局部重建
function Ground:Flush()
    ---@type integer[]|nil
    local d = self.dirty
    if d == nil then return end
    self.volume:MarkRegionDirty(d[1], self.layer, d[2], d[3], self.layer, d[4])
    self.dirty = nil
end

return M
