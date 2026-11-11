-- ====================================================================
-- RuinsPalette.lua — 时之遗迹的调色板槽位与配色
--
-- 槽位 100–159（龙占 40–57、龙息 65–77，互不冲突）。硬度语义见 voxel-physics.md：
-- 法术伤害 power < hardness 的体素完全免疫。地形 / 主体建筑另设 destructible = false。
-- 法阵、符文类槽位带自发光；苏醒时运行时改 PBR 让它们亮起来。
-- ====================================================================

local M = {}

local P = {
    -- 古石（暖灰米色，三档 + 苔）
    STONE_A = 100, STONE_B = 101, STONE_C = 102, STONE_D = 103, STONE_MOSS = 104,
    -- 白玛瑙 / 蓝调石（神殿主体）
    MARBLE_A = 105, MARBLE_B = 106, MARBLE_BLUE = 107, MARBLE_DARK = 108,
    -- 金饰
    GOLD = 109, GOLD_DARK = 110,
    -- 法阵 / 符文
    RUNE_BLUE = 111, RUNE_GOLD = 112, FLOOR_RUNE_B = 113, FLOOR_RUNE_G = 114,
    -- 地面
    GRASS_A = 115, GRASS_B = 116, GRASS_C = 117, GRASS_D = 118, DIRT = 119, DIRT_B = 120,
    CLIFF_A = 121, CLIFF_B = 122, CLIFF_C = 123, CLIFF_D = 124, SAND = 125, PATH = 126, PATH_B = 127,
    -- 植被
    BARK = 128, LEAF_A = 129, LEAF_B = 130, LEAF_C = 131, LEAF_GOLD = 132, LEAF_GOLD_B = 133,
    FLOWER_W = 134, FLOWER_B = 135, FLOWER_Y = 136,
    -- 晶体
    CRYSTAL = 137, CRYSTAL_B = 138,
    -- 地砖
    TILE_A = 139, TILE_B = 140, TILE_C = 141,
    -- 可破坏碎石（封门乱石、掩埋堆）
    RUBBLE_A = 142, RUBBLE_B = 143, RUBBLE_C = 144,
    -- 屋顶 / 木
    ROOF = 145, WOOD = 146,
    -- 深色岩（峡谷底）
    DEEP_A = 147, DEEP_B = 148,
    -- 雪顶（远处山顶）
    SNOW = 149,
}
M.P = P

-- { 槽位, 颜色, 硬度, 粗糙度, 金属度, 自发光(rgba, a=强度) }
local DEF = {
    { P.STONE_A, { 0.78, 0.74, 0.66 }, 4.0, 0.9 },
    { P.STONE_B, { 0.70, 0.66, 0.58 }, 4.0, 0.9 },
    { P.STONE_C, { 0.60, 0.57, 0.51 }, 4.0, 0.92 },
    { P.STONE_D, { 0.50, 0.48, 0.44 }, 4.0, 0.95 },
    { P.STONE_MOSS, { 0.42, 0.55, 0.32 }, 4.0, 0.95 },
    { P.MARBLE_A, { 0.93, 0.92, 0.88 }, 6.0, 0.55 },
    { P.MARBLE_B, { 0.85, 0.85, 0.82 }, 6.0, 0.6 },
    { P.MARBLE_BLUE, { 0.55, 0.66, 0.84 }, 6.0, 0.5 },
    { P.MARBLE_DARK, { 0.30, 0.36, 0.50 }, 6.0, 0.6 },
    { P.GOLD, { 0.95, 0.74, 0.32 }, 8.0, 0.35, 1.0 },
    { P.GOLD_DARK, { 0.70, 0.50, 0.20 }, 8.0, 0.45, 1.0 },
    { P.RUNE_BLUE, { 0.35, 0.55, 1.0 }, 8.0, 0.3, 0.0, { 0.25, 0.45, 1.0, 1.2 } },
    { P.RUNE_GOLD, { 1.0, 0.80, 0.38 }, 8.0, 0.3, 0.0, { 1.0, 0.72, 0.28, 1.0 } },
    { P.FLOOR_RUNE_B, { 0.32, 0.42, 0.62 }, 50.0, 0.4, 0.0, { 0.25, 0.45, 1.0, 0.15 } },
    { P.FLOOR_RUNE_G, { 0.66, 0.56, 0.34 }, 50.0, 0.4, 0.4, { 1.0, 0.72, 0.28, 0.08 } },
    { P.GRASS_A, { 0.42, 0.62, 0.30 }, 50.0, 0.95 },
    { P.GRASS_B, { 0.50, 0.68, 0.33 }, 50.0, 0.95 },
    { P.GRASS_C, { 0.36, 0.55, 0.28 }, 50.0, 0.95 },
    { P.GRASS_D, { 0.60, 0.70, 0.36 }, 50.0, 0.95 },
    { P.DIRT, { 0.52, 0.42, 0.32 }, 50.0, 0.95 },
    { P.DIRT_B, { 0.45, 0.36, 0.28 }, 50.0, 0.95 },
    { P.CLIFF_A, { 0.62, 0.60, 0.58 }, 50.0, 0.92 },
    { P.CLIFF_B, { 0.54, 0.52, 0.50 }, 50.0, 0.92 },
    { P.CLIFF_C, { 0.46, 0.45, 0.45 }, 50.0, 0.95 },
    { P.CLIFF_D, { 0.68, 0.64, 0.58 }, 50.0, 0.92 },
    { P.SAND, { 0.80, 0.74, 0.60 }, 50.0, 0.95 },
    { P.PATH, { 0.68, 0.64, 0.57 }, 50.0, 0.9 },
    { P.PATH_B, { 0.60, 0.56, 0.50 }, 50.0, 0.9 },
    { P.BARK, { 0.40, 0.30, 0.22 }, 2.0, 0.95 },
    { P.LEAF_A, { 0.30, 0.52, 0.26 }, 1.0, 0.9 },
    { P.LEAF_B, { 0.38, 0.60, 0.30 }, 1.0, 0.9 },
    { P.LEAF_C, { 0.24, 0.44, 0.24 }, 1.0, 0.9 },
    { P.LEAF_GOLD, { 0.96, 0.72, 0.30 }, 1.0, 0.85 },
    { P.LEAF_GOLD_B, { 0.88, 0.56, 0.22 }, 1.0, 0.85 },
    { P.FLOWER_W, { 0.96, 0.95, 0.90 }, 1.0, 0.9 },
    { P.FLOWER_B, { 0.45, 0.62, 1.0 }, 1.0, 0.9 },
    { P.FLOWER_Y, { 1.0, 0.85, 0.40 }, 1.0, 0.9 },
    { P.CRYSTAL, { 0.45, 0.65, 1.0 }, 6.0, 0.15, 0.0, { 0.3, 0.55, 1.0, 1.6 } },
    { P.CRYSTAL_B, { 0.62, 0.55, 1.0 }, 6.0, 0.15, 0.0, { 0.45, 0.4, 1.0, 1.2 } },
    { P.TILE_A, { 0.82, 0.80, 0.74 }, 50.0, 0.7 },
    { P.TILE_B, { 0.74, 0.72, 0.67 }, 50.0, 0.75 },
    { P.TILE_C, { 0.62, 0.62, 0.62 }, 50.0, 0.8 },
    { P.RUBBLE_A, { 0.64, 0.60, 0.53 }, 1.0, 0.95 },
    { P.RUBBLE_B, { 0.55, 0.51, 0.45 }, 1.0, 0.95 },
    { P.RUBBLE_C, { 0.47, 0.44, 0.39 }, 1.0, 0.95 },
    { P.ROOF, { 0.38, 0.45, 0.62 }, 2.0, 0.8 },
    { P.WOOD, { 0.48, 0.36, 0.25 }, 1.5, 0.9 },
    { P.DEEP_A, { 0.32, 0.33, 0.38 }, 50.0, 0.95 },
    { P.DEEP_B, { 0.26, 0.27, 0.33 }, 50.0, 0.95 },
    { P.SNOW, { 0.95, 0.96, 0.98 }, 50.0, 0.8 },
}

local function Emi(e, k)
    if e == nil then return Color(0, 0, 0, 0) end
    return Color(e[1], e[2], e[3], e[4] * (k or 1))
end

---@param world VoxelPhysicsWorld
function M.Setup(world)
    for _, d in ipairs(DEF) do
        local c = d[2]
        world:SetPaletteEntry(d[1], Color(c[1], c[2], c[3]), d[3])
        world:SetPaletteEntryPBR(d[1], d[4] or 0.9, d[5] or 0.0, 0.5, Emi(d[6]))
    end
    -- 断面色：古石内芯偏暖偏深
    world:SetPaletteCutColor(P.MARBLE_A, Color(0.70, 0.66, 0.58))
    world:SetPaletteCutColor(P.MARBLE_B, Color(0.66, 0.62, 0.55))
    print("RuinsPalette: " .. #DEF .. " entries")
end

-- 地面法阵亮度：k = 0 沉睡（几乎不亮），1 完全点亮
---@param world VoxelPhysicsWorld
function M.SetFloorRune(world, k, pulse)
    local p = pulse or 0
    world:SetPaletteEntryPBR(P.FLOOR_RUNE_B, 0.4, 0.0, 0.5, Color(0.25, 0.45, 1.0, 0.15 + 2.4 * k + 0.4 * p * k))
    world:SetPaletteEntryPBR(P.FLOOR_RUNE_G, 0.4, 0.4, 0.5, Color(1.0, 0.72, 0.28, 0.08 + 1.6 * k + 0.3 * p * k))
end

-- 随机选色工具：pick(list, h) h ∈ [0,1)
function M.Pick(list, h)
    return list[math.min(#list, math.floor(h * #list) + 1)]
end

M.STONES = { P.STONE_A, P.STONE_B, P.STONE_C }
M.MARBLES = { P.MARBLE_A, P.MARBLE_A, P.MARBLE_B }
M.RUBBLES = { P.RUBBLE_A, P.RUBBLE_B, P.RUBBLE_C }
M.LEAVES = { P.LEAF_A, P.LEAF_B, P.LEAF_C }
M.GOLD_LEAVES = { P.LEAF_GOLD, P.LEAF_GOLD_B, P.LEAF_GOLD }

return M
