-- ====================================================================
-- RuinsTerrain.lua — 时之遗迹的地形（0.5m 体素，按 24m 分块）
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
--        │   │   │   |x|<3.5，每 1m 降 0.5m │   │   │
--        │   │   └──────────────────────┘   │   │
--        │   │  断桥（时之物件）横跨南侧峡谷   │   │
--        │   └──────────────────────────────┘   │
--        │  出生点 (0, 6, -64)  南城门 z=-51      │
--        └──────────────────────────────────────┘
-- 龙庭地砖、柱廊、城墙等建筑在 RuinsBuild 里单独以 0.25m / 0.5m 体素搭建。
-- ====================================================================

local Noise = require("ruins.Noise")
local Pal = require("ruins.RuinsPalette")
local P = Pal.P

local M = {}

M.CELL = 0.5
M.HALF = 84.0           -- 地形范围 [-84, 84]
M.Y_BASE = -18.0
M.COURT_R = 20.75       -- 龙庭边缘
M.RING_Y = 6.0          -- 内环 / 外环台面高度
M.RAVINE_IN = 39.5
M.RAVINE_OUT = 48.5
M.RAVINE_Y = -14.0
M.WALL_R = 51.0         -- 外城墙
M.RIM_R = 70.0
M.STAIR_HALF = 3.5      -- 大阶梯半宽
M.STAIR_END = 32.75     -- 阶梯顶端（离中心距离）

local floor, sqrt, max, min, abs = math.floor, math.sqrt, math.max, math.min, math.abs

local function Smooth(e0, e1, x)
    local t = (x - e0) / (e1 - e0)
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return t * t * (3 - 2 * t)
end
M.Smooth = Smooth

local function Q(y) return floor(y / 0.5 + 0.5) * 0.5 end

-- 是否在大阶梯走廊里（南北各一条）
function M.InStair(x, z)
    local d = abs(z)
    return abs(x) < M.STAIR_HALF and d >= M.COURT_R - 0.01 and d < M.STAIR_END
end

-- 地表高度（顶面 Y）
function M.Height(x, z)
    local r = sqrt(x * x + z * z)
    if r < M.COURT_R then return -0.5 end -- 龙庭地砖在上面另建
    if M.InStair(x, z) then
        local d = abs(z)
        return min(M.RING_Y, 0.5 * floor((d - M.COURT_R) / 1.0 + 1))
    end
    local a = math.atan(z, x)
    local ca, sa = math.cos(a), math.sin(a)
    -- 峡谷边缘带一点曲折
    local rin = M.RAVINE_IN + (Noise.Value2(ca * 6 + 10, sa * 6 + 10, 3) - 0.5) * 2.0
    local rout = M.RAVINE_OUT + (Noise.Value2(ca * 6 + 30, sa * 6 + 30, 4) - 0.5) * 2.0
    if r < rin then return M.RING_Y end
    if r < rout then
        -- 峡谷：两壁陡峭，中段一级碎台阶，谷底起伏
        local e = min(r - rin, rout - r)
        local bottom = M.RAVINE_Y + Noise.Fbm2(x * 0.12, z * 0.12, 3, 7) * 3.0
        local shelf = M.RING_Y - 5.0 + Noise.Value2(x * 0.3, z * 0.3, 9) * 2.0
        if e < 0.9 then return Q(max(shelf, bottom)) end
        if e < 1.6 then return Q(bottom + (shelf - bottom) * 0.35) end
        return Q(bottom)
    end
    -- 外环高台 + 山脊
    local rimR = M.RIM_R + (Noise.Value2(ca * 3 + 50, sa * 3 + 50, 5) - 0.5) * 10.0
    local h = M.RING_Y
    if r > M.RAVINE_OUT + 3 and r < rimR - 2 then
        local n = Noise.Value2(x * 0.08, z * 0.08, 11)
        if n > 0.66 and abs(x) > 4 then h = h + 0.5 end
    end
    local rise = Smooth(rimR - 2, rimR + 12, r)
    if rise > 0 then
        local big = 14 + Noise.Fbm2(x * 0.03, z * 0.03, 4, 21) * 22
        local raw = rise * big
        -- 梯田：每 2m 一级，台缘略有起伏
        local step = 2.0
        raw = floor(raw / step + Noise.Value2(x * 0.25, z * 0.25, 23) * 0.6) * step
        h = h + raw
    end
    return min(Q(h), 44.0)
end

-- 地表材质（顶层）
local GRASS = { P.GRASS_A, P.GRASS_B, P.GRASS_C, P.GRASS_A, P.GRASS_D }
local STRATA = { P.CLIFF_A, P.CLIFF_B, P.CLIFF_D, P.CLIFF_B, P.CLIFF_C, P.CLIFF_A }

local function StrataAt(y, x, z)
    local band = floor((y + 30) / 1.5 + Noise.Value2(x * 0.05, z * 0.05, 31) * 1.2)
    return STRATA[(band % #STRATA) + 1]
end
M.StrataAt = StrataAt

-- 是否属于铺路（材质用）
function M.IsPath(x, z)
    local r = sqrt(x * x + z * z)
    -- 南侧主路：出生点 → 城门 → 桥
    if abs(x) < 2.0 + Noise.Value2(z * 0.4, 1, 41) * 0.8 and z < -M.RAVINE_OUT and z > -68 then return true end
    -- 内环铺石平台（柱廊一圈）
    if r >= M.COURT_R and r < 27.0 then return true end
    -- 内环南北向直路（桥头 → 阶梯顶）
    if abs(x) < 3.0 and abs(z) >= M.STAIR_END - 0.5 and r < M.RAVINE_IN then return true end
    return false
end

-- 构建全部地形块；返回 { volumes = {...} }
---@param world VoxelPhysicsWorld
function M.Build(world)
    local t0 = os.clock()
    local c = M.CELL
    local N = math.tointeger(M.HALF * 2 / c) or 336
    local x0 = -M.HALF
    -- 先算整张高度图（多算一圈，用来判断坡度）
    local H = {}
    for i = -1, N do
        local row = {}
        local x = x0 + (i + 0.5) * c
        for k = -1, N do
            row[k] = M.Height(x, x0 + (k + 0.5) * c)
        end
        H[i] = row
    end
    M.heightMap = H
    print(string.format("RuinsTerrain: heightmap %dx%d in %.2fs", N, N, os.clock() - t0))

    local CH = 48
    local vols = {}
    local nChunks = 0
    for ci = 0, N - 1, CH do
        for ck = 0, N - 1, CH do
            local i1, k1 = min(N - 1, ci + CH - 1), min(N - 1, ck + CH - 1)
            local lo, hi = 1e9, -1e9
            for i = ci, i1 do
                local row = H[i]
                for k = ck, k1 do
                    local h = row[k]
                    -- 相邻列最低点也要覆盖（崖壁侧面需要实心）
                    local hn = min(h, H[i - 1][k], H[i + 1][k], row[k - 1], row[k + 1])
                    if hn < lo then lo = hn end
                    if h > hi then hi = h end
                end
            end
            local baseY = max(M.Y_BASE, lo - 2.0)
            local ny = math.tointeger(floor((hi - baseY) / c + 0.5)) or 1
            local nxC, nzC = i1 - ci + 1, k1 - ck + 1
            local vol = world:CreateVolume(nxC, ny, nzC, c, Vector3(x0 + ci * c, baseY, x0 + ck * c))
            local g = vol:GetGrid()
            for i = ci, i1 do
                local row = H[i]
                for k = ck, k1 do
                    local top = math.tointeger(floor((row[k] - baseY) / c + 0.5)) - 1
                    if top >= 0 then g:FillBox(i - ci, 0, k - ck, i - ci, top, k - ck, true) end
                end
            end
            -- 岩层：整块按高度带刷
            local cx, cz = x0 + (ci + CH * 0.5) * c, x0 + (ck + CH * 0.5) * c
            for j = 0, ny - 1 do
                local y = baseY + (j + 0.5) * c
                g:PaintBox(0, j, 0, nxC - 1, j, nzC - 1, StrataAt(y, cx, cz))
            end
            -- 顶层：草 / 土 / 路 / 深谷岩 / 雪
            for i = ci, i1 do
                local row = H[i]
                local x = x0 + (i + 0.5) * c
                for k = ck, k1 do
                    local h = row[k]
                    local top = math.tointeger(floor((h - baseY) / c + 0.5)) - 1
                    if top >= 0 then
                        local z = x0 + (k + 0.5) * c
                        local drop = h - min(H[i - 1][k], H[i + 1][k], row[k - 1], row[k + 1])
                        local li, lk = i - ci, k - ck
                        local hsh = Noise.Hash2(i, k)
                        if h <= M.RAVINE_Y + 2.5 then
                            g:PaintBox(li, top, lk, li, top, lk, (hsh < 0.5) and P.DEEP_A or P.DEEP_B)
                        elseif h >= 32 then
                            g:PaintBox(li, top, lk, li, top, lk, P.SNOW)
                        elseif drop <= 1.0 then
                            local m
                            if M.IsPath(x, z) then
                                m = (hsh < 0.7) and P.PATH or P.PATH_B
                                if hsh > 0.93 then m = P.GRASS_C end
                            else
                                local n = Noise.Value2(x * 0.15, z * 0.15, 61)
                                m = GRASS[math.min(#GRASS, floor((n * 0.7 + hsh * 0.3) * #GRASS) + 1)]
                                if hsh > 0.985 then m = P.FLOWER_W elseif hsh > 0.975 then m = P.FLOWER_Y
                                elseif hsh > 0.968 and h > 5 and h < 8 then m = P.FLOWER_B end
                            end
                            g:PaintBox(li, top, lk, li, top, lk, m)
                            if top >= 1 and not M.IsPath(x, z) then
                                local d0 = math.max(0, top - 2)
                                g:PaintBox(li, d0, lk, li, top - 1, lk, (hsh < 0.5) and P.DIRT or P.DIRT_B)
                            end
                        end
                    end
                end
            end
            vol.destructible = false
            vol.evictable = false
            world:FinalizeVolume(vol)
            vol:RebuildGeometry()
            vols[#vols + 1] = vol
            nChunks = nChunks + 1
        end
    end
    print(string.format("RuinsTerrain: %d chunks in %.2fs", nChunks, os.clock() - t0))
    print("RuinsTerrain: returning")
    return { volumes = vols }
end

-- 查表取地面高度（建造 / 摆放时用；超出范围走解析函数）
function M.HeightAt(x, z)
    local H = M.heightMap
    if H ~= nil then
        local i = floor((x + M.HALF) / M.CELL)
        local k = floor((z + M.HALF) / M.CELL)
        local row = H[i]
        if row ~= nil and row[k] ~= nil then return row[k] end
    end
    return M.Height(x, z)
end

return M
