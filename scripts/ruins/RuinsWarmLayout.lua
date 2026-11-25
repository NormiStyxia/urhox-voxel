-- RuinsWarmLayout.lua — 时之遗迹的夜间篝火布局。
--
-- 原来夜里只有柱顶火盆。这里在外环草地的几处空地上放篝火：
-- 彼此相隔 30m 以上，每处照亮约 9m 半径的一块区域，不会连成一片"满天星"。
-- 坐标由运行时地面探针挑出（平坦、安全永久岛面、离岛缘 >4m、不在路上、
-- 不在谜题保留区、离树 >5m）；放置时再次校验，地形变化后不合格的点直接跳过。
-- 另在南门内侧两边各放一支柱式火把，玩家出生后第一眼就能看到暖光。
local WarmLights = require('ruins.WarmLights')
local Terrain = require('ruins.RuinsTerrain')

local M = {}

-- { x, z, yaw, 优先级（越小越先拿到点光） }
local CAMPFIRES = {
    { -7, -55, 20, 1 },  -- 南门内侧：出生点前方
    { 57, 9, 110, 2 },   -- 东侧草甸
    { -54, 10, 250, 2 }, -- 西侧草甸
    { 41, 44, 40, 3 },   -- 东北角
    { -47, 39, 320, 3 }, -- 西北角
    { 50, -38, 160, 4 }, -- 东南角
    { -50, -41, 200, 4 },-- 西南角
}
M.CAMPFIRES = CAMPFIRES

---@param scene Scene
---@param world VoxelPhysicsWorld
---@return table|nil
function M.Build(scene, world)
    WarmLights.SetupPalette(world)
    local lights = WarmLights.New(scene, world, 'RuinsWarmLights')
    local placed = 0
    for _, c in ipairs(CAMPFIRES) do
        local x, z = c[1], c[2]
        local y = Terrain.GroundHeight(x, z)
        if y and Terrain.IsSafeGround(x, y, z) and Terrain.EdgeDistance(x, z) > 3 then
            lights:Add({ kind = 'campfire', pos = Vector3(x, y, z), yaw = c[3], priority = c[4] })
            placed = placed + 1
        else
            print(string.format('RuinsWarmLayout: campfire (%.1f, %.1f) skipped: unsafe ground', x, z))
        end
    end
    print('RuinsWarmLayout: campfires ' .. placed .. '/' .. #CAMPFIRES)
    return lights
end

return M
