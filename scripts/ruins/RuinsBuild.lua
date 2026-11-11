-- ====================================================================
-- RuinsBuild.lua — 时之遗迹的静态建筑与景观（不含谜题物件，谜题见 RuinsPuzzles）
--
-- 全部是静态体素体积（destructible = false，诺米的碎时只对时之物件和乱石生效）。
-- 主要部件（原点 = 龙庭中心）：
--   龙庭地砖 r<20.75（0.25m 体素）：同心圆环 + 金色时之法阵（可点亮）
--   龙庭祭坛：中心偏北的低台，龙卧在上面
--   内环柱廊：r=23.5 共 24 根柱，部分倒塌；柱顶残留横梁
--   半塌穹顶：从柱廊升起的 6 根肋拱，向中心弯曲，只有 2 根完整
--   四座时之碑底座（谜题 4 的碑体由 RuinsPuzzles 放置）
--   外城墙 r=51（带垛口、南门、北门、残缺段）+ 4 座角楼（1 座倒塌）
--   北侧大殿遗址（外环北，台基 + 断柱 + 后墙 + 巨像）
--   悬浮碎岩（龙庭上空，缓慢漂浮，纯视觉体积）
--   植被：金叶古树、普通树、灌木；蓝色时晶簇
-- ====================================================================

local Brush = require("ruins.VoxelBrush")
local Noise = require("ruins.Noise")
local Pal = require("ruins.RuinsPalette")
local Terrain = require("ruins.RuinsTerrain")
local P = Pal.P

local M = {}

local sin, cos, sqrt, floor, abs, max, min, pi = math.sin, math.cos, math.sqrt, math.floor, math.abs, math.max, math.min, math.pi
local Hash3 = Noise.Hash3

local function Stone(x, y, z)
    local h = Hash3(floor(x * 4), floor(y * 4), floor(z * 4))
    if h < 0.45 then return P.STONE_A elseif h < 0.8 then return P.STONE_B elseif h < 0.95 then return P.STONE_C end
    return P.STONE_D
end
-- 带苔藓：越靠下越多，上表面也长
local function MossyStone(x, y, z, base)
    local h = Hash3(floor(x * 4) + 7, floor(y * 4), floor(z * 4))
    local n = Noise.Value3(x * 0.8, y * 0.8, z * 0.8, 3)
    if n > 0.62 and h < 0.7 then return P.STONE_MOSS end
    if base ~= nil and y - base < 0.6 and h < 0.35 then return P.STONE_MOSS end
    return Stone(x, y, z)
end
local function Marble(x, y, z)
    local h = Hash3(floor(x * 4) + 3, floor(y * 4), floor(z * 4))
    if h < 0.55 then return P.MARBLE_A elseif h < 0.92 then return P.MARBLE_B end
    return P.STONE_A
end
M.Stone, M.Marble, M.MossyStone = Stone, Marble, MossyStone

M.volumes = {}
local function Keep(v) if v ~= nil then M.volumes[#M.volumes + 1] = v end return v end

-- ---------------------------------------------------------------- 龙庭地砖 + 法阵
-- 法阵图案（极坐标）：外双环、12 刻度、时钟指针（两根）、内三环、中心沙漏符号
local function RuneAt(x, z)
    local r = sqrt(x * x + z * z)
    local a = math.atan(z, x)
    local function ring(R, w) return abs(r - R) < w end
    if ring(19.6, 0.3) or ring(18.6, 0.15) then return 1 end
    -- 刻度：12 个
    local seg = (a / (2 * pi) * 12) % 1
    if r > 17.2 and r < 18.4 and (seg < 0.04 or seg > 0.96) then return 2 end
    -- 罗马数字位：每个刻度外侧一个小方块
    if r > 16.4 and r < 17.0 and (seg > 0.46 and seg < 0.54) then return 2 end
    if ring(15.8, 0.15) then return 1 end
    -- 中环：24 段虚线
    local seg24 = (a / (2 * pi) * 24) % 1
    if ring(12.0, 0.25) and seg24 > 0.15 and seg24 < 0.85 then return 1 end
    -- 时钟指针：时针 / 分针（宽度随半径收窄）
    local function hand(ang, len, w)
        local dx, dz = cos(ang), sin(ang)
        local t = x * dx + z * dz
        local d = abs(-x * dz + z * dx)
        return t > 0 and t < len and d < w * (1 - t / len * 0.6)
    end
    if hand(pi * 0.5 + 0.35, 14.5, 0.55) then return 2 end
    if hand(pi * 0.5 - 2.1, 10.0, 0.7) then return 2 end
    if ring(7.5, 0.2) or ring(6.6, 0.12) then return 1 end
    -- 内部：六芒星（两个三角）
    local function tri(rot, R)
        local inside = true
        for i = 0, 2 do
            local an = rot + i * 2 * pi / 3
            local nx, nz = cos(an), sin(an)
            if x * nx + z * nz > R * 0.5 then inside = false end
        end
        return inside
    end
    local t1, t2 = tri(pi / 2, 6.4), tri(-pi / 2, 6.4)
    local t1i, t2i = tri(pi / 2, 5.7), tri(-pi / 2, 5.7)
    if (t1 and not t1i) or (t2 and not t2i) then return 1 end
    if ring(2.4, 0.18) then return 2 end
    return 0
end
M.RuneAt = RuneAt

local function BuildCourtFloor(world)
    local R = Terrain.COURT_R
    -- 4 块拼成（每块 21m × 42m 太大，按象限拆，0.25m 体素）
    local quads = { { -R, 0, -R, 0 }, { 0, R, -R, 0 }, { -R, 0, 0, R }, { 0, R, 0, R } }
    for _, q in ipairs(quads) do
        local b = Brush.New(world, { min = { q[1], -1.0, q[3] }, max = { q[2], 0.0, q[4] }, size = 0.25 })
        b:Shape(q[1], -1.0, q[3], q[2], 0.0, q[4], function(x, y, z)
            local r = sqrt(x * x + z * z)
            if r >= R then return nil end
            if y < -0.5 then return P.STONE_C end
            -- 顶层：法阵 / 地砖缝 / 磨损
            local rn = RuneAt(x, z)
            if y > -0.25 then
                if rn == 1 then return P.FLOOR_RUNE_B end
                if rn == 2 then return P.FLOOR_RUNE_G end
                -- 地砖：同心环 + 放射缝
                local ringI = floor(r / 1.5)
                local a = math.atan(z, x)
                local segN = max(6, floor(r * 0.9))
                local segF = ((a / (2 * pi) + 0.5) * segN + ringI * 0.37) % 1
                local h = Hash3(ringI, floor((a / (2 * pi) + 0.5) * segN + ringI * 0.37), 5)
                if (r % 1.5) < 0.16 or segF < 0.05 then return P.TILE_C end
                -- 破损缺块：偶尔一块砖下沉（挖空顶层）
                if h > 0.965 and r > 8 then return false end
                if h > 0.93 then return P.GRASS_C end
                if h < 0.5 then return P.TILE_A end
                return P.TILE_B
            end
            return P.STONE_B
        end)
        Keep(b:Finish({}))
    end
end

-- ---------------------------------------------------------------- 祭坛（龙卧处）
local function BuildAltar(world)
    -- 中心 (0, 0, 4)，低圆台 r=6.5 高 0.5，外圈台阶；北侧一道弧形矮墙当背景
    local b = Brush.New(world, { min = { -8, 0, -4 }, max = { 8, 3.5, 13 }, size = 0.25 })
    b:Shape(-8, 0, -4, 8, 0.5, 12, function(x, y, z)
        local dz = z - 4
        local r = sqrt(x * x + dz * dz)
        if r < 6.5 or (r < 7.2 and y < 0.25) then
            if y > 0.25 and r > 6.2 then return P.GOLD_DARK end
            if y > 0.25 and abs(r - 4.0) < 0.15 then return P.FLOOR_RUNE_G end
            return Marble(x, y, z)
        end
    end)
    -- 背后弧墙：半径 7.5，北侧 120°，高 1.2–2.8（起伏残缺）
    b:Shape(-8, 0, 4, 8, 3.5, 13, function(x, y, z)
        local dz = z - 4
        local r = sqrt(x * x + dz * dz)
        if abs(r - 7.6) > 0.4 then return nil end
        local a = math.atan(dz, x)
        if a < pi * 0.2 or a > pi * 0.8 then return nil end
        local top = 1.2 + 1.6 * Noise.Value2(a * 6, 2, 17)
        if y > top then return nil end
        if y > top - 0.25 then return P.GOLD end
        return MossyStone(x, y, z, 0)
    end)
    Keep(b:Finish({}))
end

-- ---------------------------------------------------------------- 柱子工具
-- 带柱础 / 凹槽 / 柱头的圆柱；broken = 断裂高度（nil = 完整）
local function Column(b, cx, cz, baseY, height, r, broken, gold)
    local top = broken or height
    -- 柱础
    b:Shape(cx - r - 0.5, baseY, cz - r - 0.5, cx + r + 0.5, baseY + 0.75, cz + r + 0.5, function(x, y, z)
        local dx, dz = abs(x - cx), abs(z - cz)
        local e = (y - baseY < 0.4) and (r + 0.45) or (r + 0.25)
        if dx <= e and dz <= e then return Marble(x, y, z) end
    end)
    -- 柱身：12 道凹槽
    local breakN = Noise.Rng(floor(cx * 13 + cz * 7))
    b:Shape(cx - r, baseY + 0.75, cz - r, cx + r, baseY + top, cz + r, function(x, y, z)
        local dx, dz = x - cx, z - cz
        local d = sqrt(dx * dx + dz * dz)
        local a = math.atan(dz, dx)
        local flute = (a / (2 * pi) * 12) % 1
        local rr = r - ((flute > 0.35 and flute < 0.65) and 0.13 or 0)
        if d > rr then return nil end
        -- 断口：参差不齐
        if broken ~= nil then
            local cut = baseY + broken - 0.6 * Noise.Value2(dx * 2 + cx, dz * 2 + cz, 21)
            if y > cut then return nil end
        end
        if y - baseY < 1.6 and Noise.Value3(x * 1.4, y * 1.4, z * 1.4, 5) > 0.66 then return P.STONE_MOSS end
        if gold and abs(y - baseY - height * 0.62) < 0.13 then return P.GOLD end
        return Marble(x, y, z)
    end)
    -- 柱头
    if broken == nil then
        b:Shape(cx - r - 0.6, baseY + height, cz - r - 0.6, cx + r + 0.6, baseY + height + 0.9, cz + r + 0.6, function(x, y, z)
            local dx, dz = abs(x - cx), abs(z - cz)
            local k = (y - baseY - height) / 0.9
            local e = r + 0.1 + 0.5 * k
            if dx <= e and dz <= e then
                if k > 0.7 and (dx > e - 0.26 or dz > e - 0.26) then return P.GOLD_DARK end
                return Marble(x, y, z)
            end
        end)
    end
end
M.Column = Column

-- ---------------------------------------------------------------- 内环柱廊
M.COLONNADE_R = 23.6
local COL_N = 24
local function BuildColonnade(world)
    local R = M.COLONNADE_R
    local H = 7.0
    local baseY = Terrain.RING_Y
    -- 柱廊分 4 个象限体积
    local broken = {}
    local rng = Noise.Rng(77)
    for i = 0, COL_N - 1 do
        local a = (i + 0.5) / COL_N * 2 * pi
        -- 南北阶梯口两侧柱子完整；其余 1/3 倒塌
        local h = rng:Next()
        local nearStair = abs(sin(a)) > 0.97
        if not nearStair and h < 0.35 then broken[i] = 1.2 + rng:Next() * 3.5 else broken[i] = nil end
        if i == 5 or i == 17 then broken[i] = nil end
    end
    M.colBroken = broken
    for qd = 0, 3 do
        local x0, x1 = (qd % 2 == 0) and -R - 2 or 0, (qd % 2 == 0) and 0 or R + 2
        local z0, z1 = (qd < 2) and -R - 2 or 0, (qd < 2) and 0 or R + 2
        local b = Brush.New(world, { min = { x0, baseY, z0 }, max = { x1, baseY + H + 2.5, z1 }, size = 0.25 })
        for i = 0, COL_N - 1 do
            local a = (i + 0.5) / COL_N * 2 * pi
            local cx, cz = cos(a) * R, sin(a) * R
            if cx >= x0 and cx < x1 and cz >= z0 and cz < z1 then
                Column(b, cx, cz, baseY, H, 0.75, broken[i], true)
            end
        end
        -- 横梁：相邻两根都完整时连一段梁（弧形，沿圆周）
        b:Shape(x0, baseY + H + 0.9, z0, x1, baseY + H + 1.9, z1, function(x, y, z)
            local r = sqrt(x * x + z * z)
            if abs(r - R) > 0.75 then return nil end
            local a = math.atan(z, x)
            if a < 0 then a = a + 2 * pi end
            local f = a / (2 * pi) * COL_N - 0.5
            local i0 = floor(f) % COL_N
            local i1 = (i0 + 1) % COL_N
            if broken[i0] ~= nil or broken[i1] ~= nil then return nil end
            -- 梁有断：哈希
            if Hash3(i0, 3, 9) < 0.3 then return nil end
            local ly = y - baseY - H - 0.9
            if ly > 0.75 then
                -- 梁顶装饰齿
                if (f * 8) % 1 < 0.5 then return Marble(x, y, z) end
                return nil
            end
            if ly < 0.25 and abs(r - R) > 0.5 then return nil end
            if abs(ly - 0.4) < 0.13 then return P.GOLD end
            return Marble(x, y, z)
        end)
        Keep(b:Finish({}))
    end
end

-- 倒塌柱段散落在柱廊附近（躺倒的柱节，静态）
local function BuildFallenColumns(world)
    local R = M.COLONNADE_R
    local rng = Noise.Rng(91)
    for i, h in pairs(M.colBroken or {}) do
        if rng:Next() < 0.75 then
            local a = (i + 0.5) / COL_N * 2 * pi
            local out = rng:Next() < 0.5
            local cx = cos(a) * (R + (out and 2.0 or -1.8))
            local cz = sin(a) * (R + (out and 2.0 or -1.8))
            if abs(cx) > 4.5 then
                local yaw = math.deg(a) + rng:Range(-50, 50) + 90
                local len = rng:Range(2.0, 3.6)
                local gy = Terrain.HeightAt(cx, cz)
                if sqrt(cx * cx + cz * cz) < Terrain.COURT_R then gy = 0 end
                local b = Brush.New(world, { origin = Vector3(cx, gy, cz), yaw = yaw, min = { -len / 2, 0, -0.8 }, max = { len / 2, 1.6, 0.8 }, size = 0.25 })
                b:Shape(-len / 2, 0, -0.8, len / 2, 1.6, 0.8, function(x, y, z)
                    local dy, dz = y - 0.72, z
                    local d = sqrt(dy * dy + dz * dz)
                    if d > 0.75 then return nil end
                    -- 断口两端不平
                    if abs(x) > len / 2 - 0.4 * Noise.Value2(dy * 3, dz * 3, i) then return nil end
                    if y > 1.1 and Hash3(floor(x * 4), floor(y * 4), floor(z * 4)) < 0.35 then return P.STONE_MOSS end
                    return Marble(x, y, z)
                end)
                Keep(b:Finish({}))
            end
        end
    end
end

-- ---------------------------------------------------------------- 半塌穹顶肋拱
-- 肋拱从柱廊 r=23.6 处（柱顶 y=13）向中心升起，四分之一椭圆，顶点在 (r=0, y=34)。
-- 完整的 2 根汇到顶部的残环；其余在不同高度断掉，断口下方散落碎石（静态）。
M.DOME_TOP = 34.0
local function BuildDomeRibs(world)
    local R = M.COLONNADE_R
    local y0 = Terrain.RING_Y + 8.9
    local yTop = M.DOME_TOP
    local ribs = {
        { a = 30, keep = 1.0 }, { a = 90, keep = 0.42 }, { a = 150, keep = 1.0 },
        { a = 210, keep = 0.55 }, { a = 270, keep = 0.30 }, { a = 330, keep = 0.66 },
    }
    M.ribs = ribs
    for ri, rib in ipairs(ribs) do
        local ang = math.rad(rib.a)
        -- 局部坐标：x 沿半径（0 = 中心，R = 柱廊），y 向上，z 横向厚度
        -- 绕 Y 转 yaw：局部 +X → (cos yaw, 0, -sin yaw)，所以 yaw = -a 时 +X 指向 (cos a, 0, sin a)
        local yaw = -rib.a
        local b = Brush.New(world, { origin = Vector3(0, 0, 0), yaw = yaw, min = { -2, y0 - 0.5, -1.2 }, max = { R + 1.5, yTop + 2.5, 1.2 }, size = 0.25 })
        local keepT = rib.keep
        b:Shape(-2, y0 - 0.5, -1.2, R + 1.5, yTop + 2.5, 1.2, function(x, y, z)
            -- 椭圆：((R - x)/R)^2 + ((y - y0)/(yTop - y0))^2 = 1 外沿，厚 1.1m
            -- 四分之一椭圆 (x/R)^2 + ((y-y0)/hy)^2 = 1：x=R 处在柱顶 y0，x=0 处在穹顶 yTop
            local u = x / R
            if u < -0.06 or u > 1.06 then return nil end
            local hy = yTop - y0
            local v = (y - y0) / hy
            if v < -0.02 then return nil end
            local e = u * u + v * v
            local thick = 1.1 / R
            if e > 1.0 or e < (1.0 - thick * 2.2) then return nil end
            local phi = math.atan(v, u) / (pi / 2) -- 0 = 起拱（柱顶），1 = 穹顶中心
            if phi > keepT then
                -- 断口参差
                local cut = keepT + 0.025 * (Noise.Value2(y * 2, z * 3, ri) - 0.5)
                if phi > cut then return nil end
            end
            -- 宽度：靠中心收窄
            if abs(z) > 1.05 - 0.35 * phi then return nil end
            local outer = e > 1.0 - thick * 0.6
            if outer and abs(z) < 0.3 then return P.GOLD end
            if not outer and (y * 2) % 1 < 0.15 and abs(z) > 0.5 then return P.GOLD_DARK end
            if outer and Noise.Value3(x * 0.9, y * 0.9, z, 7) > 0.68 then return P.STONE_MOSS end
            return Marble(x, y, z)
        end)
        Keep(b:Finish({}))
    end
    -- 穹顶残环（顶点环，r=2.2 粗 0.9，只有两根完整肋拱连着；略带破口）
    local b = Brush.New(world, { min = { -4, yTop - 1.6, -4 }, max = { 4, yTop + 1.2, 4 }, size = 0.25 })
    b:Shape(-4, yTop - 1.6, -4, 4, yTop + 1.2, 4, function(x, y, z)
        local r = sqrt(x * x + z * z)
        local dr = r - 2.6
        local dy = y - (yTop - 0.3)
        if dr * dr + dy * dy > 0.75 * 0.75 then return nil end
        local a = math.deg(math.atan(z, x)) % 360
        if a > 230 and a < 300 then return nil end -- 破口
        if dr > 0.3 then return P.GOLD end
        return Marble(x, y, z)
    end)
    -- 残环下方垂挂的蓝色时晶（发光）
    b:Shape(-4, yTop - 1.6, -4, 4, yTop - 0.6, 4, function(x, y, z)
        local r = sqrt(x * x + z * z)
        if abs(r - 2.6) < 0.3 then
            local a = math.atan(z, x)
            local s = (a / (2 * pi) * 10) % 1
            if s < 0.12 and y > yTop - 1.6 + (s * 6) then return P.CRYSTAL end
        end
    end)
    Keep(b:Finish({}))
end

-- ---------------------------------------------------------------- 时之碑底座（4 个，东南西北偏 45°）
M.STELE_POS = {}
local function BuildSteleBases(world)
    local R = 29.5
    for i = 0, 3 do
        local a = pi / 4 + i * pi / 2
        local cx, cz = cos(a) * R, sin(a) * R
        M.STELE_POS[i + 1] = Vector3(cx, Terrain.RING_Y, cz)
        local b = Brush.New(world, { min = { cx - 3, Terrain.RING_Y - 0.5, cz - 3 }, max = { cx + 3, Terrain.RING_Y + 1.25, cz + 3 }, size = 0.25 })
        b:Shape(cx - 3, Terrain.RING_Y - 0.5, cz - 3, cx + 3, Terrain.RING_Y + 1.25, cz + 3, function(x, y, z)
            local dx, dz = abs(x - cx), abs(z - cz)
            local ly = y - Terrain.RING_Y
            local e = (ly < 0.5) and 2.6 or ((ly < 1.0) and 2.0 or 1.5)
            if dx > e or dz > e then return nil end
            if ly > 1.0 then
                -- 顶面金色接口
                if dx < 0.9 and dz < 0.9 then return P.GOLD end
                if dx > e - 0.26 or dz > e - 0.26 then return P.RUNE_BLUE end
            end
            if ly > 0.5 and ly < 0.75 and (dx > e - 0.26 or dz > e - 0.26) then return P.GOLD_DARK end
            return MossyStone(x, y, z, Terrain.RING_Y)
        end)
        Keep(b:Finish({}))
        -- 底座到龙庭边的引导线：一串地面金色方砖（位于平台路面上，嵌入一格）
        local lb = Brush.New(world, { min = { min(cx, cos(a) * 21) - 1, Terrain.RING_Y - 0.25, min(cz, sin(a) * 21) - 1 },
            max = { max(cx, cos(a) * 21) + 1, Terrain.RING_Y + 0.01, max(cz, sin(a) * 21) + 1 }, size = 0.25 })
        local dx, dz = cos(a), sin(a)
        for t = 21.5, R - 2.8, 1.0 do
            local px, pz = dx * t, dz * t
            lb:Box(px - 0.25, Terrain.RING_Y - 0.25, pz - 0.25, px + 0.25, Terrain.RING_Y, pz + 0.25, P.FLOOR_RUNE_G)
        end
        Keep(lb:Finish({ keepEmpty = false }))
    end
end

-- ---------------------------------------------------------------- 内环台缘矮墙（台边、阶梯扶手）
local function BuildInnerParapet(world)
    -- 沿 r=20.9 一圈的矮栏（龙庭边缘，台面 y=6 落到 0 的崖壁顶），留出阶梯口
    for qd = 0, 3 do
        local x0, x1 = (qd % 2 == 0) and -22.5 or 0, (qd % 2 == 0) and 0 or 22.5
        local z0, z1 = (qd < 2) and -22.5 or 0, (qd < 2) and 0 or 22.5
        local b = Brush.New(world, { min = { x0, Terrain.RING_Y, z0 }, max = { x1, Terrain.RING_Y + 1.5, z1 }, size = 0.25 })
        b:Shape(x0, Terrain.RING_Y, z0, x1, Terrain.RING_Y + 1.5, z1, function(x, y, z)
            local r = sqrt(x * x + z * z)
            if r < 21.0 or r > 21.6 then return nil end
            if abs(x) < Terrain.STAIR_HALF + 0.6 then return nil end
            local a = math.atan(z, x)
            local seg = (a / (2 * pi) * 96) % 1
            local ly = y - Terrain.RING_Y
            local broken = Noise.Value2(a * 8, 1, 33) < 0.28
            if broken and ly > 0.5 then return nil end
            if ly < 0.25 then return Marble(x, y, z) end
            if ly < 1.0 then
                if seg < 0.3 then return Marble(x, y, z) end -- 栏杆柱
                return nil
            end
            if ly < 1.25 then return Marble(x, y, z) end
        end)
        Keep(b:Finish({}))
    end
    -- 阶梯两侧扶墙（龙庭 → 内环），南北各两条
    for _, sz in ipairs({ -1, 1 }) do
        for _, sx in ipairs({ -1, 1 }) do
            local x = sx * (Terrain.STAIR_HALF + 0.25)
            local zA, zB = sz * Terrain.COURT_R, sz * Terrain.STAIR_END
            local b = Brush.New(world, { min = { x - 0.5, -0.5, min(zA, zB) - 0.5 }, max = { x + 0.5, Terrain.RING_Y + 1.5, max(zA, zB) + 0.5 }, size = 0.25 })
            b:Shape(x - 0.5, -0.5, min(zA, zB) - 0.5, x + 0.5, Terrain.RING_Y + 1.5, max(zA, zB) + 0.5, function(px, py, pz)
                local d = abs(pz) - Terrain.COURT_R
                if d < -0.5 or abs(pz) > Terrain.STAIR_END then return nil end
                local stepY = min(Terrain.RING_Y, 0.5 * floor(max(0, d) / 1.0 + 1))
                if py < stepY + 1.0 then
                    if abs(px - x) > 0.4 then return nil end
                    if py > stepY + 0.75 then return P.GOLD_DARK end
                    return Marble(px, py, pz)
                end
            end)
            Keep(b:Finish({}))
        end
    end
end

-- ---------------------------------------------------------------- 外城墙 + 角楼 + 城门
M.WALL_R = Terrain.WALL_R
local function BuildOuterWall(world)
    local R = M.WALL_R
    local baseY = Terrain.RING_Y
    local H = 6.0
    local T = 1.6
    -- 8 段（每 45°）分体积
    for seg = 0, 7 do
        local a0, a1 = seg * pi / 4, (seg + 1) * pi / 4
        local xs = { cos(a0) * (R + 2), cos(a1) * (R + 2), cos(a0) * (R - 2), cos(a1) * (R - 2) }
        local zs = { sin(a0) * (R + 2), sin(a1) * (R + 2), sin(a0) * (R - 2), sin(a1) * (R - 2) }
        local x0, x1 = min(xs[1], xs[2], xs[3], xs[4]), max(xs[1], xs[2], xs[3], xs[4])
        local z0, z1 = min(zs[1], zs[2], zs[3], zs[4]), max(zs[1], zs[2], zs[3], zs[4])
        local b = Brush.New(world, { min = { x0, baseY - 1, z0 }, max = { x1, baseY + H + 1.5, z1 }, size = 0.5 })
        b:Shape(x0, baseY - 1, z0, x1, baseY + H + 1.5, z1, function(x, y, z)
            local r = sqrt(x * x + z * z)
            if abs(r - R) > T * 0.5 + 0.5 then return nil end
            local a = math.atan(z, x)
            if a < 0 then a = a + 2 * pi end
            if a < a0 or a >= a1 then return nil end
            -- 南门（-90°）/ 北门（90°）门洞 宽 5m 高 4.5m
            local gx = abs(x)
            local isGate = gx < 2.6 and abs(abs(z) - R) < 2
            local ly = y - baseY
            local ground = Terrain.HeightAt(x, z)
            if y < ground - 0.5 then return nil end
            -- 墙基外扩
            local half = (ly < 0.8) and (T * 0.5 + 0.5) or (T * 0.5)
            if abs(r - R) > half then return nil end
            -- 残缺：按角度噪声降低墙顶；东侧（0°附近）有一大段完全坍塌
            local top = H - 3.5 * max(0, Noise.Value2(a * 5, 3, 51) - 0.5) * 2
            local ruinE = abs(math.deg(a) - 15) < 12
            if ruinE then top = 0.8 + Noise.Value2(a * 30, 1, 52) * 1.2 end
            if isGate then
                if ly < 4.5 then return nil end
                -- 门拱：半圆
                local dy = ly - 4.5
                if gx * gx + dy * dy * 0 < 0 then return nil end
                top = H + 1.0
            end
            -- 垛口
            if ly > top then return nil end
            if ly > top - 0.8 and abs(r - R) > 0.3 and not isGate then
                local m = (a * R / 1.0) % 2
                if m > 1.0 and top >= H - 0.1 then return nil end
            end
            if isGate and ly > H + 0.2 then return P.GOLD end
            if ly > top - 0.5 and top >= H - 0.1 then return Stone(x, y, z) end
            return MossyStone(x, y, z, baseY)
        end)
        Keep(b:Finish({}))
    end
    -- 角楼：4 座（45° 方向），东北的倒塌
    for i = 0, 3 do
        local a = pi / 4 + i * pi / 2
        local cx, cz = cos(a) * R, sin(a) * R
        local collapsed = (i == 0)
        local h = collapsed and 7.0 or 14.0
        local b = Brush.New(world, { min = { cx - 4, baseY - 1, cz - 4 }, max = { cx + 4, baseY + h + 6, cz + 4 }, size = 0.5 })
        b:Shape(cx - 4, baseY - 1, cz - 4, cx + 4, baseY + h + 6, cz + 4, function(x, y, z)
            local dx, dz = x - cx, z - cz
            local d = sqrt(dx * dx + dz * dz)
            local ly = y - baseY
            local ground = Terrain.HeightAt(x, z)
            if y < ground - 0.5 then return nil end
            local rr = (ly < 1.0) and 3.6 or 3.2
            local topY = h
            if collapsed then topY = h - 4 * Noise.Value2(dx * 0.8, dz * 0.8, 61) end
            if ly < topY then
                if d > rr then return nil end
                -- 空心（2.2 内径），底层实心
                if d < 2.2 and ly > 1.0 then return nil end
                -- 窗洞
                local ang = math.atan(dz, dx)
                local w = (ang / (2 * pi) * 6) % 1
                if ly % 4.0 > 2.0 and ly % 4.0 < 3.3 and w > 0.42 and w < 0.58 and d > 2.4 then return nil end
                if abs(ly - h + 0.5) < 0.26 then return P.GOLD_DARK end
                return MossyStone(x, y, z, baseY)
            end
            if not collapsed then
                -- 尖顶：锥形蓝瓦
                local k = (ly - h) / 5.5
                if k > 1 then return nil end
                if d < 3.6 * (1 - k) then
                    if k > 0.92 then return P.GOLD end
                    if (ly * 2) % 1 < 0.5 and d > 3.6 * (1 - k) - 0.6 then return P.MARBLE_DARK end
                    return P.ROOF
                end
            end
        end)
        Keep(b:Finish({}))
    end
end

-- ---------------------------------------------------------------- 北殿遗址 + 巨像
local function BuildNorthHall(world)
    local cz = 60.0
    local baseY = Terrain.RING_Y
    -- 台基 20×10，三级台阶
    local b = Brush.New(world, { min = { -12, baseY - 1, cz - 7 }, max = { 12, baseY + 13, cz + 8 }, size = 0.5 })
    b:Shape(-12, baseY - 1, cz - 7, 12, baseY + 2, cz + 8, function(x, y, z)
        local ly = y - baseY
        local dz = z - cz
        if ly < 0.5 and abs(x) < 11 and dz > -6.5 and dz < 7.5 then return Stone(x, y, z) end
        if ly < 1.0 and abs(x) < 10.5 and dz > -6.0 and dz < 7.5 then return Marble(x, y, z) end
        if ly < 1.5 and abs(x) < 10 and dz > -5.5 and dz < 7.5 then return Marble(x, y, z) end
    end)
    -- 后墙（残缺，带壁龛）
    b:Shape(-10, baseY + 1.5, cz + 5.5, 10, baseY + 13, cz + 7.5, function(x, y, z)
        local ly = y - baseY
        local top = 8 + 4 * Noise.Value2(x * 0.3, 1, 71)
        if abs(x) > 7 then top = top - 3 * Noise.Value2(x, 2, 72) end
        if ly > top then return nil end
        -- 壁龛（中央，为巨像留位置）
        if abs(x) < 3.2 and ly < 10 and z < cz + 6.5 then return nil end
        if abs(ly - 7.5) < 0.26 then return P.GOLD_DARK end
        return MossyStone(x, y, z, baseY)
    end)
    Keep(b:Finish({}))
    -- 前排断柱 6 根
    local cb = Brush.New(world, { min = { -12, baseY + 1, cz - 6 }, max = { 12, baseY + 12, cz - 1 }, size = 0.25 })
    local hs = { 9.0, 3.2, 9.0, 5.1, 9.0, 2.4 }
    for i = 1, 6 do
        local x = -8.75 + (i - 1) * 3.5
        Column(cb, x, cz - 3.5, baseY + 1.5, 8.0, 0.6, (hs[i] < 8.5) and hs[i] or nil, true)
    end
    Keep(cb:Finish({}))
    -- 巨像：抱着沙漏的守护者（简化造型：袍身 + 头 + 双臂托沙漏）
    local sb = Brush.New(world, { min = { -3.5, baseY + 1.5, cz + 3 }, max = { 3.5, baseY + 13, cz + 7 }, size = 0.25 })
    local sx, szz = 0, cz + 5.2
    sb:Shape(-3.5, baseY + 1.5, cz + 3, 3.5, baseY + 13, cz + 7, function(x, y, z)
        local ly = y - baseY - 1.5
        local dx, dz = x - sx, z - szz
        -- 底座
        if ly < 1.0 then
            if abs(dx) < 2.2 and abs(dz) < 1.6 then return (ly > 0.75) and P.GOLD_DARK or Stone(x, y, z) end
            return nil
        end
        -- 袍身：自下而上收窄的椭圆柱
        if ly < 7.0 then
            local k = (ly - 1) / 6
            local rx, rz = 1.8 - 0.7 * k, 1.1 - 0.35 * k
            if (dx / rx) ^ 2 + (dz / rz) ^ 2 <= 1 then
                -- 衣褶：竖条
                if (x * 2.5) % 1 < 0.2 and ly < 5 then return P.STONE_C end
                if abs(ly - 4.2) < 0.13 then return P.GOLD end
                if Noise.Value3(x, y, z, 9) > 0.7 then return P.STONE_MOSS end
                return Marble(x, y, z)
            end
            -- 双臂：从肩（ly 6.2）向前下伸，托住胸前沙漏
            if ly > 4.2 and ly < 6.5 then
                for _, sgn in ipairs({ -1, 1 }) do
                    local ax = sx + sgn * (1.25 - (6.4 - ly) * 0.35)
                    local az = szz - 0.6 - (6.4 - ly) * 0.45
                    if (x - ax) ^ 2 + (z - az) ^ 2 < 0.33 ^ 2 then return Marble(x, y, z) end
                end
            end
            return nil
        end
        -- 头 + 兜帽
        local hy = ly - 7.9
        if hy * hy / 1.0 + dx * dx / 0.6 + dz * dz / 0.55 <= 1 then
            if dz < -0.55 and abs(hy + 0.1) < 0.13 and abs(dx) < 0.5 then return P.RUNE_BLUE end -- 眼缝
            return Marble(x, y, z)
        end
        -- 头顶光环残片
        local rr = sqrt(dx * dx + (hy - 0.4) ^ 2)
        if abs(dz - 0.4) < 0.15 and abs(rr - 1.5) < 0.15 and x < 0.8 then return P.GOLD end
    end)
    -- 沙漏（胸前）：金框 + 蓝色时晶沙
    sb:Shape(-1, baseY + 4.5, cz + 3, 1, baseY + 7.5, cz + 4.6, function(x, y, z)
        local ly = y - baseY - 1.5
        local dx, dz = x - sx, z - (szz - 1.45)
        if ly < 3.3 or ly > 5.4 then return nil end
        local m = ly - 4.35
        if abs(m) > 0.95 then
            if abs(dx) < 0.62 and abs(dz) < 0.45 then return P.GOLD end
            return nil
        end
        local w = 0.12 + 0.42 * abs(m) / 0.95
        if abs(dx) < w and abs(dz) < w * 0.8 then return P.CRYSTAL end
        if abs(abs(dx) - 0.55) < 0.12 and abs(dz) < 0.12 then return P.GOLD end
    end)
    Keep(sb:Finish({}))
end

-- ---------------------------------------------------------------- 渡槽（东侧，跨峡谷到外环，断一截）
local function BuildAqueduct(world)
    -- 沿 +X 方向，z = 10，从 x=36 到 x=58；桥墩落在谷底
    local z0 = 10
    local b = Brush.New(world, { min = { 34, Terrain.RAVINE_Y - 1, z0 - 1.6 }, max = { 60, Terrain.RING_Y + 6, z0 + 1.6 }, size = 0.5 })
    local deck = Terrain.RING_Y + 3.5
    b:Shape(34, Terrain.RAVINE_Y - 1, z0 - 1.6, 60, deck + 2, z0 + 1.6, function(x, y, z)
        local dz = abs(z - z0)
        if dz > 1.5 then return nil end
        local ground = Terrain.HeightAt(x, z)
        -- 断口：x 在 43.5..46 之间没有桥面
        local gap = x > 43.5 and x < 46.5
        -- 桥面槽（U 形）
        if y > deck and y < deck + 1.5 and not gap then
            if dz > 1.0 then return (y > deck + 1.25) and P.GOLD_DARK or Stone(x, y, z) end
            if y < deck + 0.5 then return P.MARBLE_BLUE end
            return nil
        end
        if y > deck - 1.0 and y <= deck and not gap then
            -- 拱：每 5m 一个半圆拱
            return Stone(x, y, z)
        end
        if y <= deck - 1.0 and y > ground - 0.5 then
            -- 每 5m 一跨：墩宽 1m（|dxa| ≥ 2），墩间是半圆拱（半径 2，圆心在桥面下 3m）
            local dxa = (x - 34) % 5.0 - 2.5
            if gap and y > deck - 6 then return nil end
            if abs(dxa) >= 2.0 then return MossyStone(x, y, z, ground) end
            local cy = deck - 3.0
            if y > cy + sqrt(max(0, 4.0 - dxa * dxa)) then return Stone(x, y, z) end
            return nil
        end
    end)
    Keep(b:Finish({}))
end

-- ---------------------------------------------------------------- 植被
local function Tree(world, x, z, o)
    local gy = Terrain.HeightAt(x, z)
    local h = o.h or 7
    local cr = o.r or 3.2
    local leaves = o.gold and Pal.GOLD_LEAVES or Pal.LEAVES
    local b = Brush.New(world, { min = { x - cr - 1, gy - 0.5, z - cr - 1 }, max = { x + cr + 1, gy + h + cr, z + cr + 1 }, size = 0.25 })
    local lean = o.lean or 0
    local la = o.leanA or 0
    local lx, lz = cos(la) * lean, sin(la) * lean
    -- 树干
    b:Shape(x - 1.5, gy - 0.5, z - 1.5, x + 1.5, gy + h, z + 1.5, function(px, py, pz)
        local t = (py - gy) / h
        local cx, cz = x + lx * t * t, z + lz * t * t
        local rr = (o.trunk or 0.45) * (1.0 - 0.45 * t) + ((t < 0.08) and 0.35 or 0)
        local dx, dz = px - cx, pz - cz
        if dx * dx + dz * dz <= rr * rr then return P.BARK end
    end)
    -- 枝杈 + 树冠团（3–5 团）
    local rng = Noise.Rng(floor(x * 31 + z * 17))
    local tx, tz = x + lx, z + lz
    local blobs = { { tx, gy + h, tz, cr } }
    for i = 1, rng:Int(2, 4) do
        local a = rng:Range(0, 2 * pi)
        local d = rng:Range(cr * 0.5, cr * 0.9)
        blobs[#blobs + 1] = { tx + cos(a) * d, gy + h - rng:Range(0.4, 1.8), tz + sin(a) * d, cr * rng:Range(0.55, 0.8) }
    end
    for _, bl in ipairs(blobs) do
        b:Shape(bl[1] - bl[4], bl[2] - bl[4] * 0.8, bl[3] - bl[4], bl[1] + bl[4], bl[2] + bl[4] * 0.8, bl[3] + bl[4], function(px, py, pz)
            local dx, dy, dz = (px - bl[1]) / bl[4], (py - bl[2]) / (bl[4] * 0.72), (pz - bl[3]) / bl[4]
            local d = dx * dx + dy * dy + dz * dz
            local n = Noise.Value3(px * 1.3, py * 1.3, pz * 1.3, 13)
            if d < 0.65 + 0.5 * n then
                local h2 = Hash3(floor(px * 4), floor(py * 4), floor(pz * 4))
                -- 上半更亮
                if dy > 0.3 and h2 < 0.5 then return leaves[2] end
                if dy < -0.3 then return leaves[3] end
                return leaves[(h2 < 0.6) and 1 or 2]
            end
        end)
        -- 枝
        b:Shape(min(tx, bl[1]) - 0.3, min(gy + h - 2, bl[2]) - 0.3, min(tz, bl[3]) - 0.3, max(tx, bl[1]) + 0.3, max(gy + h, bl[2]) + 0.3, max(tz, bl[3]) + 0.3, function(px, py, pz)
            local ax, ay, az = tx, gy + h - 1.8, tz
            local bx, by, bz = bl[1], bl[2], bl[3]
            local abx, aby, abz = bx - ax, by - ay, bz - az
            local l2 = abx * abx + aby * aby + abz * abz
            if l2 < 0.01 then return nil end
            local t = ((px - ax) * abx + (py - ay) * aby + (pz - az) * abz) / l2
            if t < 0 or t > 1 then return nil end
            local qx, qy, qz = ax + abx * t - px, ay + aby * t - py, az + abz * t - pz
            if qx * qx + qy * qy + qz * qz < 0.22 * 0.22 then return P.BARK end
        end)
    end
    -- 金叶古树：落叶铺地（在地表上画一层薄叶）
    if o.gold then
        b:Shape(x - cr - 1, gy - 0.25, z - cr - 1, x + cr + 1, gy + 0.25, z + cr + 1, function(px, py, pz)
            local dx, dz = px - tx, pz - tz
            if dx * dx + dz * dz > (cr + 0.8) ^ 2 then return nil end
            local g = Terrain.HeightAt(px, pz)
            if abs(g - gy) > 0.3 then return nil end
            if py > g and py < g + 0.25 and Hash3(floor(px * 4), 1, floor(pz * 4)) < 0.3 then return Pal.GOLD_LEAVES[1] end
        end)
    end
    return Keep(b:Finish({}))
end

local function Bush(b, x, y, z, r, rng)
    b:Shape(x - r, y, z - r, x + r, y + r * 1.2, z + r, function(px, py, pz)
        local dx, dy, dz = (px - x) / r, (py - y) / (r * 0.9), (pz - z) / r
        local n = Noise.Value3(px * 2, py * 2, pz * 2, 19)
        if dx * dx + dy * dy + dz * dz < 0.6 + 0.5 * n then
            local h = Hash3(floor(px * 4), floor(py * 4), floor(pz * 4))
            if h > 0.97 then return P.FLOWER_W elseif h > 0.95 then return P.FLOWER_B end
            return Pal.LEAVES[(h < 0.5) and 1 or ((h < 0.8) and 2 or 3)]
        end
    end)
end

local function Crystal(b, x, y, z, h, r, tilt, a)
    local dx, dz = cos(a) * tilt, sin(a) * tilt
    b:Shape(x - r - abs(dx) * h, y - 0.3, z - r - abs(dz) * h, x + r + abs(dx) * h, y + h, z + r + abs(dz) * h, function(px, py, pz)
        local t = (py - y) / h
        if t < -0.1 or t > 1 then return nil end
        local cx, cz = x + dx * h * t, z + dz * h * t
        local rr = r * ((t > 0.7) and (1 - (t - 0.7) / 0.3) or 1)
        local ax, az = abs(px - cx), abs(pz - cz)
        -- 六边形近似：|x| + 0.5|z| 截面
        if max(ax * 0.87 + az * 0.5, az) <= rr then
            return (t > 0.6 or Hash3(floor(px * 4), floor(py * 4), floor(pz * 4)) < 0.3) and P.CRYSTAL or P.CRYSTAL_B
        end
    end)
end
M.Crystal = Crystal

local function BuildVegetation(world)
    local rng = Noise.Rng(2026)
    -- 金叶古树：龙庭东南、西北各一棵，内环上（作为构图焦点）
    Tree(world, 30.5, -14, { h = 9, r = 4.5, trunk = 0.7, gold = true, lean = 1.2, leanA = pi })
    Tree(world, -31, 15, { h = 10, r = 5.0, trunk = 0.75, gold = true, lean = 1.4, leanA = 0.3 })
    -- 外环普通树：沿外环随机，避开道路和城墙
    local placed = 0
    for i = 1, 60 do
        local a = rng:Range(0, 2 * pi)
        local r = rng:Range(54, 66)
        local x, z = cos(a) * r, sin(a) * r
        local gy = Terrain.HeightAt(x, z)
        if abs(x) > 6 and gy < Terrain.RING_Y + 1.5 and not (z > 50 and abs(x) < 14) then
            Tree(world, x, z, { h = rng:Range(5, 8), r = rng:Range(2.4, 3.6), lean = rng:Range(0, 0.8), leanA = rng:Range(0, 6.28), gold = rng:Next() < 0.12 })
            placed = placed + 1
            if placed >= 22 then break end
        end
    end
    -- 内环少量树（柱廊外侧）
    for i = 1, 6 do
        local a = rng:Range(0, 2 * pi)
        local r = rng:Range(33.5, 37)
        local x, z = cos(a) * r, sin(a) * r
        if abs(x) > 6 then Tree(world, x, z, { h = rng:Range(4.5, 6), r = rng:Range(2.0, 2.8), lean = 0.5, leanA = a }) end
    end
    -- 灌木 + 时晶：按象限合到几个体积里
    for qd = 0, 3 do
        local x0, x1 = (qd % 2 == 0) and -70 or 0, (qd % 2 == 0) and 0 or 70
        local z0, z1 = (qd < 2) and -70 or 0, (qd < 2) and 0 or 70
        local b = Brush.New(world, { min = { x0, Terrain.RAVINE_Y - 1, z0 }, max = { x1, Terrain.RING_Y + 6, z1 }, size = 0.25 })
        for i = 1, 40 do
            local x, z = rng:Range(x0, x1), rng:Range(z0, z1)
            local r = sqrt(x * x + z * z)
            local gy = Terrain.HeightAt(x, z)
            local ok = r > 27 and r < 68 and abs(x) > 4.5 and gy <= Terrain.RING_Y + 0.6 and gy >= Terrain.RING_Y - 0.1
                and abs(r - M.WALL_R) > 2.5 and (r < Terrain.RAVINE_IN - 1 or r > Terrain.RAVINE_OUT + 1)
            if ok then Bush(b, x, gy, z, rng:Range(0.6, 1.2), rng) end
        end
        -- 峡谷里的时晶簇（发光，给峡谷底提供蓝色光源感）
        for i = 1, 14 do
            local a = rng:Range(qd * pi / 2, (qd + 1) * pi / 2) + pi -- 象限对应
            local rr = rng:Range(Terrain.RAVINE_IN + 2, Terrain.RAVINE_OUT - 2)
            local x, z = cos(a) * rr, sin(a) * rr
            if x >= x0 and x < x1 and z >= z0 and z < z1 and abs(x) > 5 then
                local gy = Terrain.HeightAt(x, z)
                for k = 1, rng:Int(2, 4) do
                    Crystal(b, x + rng:Range(-0.8, 0.8), gy, z + rng:Range(-0.8, 0.8), rng:Range(1.2, 3.2), rng:Range(0.25, 0.45),
                        rng:Range(0, 0.35), rng:Range(0, 2 * pi))
                end
            end
        end
        Keep(b:Finish({}))
    end
end

-- ---------------------------------------------------------------- 悬浮碎岩（纯视觉，缓慢漂浮旋转）
M.floaters = {}
local function BuildFloaters(world)
    local rng = Noise.Rng(404)
    local defs = {}
    -- 龙庭上空环绕的碎石（大小不一）
    for i = 1, 14 do
        local a = rng:Range(0, 2 * pi)
        local r = rng:Range(12, 30)
        defs[#defs + 1] = { x = cos(a) * r, y = rng:Range(16, 28), z = sin(a) * r, s = rng:Range(0.6, 2.2) }
    end
    -- 峡谷上空几块大的（带草皮的浮岛）
    for i = 1, 5 do
        local a = rng:Range(0, 2 * pi)
        local r = rng:Range(42, 48)
        if abs(cos(a) * r) > 8 then
            defs[#defs + 1] = { x = cos(a) * r, y = rng:Range(10, 18), z = sin(a) * r, s = rng:Range(2.5, 4.0), island = true }
        end
    end
    -- 半截塔尖（时停中的崩塌），北侧上空
    defs[#defs + 1] = { x = -14, y = 24, z = 30, s = 3.0, spire = true }
    for i, d in ipairs(defs) do
        local s = d.s
        local b = Brush.New(world, { origin = Vector3(d.x, d.y, d.z), min = { -s * 1.4, -s * 1.6, -s * 1.4 }, max = { s * 1.4, s * (d.spire and 3.5 or 1.2), s * 1.4 }, size = (s > 2) and 0.25 or 0.25 })
        local seed = i * 13
        if d.spire then
            b:Shape(-s * 1.4, -s * 1.6, -s * 1.4, s * 1.4, s * 3.5, s * 1.4, function(x, y, z)
                local k = (y + s * 1.6) / (s * 5.1)
                local rr = s * (1 - k) * 0.9
                if max(abs(x), abs(z)) > rr then return nil end
                -- 底部断口
                if y < -s * 1.6 + s * 0.8 * Noise.Value2(x * 2, z * 2, seed) then return nil end
                if (y * 2) % 1 < 0.5 and max(abs(x), abs(z)) > rr - 0.5 then return P.MARBLE_DARK end
                if k > 0.95 then return P.GOLD end
                return P.ROOF
            end)
        else
            b:Shape(-s * 1.4, -s * 1.6, -s * 1.4, s * 1.4, s * 1.2, s * 1.4, function(x, y, z)
                -- 倒锥形岩块：上平下尖
                local top = s * 0.6 + s * 0.3 * Noise.Value2(x * 0.7, z * 0.7, seed)
                if y > top then return nil end
                local k = (top - y) / (s * 2.0)
                local rr = s * (1.2 - k * 0.9) * (0.8 + 0.4 * Noise.Value3(x * 0.8, y * 0.8, z * 0.8, seed))
                if sqrt(x * x + z * z) > rr then return nil end
                if d.island and y > top - 0.3 then return Pal.Pick({ P.GRASS_A, P.GRASS_B, P.GRASS_C }, Hash3(floor(x * 4), 3, floor(z * 4))) end
                if d.island and y > top - 0.8 then return P.DIRT end
                if Hash3(floor(x * 4), floor(y * 4), floor(z * 4)) < 0.05 then return P.CRYSTAL end
                return Terrain.StrataAt(y + d.y, x, z)
            end)
            -- 浮岛上加一棵小树 / 时晶
            if d.island then
                Crystal(b, 0.3, s * 0.6, -0.2, 1.6, 0.3, 0.2, 1.0)
            end
        end
        local v = b:Finish({ visual = true })
        if v ~= nil then
            M.floaters[#M.floaters + 1] = { vol = v, node = v:GetNode(), base = v:GetNode().position, phase = rng:Range(0, 6.28),
                amp = rng:Range(0.25, 0.6), spin = rng:Range(-4, 4) }
        end
    end
end

function M.UpdateFloaters(t, freezeK)
    -- freezeK：时停（诺米冻结法术命中龙庭时整体减速）；1 = 正常
    for _, f in ipairs(M.floaters) do
        local ph = f.phase + t * 0.35 * (freezeK or 1)
        f.node.position = f.base + Vector3(0, sin(ph) * f.amp, 0)
        f.node.rotation = Quaternion(f.spin * t * (freezeK or 1), Vector3.UP)
    end
end

-- ---------------------------------------------------------------- 入口
---@param world VoxelPhysicsWorld
function M.Build(world)
    local t0 = os.clock()
    local steps = {
        { "court", BuildCourtFloor }, { "altar", BuildAltar }, { "colonnade", BuildColonnade },
        { "fallen", BuildFallenColumns }, { "dome", BuildDomeRibs }, { "steles", BuildSteleBases },
        { "parapet", BuildInnerParapet }, { "wall", BuildOuterWall }, { "hall", BuildNorthHall },
        { "aqueduct", BuildAqueduct }, { "vegetation", BuildVegetation }, { "floaters", BuildFloaters },
    }
    for _, s in ipairs(steps) do
        local t1 = os.clock()
        local ok, err = pcall(s[2], world)
        if not ok then print("RuinsBuild: " .. s[1] .. " FAILED: " .. tostring(err)) end
        print(string.format("RuinsBuild: %s %.2fs (volumes %d)", s[1], os.clock() - t1, #M.volumes))
    end
    print(string.format("RuinsBuild: total %.2fs, %d volumes", os.clock() - t0, #M.volumes))
end

return M
