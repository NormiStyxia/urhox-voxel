-- ====================================================================
-- config.lua — VoxelTown 全局常量:调色板槽位、硬度、手感参数
-- 槽位纪律:1-19 归本脚手架手建体积;.vox 导入自动认领空槽,所以这里的
-- SetPaletteEntry 必须在任何 CreateVolumeFromModel 之前执行完毕。
-- ====================================================================

local M = {}

-- 手建体积的调色板槽(硬度语义:伤害 power < hardness 完全免疫)
M.MAT_ASPHALT = 1      -- 街道:炸药(power 8)能炸坑,散弹枪(3)啃不动
M.MAT_GRASS = 2
M.MAT_DIRT = 3         -- 土堆:什么都挖得动
M.MAT_PAINT = 4        -- 喷漆颜色
M.MAT_BOMB = 5         -- 炸弹身(近黑)
M.MAT_FUSE = 11        -- 引信火花(亮橙)
M.MAT_DOZER = 6
M.MAT_BLADE = 7        -- 铲刀/履带:近乎免疫
M.MAT_EXCAVATOR = 8
M.MAT_TRACK = 9
M.MAT_CAB = 10
M.MAT_WOOD = 13        -- 栈桥/船体木料
M.MAT_AIRFRAME = 14    -- 飞机蒙皮(亮白灰)
M.MAT_AIRACCENT = 15   -- 飞机涂装线(红)
M.MAT_CANOPY = 16      -- 座舱盖/舷窗(碎成玻璃粉,debrisStyle 1)
M.MAT_ASSEMBLY_BODY = 17   -- Assembly 承力车身(蓝,散弹枪可破坏)
M.MAT_ASSEMBLY_PANEL = 18  -- Assembly 解体车可脱落覆盖件(橙)
M.MAT_CRASH_WALL = 19      -- 防撞墙(不可破坏混凝土)
M.WATER_LEVEL = -0.15  -- 全局水面高度(海湾在东三分之一,x > 30)

-- 街道水坑:世界坐标噪声分布,通过 Zone 的 GBuffer 后处理修改表面。
M.PUDDLES_ENABLED = true  -- P 键开关,切换昼夜时保留
M.PUDDLE_COVERAGE = 0.48  -- 0-1,值越大水坑分布越广,0 为完全干燥
M.PUDDLE_SIZE = 3.5       -- 米,控制水坑的疏密与尺寸
M.PUDDLE_ROUGHNESS = 0.045  -- 0.02-0.4,值越低反射越清晰

function M.ApplyPalette(world)
    world:SetPaletteEntry(M.MAT_ASPHALT, Color(0.32, 0.33, 0.35), 6.0)
    world:SetPaletteEntry(M.MAT_GRASS, Color(0.36, 0.52, 0.28), 2.0)
    world:SetPaletteEntry(M.MAT_DIRT, Color(0.44, 0.31, 0.19), 0.4)
    world:SetPaletteEntry(M.MAT_PAINT, Color(0.95, 0.30, 0.65), 1.0)
    world:SetPaletteEntry(M.MAT_BOMB, Color(0.10, 0.10, 0.12), 50.0)
    world:SetPaletteEntry(M.MAT_FUSE, Color(1.0, 0.55, 0.10), 50.0)
    world:SetPaletteEntry(M.MAT_DOZER, Color(0.85, 0.65, 0.15), 50.0)
    world:SetPaletteEntry(M.MAT_BLADE, Color(0.45, 0.47, 0.52), 100.0)
    world:SetPaletteEntry(M.MAT_EXCAVATOR, Color(0.93, 0.72, 0.15), 50.0)
    world:SetPaletteEntry(M.MAT_TRACK, Color(0.36, 0.34, 0.30), 60.0)
    world:SetPaletteEntry(M.MAT_CAB, Color(0.16, 0.15, 0.14), 50.0)
    world:SetPaletteEntry(M.MAT_WOOD, Color(0.48, 0.35, 0.22), 1.2)
    world:SetPaletteEntry(M.MAT_AIRFRAME, Color(0.86, 0.88, 0.90), 3.0)
    world:SetPaletteEntry(M.MAT_AIRACCENT, Color(0.78, 0.12, 0.10), 3.0)
    world:SetPaletteEntry(M.MAT_CANOPY, Color(0.10, 0.14, 0.18), 2.0, 1)
    world:SetPaletteEntry(M.MAT_ASSEMBLY_BODY, Color(0.08, 0.32, 0.62), 3.0)
    world:SetPaletteEntry(M.MAT_ASSEMBLY_PANEL, Color(0.95, 0.42, 0.08), 3.0)
    world:SetPaletteEntry(M.MAT_CRASH_WALL, Color(0.48, 0.50, 0.54), 100.0)
end

-- 破坏世界参数
function M.ApplyWorldSettings(world)
    world:SetMinFragmentVoxels(6)
    world:SetMaxFrozenFragments(400)
    world:SetSpallChunkVoxels(4)
    world:SetMaxSpallChunks(24)
    world:SetSpallSpeed(2.5)
    world:SetDamageNoise(0.35)
    world:SetStressBreakFactor(200)
    world:SetMinDamageableVoxels(10)
    world:SetDebrisMaxAge(30.0)
end

-- 角色
M.PLAYER_HEIGHT = 1.7
M.PLAYER_RADIUS = 0.35
M.WALK_SPEED = 5.0
M.RUN_SPEED = 8.5
M.JUMP_SPEED = 6.5
M.SWIM_SPEED = 3.0     -- 游泳速度(WASD 朝视向游;Space 上浮 / C 下潜)
M.ENTER_RANGE = 3.5    -- F 键进入载具的搜索半径

-- 工具(玩法配方,详见 docs/design/voxel-physics/scripting-api.md)
M.TOOL_NAMES = { "炸药", "散弹枪", "喷漆", "喷枪" }
M.BOMB_FUSE = 2.2
M.BOMB_RADIUS = 2.2
M.BOMB_POWER = 8.0
M.BOMB_IMPULSE = 5000.0
M.SHOT_PELLETS = 8
M.SHOT_SPREAD = 0.05
M.SHOT_CRATER = 0.3
M.SHOT_POWER = 3.0
M.SHOT_COOLDOWN = 0.45
M.SPRAY_RADIUS = 0.4
M.SPRAY_COOLDOWN = 0.06
M.DIG_RADIUS = 0.45
M.DIG_POWER = 3.0
M.DIG_COOLDOWN = 0.15
M.GRAB_RANGE = 12.0

return M
