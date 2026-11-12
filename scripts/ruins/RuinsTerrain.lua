-- ====================================================================
-- RuinsTerrain.lua — 时之遗迹的地形
--
-- 两层（参考 Teardown / Hytale / 体素混合地形的通行做法）：
--   显示层：Terrain 高度图网格（0.5m 顶点间距、平滑高度），RuinsGround.shader 在世界空间
--           程序化混合 草地 / 泥土 / 铺石 / 岩壁；岩层倾斜 + 噪声扭曲，没有水平色带。
--           GrassField 在上面长出真实草叶与野花（设备不支持时退回卡片草簇）。
--   碰撞层：0.5m 体素（不可破坏），HiddenVoxel.shader 让它不渲染、不投影。
--           诺米的角色控制器、法术射线、碎块都只和体素碰撞，所以玩法完全不变。
--
-- 俯视同心圆布局（原点 = 龙庭中心，Y 向上，+Z 北）：
--
--            山脊（梯田状崖壁，r ≥ ~70，高 22–40m）
--        ┌──────────────────────────────────────┐
--        │  外环高台 y=6（48.5 ≤ r < 70）城墙 r=51 │
--        │   ┌──────────────────────────────┐   │
--        │   │ 峡谷 y≈-14（39.5 ≤ r < 48.5）   │   │
--        │   │   ┌──────────────────────┐   │   │
--        │   │   │ 内环平台 y=6（柱廊/碑） │   │   │
--        │   │   │   ┌──────────────┐   │   │   │
--        │   │   │   │ 龙庭 y=0 r<20.75│   │   │   │
--        │   │   │   └──────────────┘   │   │   │
--        │   │   │   南 / 北两条大阶梯：  │   │   │
--        │   │   │   |x|<3.5，每 1m 升 0.5m │   │   │
--        │   │   └──────────────────────┘   │   │
--        │   │  断桥（时之物件）横跨南侧峡谷   │   │
--        │   └──────────────────────────────┘   │
--        │  出生点 (0, 6, -64)  南城门 z=-51      │
--        └──────────────────────────────────────┘
-- 显示层与碰撞层的高度关系：
--   平地（内环 / 外环 y=6、龙庭）完全一致；缓坡上碰撞层取 0.5m 量化，误差 ≤ 0.25m。
--   大阶梯：碰撞层是 0.5m 台阶；显示层压低 0.6m 藏在 RuinsBuild 的石阶体积下面。
--   龙庭：显示层压到 -1.2m，藏在地砖体积下面。
-- ====================================================================

local Noise = require("ruins.Noise")
local Pal = require("ruins.RuinsPalette")
local P = Pal.P

local M = {}

M.CELL = 0.5
M.HALF = 84.0           -- 地形范围 [-84, 84]
M.Y_BASE = -18.0
M.Y_TOP = 46.0
M.COURT_R = 20.75       -- 龙庭边缘
M.RING_Y = 6.0          -- 内环 / 外环台面高度
M.RAVINE_IN = 39.5
M.RAVINE_OUT = 48.5
M.RAVINE_Y = -14.0
M.WALL_R = 51.0         -- 外城墙
M.RIM_R = 70.0
M.STAIR_HALF = 3.5      -- 大阶梯半宽
M.STAIR_END = 32.75     -- 阶梯顶端（离中心距离）
M.SNOW_Y = 31.0

local floor, sqrt, max, min, abs = math.floor, math.sqrt, math.max, math.min, math.abs

local function Smooth(e0, e1, x)
    local t = (x - e0) / (e1 - e0)
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return t * t * (3 - 2 * t)
end
M.Smooth = Smooth


-- 软台阶：平台宽、台缘陡（梯田）
local function SoftStep(v, step, sharp)
    local s = v / step
    local f = floor(s)
    return (f + Smooth(1 - sharp, 1, s - f)) * step
end

-- 是否在大阶梯走廊里（南北各一条）
function M.InStair(x, z)
    local d = abs(z)
    return abs(x) < M.STAIR_HALF and d >= M.COURT_R - 0.01 and d < M.STAIR_END
end

-- 阶梯台面高度（0.5m 一级、每级 1m 深）
function M.StairY(z)
    return min(M.RING_Y, 0.5 * floor((abs(z) - M.COURT_R) / 1.0 + 1))
end

-- 真实地表高度（平滑，米）。龙庭内返回 0（地砖顶面），阶梯返回台面
function M.Height(x, z)
    local r = sqrt(x * x + z * z)
    if r < M.COURT_R then return 0.0 end
    if M.InStair(x, z) then return M.StairY(z) end
    local a = math.atan(z, x)
    local ca, sa = math.cos(a), math.sin(a)
    -- 峡谷边缘带一点曲折
    local rin = M.RAVINE_IN + (Noise.Value2(ca * 6 + 10, sa * 6 + 10, 3) - 0.5) * 2.0
    local rout = M.RAVINE_OUT + (Noise.Value2(ca * 6 + 30, sa * 6 + 30, 4) - 0.5) * 2.0
    if r < rin - 0.5 then return M.RING_Y end
    if r < rout + 0.5 then
        -- 峡谷：两壁陡峭（0.5m 内完成落差，边缘崩一点），中段一级碎台，谷底起伏
        local e = min(r - rin, rout - r)
        local bottom = M.RAVINE_Y + Noise.Fbm2(x * 0.12, z * 0.12, 3, 7) * 3.0
        local shelf = M.RING_Y - 5.0 + Noise.Value2(x * 0.3, z * 0.3, 9) * 2.0
        if e < -0.0 then
            local k = Smooth(0.5, 0.0, -e)
            return M.RING_Y + (max(shelf, bottom) - M.RING_Y) * k
        end
        if e < 0.9 then return max(shelf, bottom) end
        if e < 1.6 then
            local k = Smooth(0.9, 1.6, e)
            return max(shelf, bottom) + (bottom + (shelf - bottom) * 0.35 - max(shelf, bottom)) * k
        end
        local e2 = Smooth(1.6, 3.5, e)
        return bottom + (shelf - bottom) * 0.35 * (1 - e2)
    end
    -- 外环高台 + 山脊
    local rimR = M.RIM_R + (Noise.Value2(ca * 3 + 50, sa * 3 + 50, 5) - 0.5) * 10.0
    local h = M.RING_Y
    if r > M.RAVINE_OUT + 3 and r < rimR - 2 then
        local n = Noise.Fbm2(x * 0.08, z * 0.08, 2, 11)
        if abs(x) > 4 then h = h + Smooth(0.55, 0.75, n) * 0.6 end
    end
    local rise = Smooth(rimR - 2, rimR + 12, r)
    if rise > 0 then
        local big = 14 + Noise.Fbm2(x * 0.03, z * 0.03, 4, 21) * 22
        local raw = rise * big + (Noise.Value2(x * 0.25, z * 0.25, 23) - 0.5) * 0.8
        -- 梯田：每 2.5m 一级，平台宽、台缘陡；台缘再叠一点碎岩起伏
        raw = SoftStep(max(0, raw), 2.5, 0.3) + Noise.Fbm2(x * 0.4, z * 0.4, 2, 24) * 0.5 * rise
        h = h + raw
    end
    return min(h, 44.0)
end

-- 碰撞层顶面高度（0.5m 量化，略偏向下取：宁可脚陷进草里一点，也不要悬空）
function M.CollideHeight(x, z)
    local r2 = x * x + z * z
    if r2 < (M.COURT_R - 0.25) ^ 2 then return -1.0 end -- 龙庭地砖体积自带碰撞
    if M.InStair(x, z) then return M.StairY(z) end
    return floor(M.Height(x, z) * 2.0 + 0.3) * 0.5
end

-- 显示层高度（藏在龙庭地砖 / 石阶下面）
function M.VisualHeight(x, z)
    local r2 = x * x + z * z
    if r2 < (M.COURT_R - 0.35) ^ 2 then return -1.2 end
    if M.InStair(x, z) then return M.StairY(z) - 0.6 end
    -- 阶梯两侧 0.5m 也压一点，避免网格斜面从扶墙下钻出来
    if abs(x) < M.STAIR_HALF + 0.5 and abs(z) >= M.COURT_R and abs(z) < M.STAIR_END then
        return min(M.Height(x, z), M.StairY(z) - 0.1)
    end
    return M.Height(x, z)
end

-- 岩石配色（浮岩等体素岩块用）：倾斜 + 三维噪声扭曲的岩层，避免水平环带
local STRATA = { P.CLIFF_A, P.CLIFF_B, P.CLIFF_D, P.CLIFF_B, P.CLIFF_C, P.CLIFF_A }

local function StrataAt(y, x, z)
    local warp = Noise.Value3(x * 0.15, y * 0.15, z * 0.15, 31) * 3.0
    local s = y * 0.8 + x * 0.12 + z * 0.07 + warp
    local band = floor(s + Noise.Hash3(floor(x * 4), floor(y * 4), floor(z * 4)) * 0.9)
    return STRATA[(band % #STRATA) + 1]
end
M.StrataAt = StrataAt

-- 是否属于铺路
function M.IsPath(x, z)
    local r = sqrt(x * x + z * z)
    -- 南侧主路：出生点 → 城门 → 桥
    if abs(x) < 2.0 + Noise.Value2(z * 0.4, 1, 41) * 0.8 and z < -M.RAVINE_OUT and z > -68 then return true end
    -- 内环铺石平台（柱廊一圈）
    if r >= M.COURT_R and r < 27.0 + (Noise.Value2(x * 0.3, z * 0.3, 42) - 0.5) * 1.5 then return true end
    -- 内环南北向直路（桥头 → 阶梯顶）
    if abs(x) < 3.0 and abs(z) >= M.STAIR_END - 0.5 and r < M.RAVINE_IN then return true end
    -- 北殿前的石板地
    if abs(x) < 11 and z > 52 and z < 67 then return true end
    return false
end

-- ---------------------------------------------------------------- 碰撞层（隐藏体素）
local hiddenMat_ = nil
local function HiddenMaterial()
    if hiddenMat_ ~= nil then return hiddenMat_ end
    local m = Material:new()
    if not m:SetSurfaceShader("Shaders/BLGL/HiddenVoxel.shader") then
        print("RuinsTerrain: HiddenVoxel.shader failed; collision voxels will be visible")
        return nil
    end
    hiddenMat_ = m
    return m
end

---@param world VoxelPhysicsWorld
local function BuildCollision(world)
    local t0 = os.clock()
    local c = M.CELL
    local N = math.tointeger(M.HALF * 2 / c) or 336
    local x0 = -M.HALF
    -- 格中心的平滑高度（HeightAt 用）+ 量化碰撞高度；多算一圈，用来判断侧面
    local H, C = {}, {}
    for i = -1, N do
        local row, crow = {}, {}
        local x = x0 + (i + 0.5) * c
        for k = -1, N do
            local z = x0 + (k + 0.5) * c
            row[k] = M.Height(x, z)
            crow[k] = M.CollideHeight(x, z)
        end
        H[i], C[i] = row, crow
    end
    M.heightMap = H
    print(string.format("RuinsTerrain: collision heightmap %dx%d in %.2fs", N, N, os.clock() - t0))

    local hidden = HiddenMaterial()
    local CH = 48
    local vols = {}
    for ci = 0, N - 1, CH do
        for ck = 0, N - 1, CH do
            local i1, k1 = min(N - 1, ci + CH - 1), min(N - 1, ck + CH - 1)
            local lo, hi = 1e9, -1e9
            for i = ci, i1 do
                local row = C[i]
                for k = ck, k1 do
                    local h = row[k]
                    local hn = min(h, C[i - 1][k], C[i + 1][k], row[k - 1], row[k + 1])
                    if hn < lo then lo = hn end
                    if h > hi then hi = h end
                end
            end
            local baseY = max(M.Y_BASE, lo - 2.0)
            local ny = math.tointeger(floor((hi - baseY) / c + 0.5)) or 1
            local nxC, nzC = i1 - ci + 1, k1 - ck + 1
            local vol = world:CreateVolume(nxC, max(1, ny), nzC, c, Vector3(x0 + ci * c, baseY, x0 + ck * c))
            local g = vol:GetGrid()
            for i = ci, i1 do
                local row = C[i]
                for k = ck, k1 do
                    local top = math.tointeger(floor((row[k] - baseY) / c + 0.5)) - 1
                    if top >= 0 then g:FillBox(i - ci, 0, k - ck, i - ci, top, k - ck, true) end
                end
            end
            g:PaintBox(0, 0, 0, nxC - 1, max(1, ny) - 1, nzC - 1, P.CLIFF_B)
            vol.destructible = false
            vol.evictable = false
            if hidden ~= nil then vol.material = hidden end
            world:FinalizeVolume(vol)
            vol:RebuildGeometry()
            vols[#vols + 1] = vol
        end
    end
    print(string.format("RuinsTerrain: %d collision chunks in %.2fs", #vols, os.clock() - t0))
    return vols
end

-- ---------------------------------------------------------------- 显示层（Terrain + 草）
-- 控制图：R 铺石路  G 泥土  B 强制岩面  A 草地密度（GrassField 读 A）
-- 像素 (px, py) ↔ 世界 x = -HALF + px * 0.5，z = +HALF - py * 0.5（第 0 行是 +Z 北侧，同 Terrain UV）
local function BuildSplat(VH, NV)
    local img = Image:new()
    img:SetSize(NV, NV, 4)
    local c = M.CELL
    local x0 = -M.HALF
    local GW = {}
    for i = 0, NV - 1 do GW[i] = {} end
    M.grassWeight = GW
    local function Hv(i, k)
        i = max(0, min(NV - 1, i))
        k = max(0, min(NV - 1, k))
        return VH[i][k]
    end
    for py = 0, NV - 1 do
        local k = NV - 1 - py
        local z = x0 + k * c
        for i = 0, NV - 1 do
            local x = x0 + i * c
            local h = VH[i][k]
            local r = sqrt(x * x + z * z)
            local slope = max(abs(Hv(i + 1, k) - Hv(i - 1, k)), abs(Hv(i, k + 1) - Hv(i, k - 1))) / (2 * c)
            local path = M.IsPath(x, z) and 1.0 or 0.0
            local court = r < M.COURT_R + 0.2 or M.InStair(x, z)
            -- 泥土：路边、峡谷底、零星斑块
            local dirt = Smooth(0.68, 0.8, Noise.Fbm2(x * 0.09, z * 0.09, 3, 81))
            if h < M.RAVINE_Y + 2.5 then dirt = max(dirt, 0.75) end
            if path < 0.5 then
                for _, d in ipairs({ { 1.2, 0 }, { -1.2, 0 }, { 0, 1.2 }, { 0, -1.2 } }) do
                    if M.IsPath(x + d[1], z + d[2]) then dirt = max(dirt, 0.55) end
                end
            end
            local rock = Smooth(0.9, 1.4, slope)
            if h > M.SNOW_Y then rock = max(rock, 0.3) end
            local grass = 1.0
            if court or path > 0.5 then grass = 0 end
            grass = grass * (1 - Smooth(0.55, 0.85, slope))
            grass = grass * (1 - dirt * 0.85)
            if h < M.RAVINE_Y + 2.5 then grass = grass * 0.35 end
            if h > M.SNOW_Y - 2 then grass = grass * Smooth(M.SNOW_Y, M.SNOW_Y - 2, h) end
            -- 稀疏处带一点随机空斑（草甸不是均匀地毯）
            grass = grass * (0.55 + 0.45 * Smooth(0.25, 0.55, Noise.Fbm2(x * 0.2, z * 0.2, 2, 83)))
            grass = max(0, min(1, grass))
            GW[i][k] = grass
            img:SetPixel(i, py, Color(path, dirt, rock, grass))
        end
    end
    local tex = Texture2D:new()
    tex:SetNumLevels(1)
    tex:SetData(img, true)
    tex:SetFilterMode(FILTER_BILINEAR)
    tex:SetAddressMode(COORD_U, ADDRESS_CLAMP)
    tex:SetAddressMode(COORD_V, ADDRESS_CLAMP)
    return tex
end

---@param scene Scene
local function BuildVisual(scene)
    local t0 = os.clock()
    local c = M.CELL
    local NV = (math.tointeger(M.HALF * 2 / c) or 336) + 1   -- 337 顶点
    local x0 = -M.HALF
    local VH = {}
    for i = 0, NV - 1 do
        local row = {}
        local x = x0 + i * c
        for k = 0, NV - 1 do row[k] = M.VisualHeight(x, x0 + k * c) end
        VH[i] = row
    end
    -- 16 位高度图：R = 高位、G = 低位（Terrain 对 ≥2 通道的图按 R + G/256 读取）
    local range = M.Y_TOP - M.Y_BASE
    local unit = range / 255.0
    local img = Image:new()
    img:SetSize(NV, NV, 3)
    for py = 0, NV - 1 do
        local k = NV - 1 - py
        for i = 0, NV - 1 do
            local v = (VH[i][k] - M.Y_BASE) / unit
            if v < 0 then v = 0 elseif v > 255.99 then v = 255.99 end
            local hiB = floor(v)
            local loB = floor((v - hiB) * 256)
            img:SetPixelInt(i, py, hiB | (loB << 8))
        end
    end
    local node = scene:CreateChild("RuinsGround")
    node.position = Vector3(0, M.Y_BASE, 0)
    local t = node:CreateComponent("Terrain")
    t.patchSize = 16
    t.spacing = Vector3(c, unit, c)
    t.smoothing = false
    t.maxLodLevels = 3
    t.lodBias = 2.0
    t.castShadows = true
    t.heightMap = img

    local splat = BuildSplat(VH, NV)
    M.splat = splat
    local mat = Material:new()
    if mat:SetSurfaceShader("Shaders/BLGL/RuinsGround.shader") then
        mat:SetSurfaceTexture("splat_map", splat)
        mat:SetShaderParameter("world_half", Variant(M.HALF))
        mat:SetShaderParameter("snow_y", Variant(M.SNOW_Y))
        mat:SetShaderParameter("deep_y", Variant(M.RAVINE_Y + 2.0))
    else
        print("RuinsTerrain: RuinsGround.shader failed, using PBRNoTexture")
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(Color(0.35, 0.5, 0.25)))
    end
    t.material = mat
    M.groundMaterial = mat
    M.terrain = t
    M.terrainNode = node
    -- 方向自检：Terrain:GetHeight 与解析高度应一致
    local probe = Vector3(-40, 0, 60)
    print(string.format("RuinsTerrain: visual %dx%d in %.2fs, probe terrain=%.2f expect=%.2f", NV, NV, os.clock() - t0,
        t:GetHeight(probe), M.VisualHeight(probe.x, probe.z)))
    return node
end

-- 草地：GrassField（GPU 草叶）+ 野花；不支持的设备退回卡片草簇
---@param scene Scene
local function BuildGrass(scene)
    local node = M.terrainNode
    local grass = node:CreateComponent("GrassField")
    if not grass.supported then
        print("RuinsTerrain: GrassField not supported, using tuft fallback")
        node:RemoveComponent(grass)
        M.grass = nil
        local Tufts = require("ruins.GrassTufts")
        M.tufts = Tufts.Build(scene, M)
        return
    end
    grass.densityMap = M.splat
    grass.densityChannel = 3
    grass.densityRange = Vector2(0.15, 0.75)
    grass.density = 110
    grass.bladeHeight = Vector2(0.22, 0.55)
    grass.bladeWidth = Vector2(0.008, 0.016)
    grass.clumpSize = 0.7
    grass.lean = 0.45
    grass.maxSlope = 42
    grass.viewDistance = 80
    grass.densityFalloffDistance = 22
    grass.castShadows = true
    grass.windDirection = Vector2(1, 0.35)
    grass.windStrength = 0.32
    grass.windSpeed = 3.5
    grass.gustSize = 14
    grass.flutter = 0.35
    grass.trampleRecoveryTime = 5
    local gm = grass.material:Clone()
    gm:SetShaderParameter("GrassRootColor", Variant(Vector4(0.020, 0.045, 0.012, 1.2)))
    gm:SetShaderParameter("GrassTipColor", Variant(Vector4(0.17, 0.30, 0.06, 0)))
    gm:SetShaderParameter("GrassDryColor", Variant(Vector4(0.32, 0.26, 0.08, 0.18)))
    grass.material = gm
    M.grass = grass
    -- 野花：白 / 金 / 时之蓝
    local fl = node:CreateComponent("GrassField")
    fl.plantType = GRASS_PLANT_FLOWER
    fl.densityMap = M.splat
    fl.densityChannel = 3
    fl.densityRange = Vector2(0.45, 0.95)
    fl.density = 2.5
    fl.bladeHeight = Vector2(0.38, 0.62)
    fl.bladeWidth = Vector2(0.003, 0.005)
    fl.flowerSize = 0.035
    fl.petalCount = 5
    fl.flowerCup = 0.3
    fl.viewDistance = 45
    fl.windDirection = grass.windDirection
    fl.windStrength = grass.windStrength
    fl.windSpeed = grass.windSpeed
    local fm = fl.material:Clone()
    fm:SetShaderParameter("GrassFlowerColor", Variant(Vector4(0.85, 0.85, 0.80, 0)))
    fm:SetShaderParameter("GrassFlowerColor2", Variant(Vector4(0.25, 0.42, 0.95, 0.35)))
    fm:SetShaderParameter("GrassFlowerCenter", Variant(Vector4(0.95, 0.70, 0.20, 0.3)))
    fl.material = fm
    M.flowers = fl
    print("RuinsTerrain: GrassField ready")
end

-- 显示层顶点网格上的草地权重（0..1）
function M.GrassAt(x, z)
    local GW = M.grassWeight --[[@as table<number, table<number, number>>?]]
    if GW == nil then return 0 end
    local i = floor((x + M.HALF) / M.CELL + 0.5)
    local k = floor((z + M.HALF) / M.CELL + 0.5)
    local row = GW[i]
    if row == nil then return 0 end
    return row[k] or 0
end

-- 角色 / 龙压草：每帧调用
function M.SetInteractor(slot, pos, radius)
    local g = M.grass --[[@as GrassField?]]
    if g ~= nil then g:SetInteractor(slot, pos, radius) end
    local fl = M.flowers --[[@as GrassField?]]
    if fl ~= nil then fl:SetInteractor(slot, pos, radius) end
end

---@param world VoxelPhysicsWorld
---@param scene Scene
function M.Build(world, scene)
    local t0 = os.clock()
    local vols = BuildCollision(world)
    BuildVisual(scene)
    local ok, err = pcall(BuildGrass, scene)
    if not ok then print("RuinsTerrain: grass FAILED: " .. tostring(err)) end
    print(string.format("RuinsTerrain: total %.2fs", os.clock() - t0))
    return { volumes = vols }
end

-- 查表取地面高度（平滑真实高度；建造 / 摆放时用；超出范围走解析函数）
function M.HeightAt(x, z)
    local H = M.heightMap --[[@as table<number, table<number, number>>?]]
    if H ~= nil then
        local i = floor((x + M.HALF) / M.CELL)
        local k = floor((z + M.HALF) / M.CELL)
        local row = H[i]
        if row ~= nil and row[k] ~= nil then return row[k] end
    end
    return M.Height(x, z)
end

return M
