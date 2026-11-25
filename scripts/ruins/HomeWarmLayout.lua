-- HomeWarmLayout.lua — 家园的夜间暖光布局（岛局部米坐标，原点 HomeIsland.x/base/z）。
--
--   池边：两盏中世纪铁路灯（挑臂 + 方灯笼），沿池塘到房前的小路
--   正墙：原有五盏小壁灯补上火苗和点光，门廊两侧再挂两盏铁壁灯
--   室内：一层大厅两盏吊灯，二层与阁楼各一盏落地灯盏，光源真正在屋里
--   露台：四角落地灯盏 + 栏杆边两簇蜡烛
--   右侧柱台：圆形石台上柱子与地面衔接处放蜡烛簇，两根高柱挂火盆壁灯
-- first/last 对应房屋建造阶段（0 废墟 1 一层 2 两层 3 完整）：没盖好的楼层不亮灯。
local WarmLights = require('ruins.WarmLights')
local Upper = require('ruins.HomeHouseUpper')

local M = {}
local F = Upper.Footprint
local F2, F3 = F.second, F.third

-- 正墙五盏小壁灯（HomeIsland.wallLantern）玻璃中心：x, y=2.21, z=6.66
local FRONT_FIXTURES = { -13.9375, -11.6875, -8.6875, -6.1875, -3.0625 }

---@param o table
local function lamp(list, o) list[#list + 1] = o end

---@return table[] 灯具定义（岛局部坐标）
function M.Definitions()
    local list = {}
    -- 池边路灯：池塘北岸草带上（池与房前小路之间），一盏在栈桥头，一盏在池西北；
    -- 挑臂朝北，灯笼悬在小路上方
    lamp(list, { kind = 'streetlamp', x = -2.0, z = 2.0, yaw = 270, height = 3.0, priority = 1 })
    lamp(list, { kind = 'streetlamp', x = -12.5, z = 2.0, yaw = 270, height = 3.0, priority = 2 })
    -- 正墙原有小壁灯：只补火苗和点光（中间两盏优先拿点光）
    for i, x in ipairs(FRONT_FIXTURES) do
        lamp(list, { kind = 'fixture', x = x, y = 2.21, z = 6.66, priority = (i == 2 or i == 4) and 3 or 7, first = 1, last = 3 })
    end
    -- 门廊两根立柱（x = -4.125 ± 2.25，前脸 z = 4.125）朝南挂铁壁灯
    for _, x in ipairs({ -6.375, -1.875 }) do
        lamp(list, { kind = 'wall', x = x, y = 2.45, z = 4.1, yaw = 180, priority = 4, first = 1, last = 3 })
    end
    -- 室内：一层大厅两盏吊灯（天花板 = 二层楼板底 F2）；二层、阁楼用落地灯盏
    lamp(list, { kind = 'hanging', x = -9.0, y = F2, z = 11.0, drop = 1.8, priority = 2, first = 1, last = 3 })
    lamp(list, { kind = 'hanging', x = -13.5, y = F2, z = 11.0, drop = 1.8, priority = 6, first = 1, last = 3, range = 4.5, brightness = 1.5 })
    lamp(list, { kind = 'floor', x = -8.5, y = F2 + .25, z = 11.0, priority = 3, first = 2, last = 3 })
    lamp(list, { kind = 'floor', x = -11.5, y = F3 + .25, z = 11.0, priority = 5, first = 3, last = 3 })
    -- 露台（台面 F3+.25）：三角落地灯盏（避开盆栽、花槽与入口），前栏杆内侧两簇蜡烛
    local deck = F3 + .25
    lamp(list, { kind = 'floor', x = F.split + .7, y = deck, z = F.z1 - .9, priority = 4, first = 3, last = 3 })
    lamp(list, { kind = 'floor', x = F.x1 - .75, y = deck, z = F.z0 + .7, priority = 4, first = 3, last = 3 })
    lamp(list, { kind = 'floor', x = F.x1 - .75, y = deck, z = F.z1 - 2.2, priority = 6, first = 3, last = 3 })
    lamp(list, { kind = 'candles', x = F.split + 2.6, y = deck, z = F.z0 + .6, seed = 1, priority = 8, first = 3, last = 3 })
    lamp(list, { kind = 'candles', x = F.split + 4.4, y = deck, z = F.z0 + .6, seed = 2, priority = 8, first = 3, last = 3 })
    -- 右侧废墟柱台：台面 y=1.75，圆心 (12,3)，半径 8.3；现存柱位 i=0,1,8,10,11。
    -- 柱础半宽 .75（外加 .125 线脚），蜡烛簇放在柱础内侧（朝台心）和侧旁，贴着柱脚。
    local cx, cz, R = 12, 3, 8.3
    for _, i in ipairs({ 0, 1, 8, 10, 11 }) do
        local a = i * math.pi / 6
        local px, pz = cx + R * math.cos(a), cz + R * math.sin(a)
        local ix, iz = -math.cos(a), -math.sin(a)
        lamp(list, { kind = 'candles', x = px + ix * 1.15, y = 1.75, z = pz + iz * 1.15, seed = i, priority = (i == 0 or i == 8) and 5 or 9 })
        lamp(list, { kind = 'candles', x = px + ix * 1.1 - iz * .55, y = 1.75, z = pz + iz * 1.1 + ix * .55, seed = i + 7, priority = 10 })
    end
    -- 高柱 i=1（19.19, 7.15，高 2.75）：火盆挂在朝台心的 -X 面
    lamp(list, { kind = 'torch', x = 19.19 - .52, y = 3.1, z = 7.15, yaw = 270, priority = 3 })
    -- 遗迹大拱两墩（12 ± 4.15, 10.19）：火盆挂在朝台心的 -Z 面（避开立面上的凸条）
    for _, x in ipairs({ 12 - 4.15, 12 + 4.15 }) do
        lamp(list, { kind = 'torch', x = x, y = 3.6, z = 10.19 - .64, yaw = 180, priority = 3 })
    end
    return list
end

---@param scene Scene 家园建造任务的根节点（随家园一起移除）
---@param world VoxelPhysicsWorld
---@param origin Vector3 岛原点（HomeIsland.x, base, z）
---@param heightAt fun(x: number, z: number): number 地面高度（世界坐标）
function M.Build(scene, world, origin, heightAt)
    local lights = WarmLights.New(scene, world, 'HomeWarmLights')
    for _, d in ipairs(M.Definitions()) do
        d.pos = Vector3(origin.x + d.x, origin.y + (d.y or 0), origin.z + d.z)
        d.home = true
        if d.kind == 'streetlamp' then
            -- 路灯底座落在地面上
            d.pos.y = heightAt(d.pos.x, d.pos.z)
        end
        lights:Add(d)
    end
    return lights
end

return M
