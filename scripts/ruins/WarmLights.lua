-- WarmLights.lua — 夜间暖光源：篝火、中世纪路灯、壁挂灯、落地灯盏、蜡烛。
--
-- 每个光源 = 体素外壳（VoxelBrush，visual，不参与物理）+ CascadeParticle 火焰 + 可选点光。
-- 外壳白天也在；火焰与点光只在黄昏到黎明之间点亮，强度跟 DayNight.nightK 平滑变化。
-- 点光按档位限制数量（高 / 中 / 低），超出预算的灯只保留火焰与自发光，不发光照。
-- 点光一律不投影；同一批灯共用一个闪烁波形，循环中不创建 table / Color。
local Brush = require('ruins.VoxelBrush')
local P = require('ruins.RuinsPalette').P

---@class RuinsWarmLights
---@field scene Scene
---@field world VoxelPhysicsWorld
---@field root Node|nil
---@field lamps table[]
---@field volumes VoxelVolume[]
---@field lightBudget number
---@field clock number
---@field disposed boolean
---@field stage integer|nil
---@field on boolean|nil
---@field PALETTE table<string, integer>
---@field KIND table<string, table>
local M = {}
M.__index = M

-- 灯具专用调色板槽位（242..247 未被占用；240/241 是家园灰泥）。
local IRON, IRON_DARK, BRASS, WAX, LOG, EMBER = 242, 243, 244, 245, 246, 247
-- 灯罩玻璃 / 烛焰芯复用家园的 156（window）槽：它的自发光受 window_light 控制，
-- 和窗户一起在夜里变亮，白天看起来是暗玻璃。
local GLASS = 156
M.PALETTE = { IRON = IRON, IRON_DARK = IRON_DARK, BRASS = BRASS, WAX = WAX, LOG = LOG, EMBER = EMBER }

---@param world VoxelPhysicsWorld
function M.SetupPalette(world)
    for _, e in ipairs({
        -- 熟铁：暗、偏冷、半金属；黄铜：灯罩边框与烛台
        { IRON, { .16, .155, .15 }, .62, .55, nil },
        { IRON_DARK, { .09, .088, .085 }, .70, .45, nil },
        { BRASS, { .55, .40, .19 }, .42, .85, nil },
        -- 蜡：奶白，带一点自发光让烛身被火焰"透亮"
        { WAX, { .90, .85, .72 }, .60, 0, { 1, .78, .48, .05 } },
        { LOG, { .30, .20, .12 }, .92, 0, nil },
        -- 炭火：夜里由点光与粒子负责主要亮度，这里只是暗红余烬（白天也只是微红）
        { EMBER, { .45, .14, .05 }, .85, 0, { 1, .36, .10, .22 } },
    }) do
        local id, c, rough, metal, emi = e[1], e[2], e[3], e[4], e[5]
        world:SetPaletteEntry(id, Color(c[1], c[2], c[3]), 50)
        world:SetPaletteEntryPBR(id, rough, metal, .5, emi and Color(emi[1], emi[2], emi[3], emi[4]) or Color(0, 0, 0, 0))
    end
end

-- 光源类型：点光范围 / 亮度（夜间满强度）/ 颜色 / 火焰特效 / 点光离火焰的高度
local KIND = {
    campfire = { range = 9.5, brightness = 5.2, color = { 1, .52, .20 }, effect = 'Effects/Warm/Campfire.effect', lift = .55 },
    streetlamp = { range = 8.0, brightness = 3.6, color = { 1, .62, .30 }, effect = 'Effects/Warm/LanternFlame.effect', lift = 0 },
    wall = { range = 4.6, brightness = 1.9, color = { 1, .60, .30 }, effect = 'Effects/Warm/LanternFlame.effect', lift = 0 },
    floor = { range = 4.2, brightness = 1.7, color = { 1, .60, .30 }, effect = 'Effects/Warm/LanternFlame.effect', lift = 0 },
    torch = { range = 6.0, brightness = 2.6, color = { 1, .50, .18 }, effect = 'Effects/Warm/TorchFlame.effect', lift = .25 },
    candles = { range = 2.6, brightness = .9, color = { 1, .64, .34 }, effect = 'Effects/Warm/LanternFlame.effect', lift = .05 },
    -- 室内吊灯：从天花板垂链吊下的铁灯笼
    hanging = { range = 5.2, brightness = 2.2, color = { 1, .66, .38 }, effect = 'Effects/Warm/LanternFlame.effect', lift = 0 },
    -- 已有体素灯具（家园正墙小壁灯）只补一盏点光和火苗，不建外壳
    fixture = { range = 4.2, brightness = 1.6, color = { 1, .62, .32 }, effect = 'Effects/Warm/LanternFlame.effect', lift = 0 },
}
M.KIND = KIND

-- ---------------------------------------------------------------- 体素外壳
-- 所有尺寸单位米；brush 局部坐标原点就是灯具底部中心。返回火焰相对底部的高度。

---@param b VoxelBrush
local function BuildCampfire(b)
    -- 一圈 10 块不规则的河石，内圈炭床，交叉的四根柴
    for i = 0, 9 do
        local a = i * math.pi / 5 + (i % 2) * .12
        local r = .5 + (i % 3) * .03
        local x, z = math.cos(a) * r, math.sin(a) * r
        local h = .125 + (i % 2) * .0625
        b:Box(x - .1, 0, z - .1, x + .1, h, z + .1, i % 3 == 0 and P.STONE_MOSS or (i % 2 == 0 and P.STONE_C or P.STONE_D))
    end
    b:Cylinder(0, 0, .36, 0, .0625, EMBER)
    for i = 0, 3 do
        local a = i * math.pi / 2 + .4
        local dx, dz = math.cos(a), math.sin(a)
        -- 柴从外沿斜靠向中心：四段由低到高
        for s = 0, 4 do
            local t = s / 4
            local r = .34 - t * .26
            local y = .0625 + t * .30
            local x, z = dx * r, dz * r
            b:Box(x - .05, y, z - .05, x + .05, y + .0625, z + .05, LOG)
        end
    end
    b:Box(-.0625, .0625, -.0625, .0625, .125, .0625, EMBER)
    return .1
end

-- 中世纪路灯：石基座、熟铁灯柱、卷边挑臂、四面玻璃方灯笼、尖顶
---@param b VoxelBrush
local function BuildStreetLamp(b, height)
    local h = height or 3.0
    b:Box(-.25, 0, -.25, .25, .125, .25, P.HOME_PLINTH)
    b:Box(-.1875, .125, -.1875, .1875, .25, .1875, P.HOME_COPING)
    b:Box(-.0625, .25, -.0625, .0625, h - .25, .0625, IRON)
    -- 柱身两道箍
    for _, y in ipairs({ .5, h - .75 }) do b:Box(-.09375, y, -.09375, .09375, y + .0625, .09375, IRON_DARK) end
    -- 挑臂向 +X 伸出，末端吊灯笼
    b:Box(-.0625, h - .25, -.0625, .5, h - .1875, .0625, IRON)
    b:Box(.0625, h - .4375, -.03125, .125, h - .25, .03125, IRON) -- 斜撑
    b:Box(.125, h - .375, -.03125, .1875, h - .3125, .03125, IRON)
    local lx, top = .4375, h - .1875
    b:Box(lx - .03125, top - .125, -.03125, lx + .03125, top, .03125, IRON_DARK) -- 吊钩
    -- 灯笼：上顶、四柱、玻璃、下托
    local y1, y0 = top - .125, top - .625
    b:Box(lx - .1875, y1 - .0625, -.1875, lx + .1875, y1, .1875, IRON_DARK)
    b:Box(lx - .125, y1, -.125, lx + .125, y1 + .0625, .125, IRON_DARK)
    b:Box(lx - .0625, y1 + .0625, -.0625, lx + .0625, y1 + .125, .0625, BRASS)
    for _, sx in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
        b:Box(lx + sx * .125 - .03125, y0, sz * .125 - .03125, lx + sx * .125 + .03125, y1 - .0625, sz * .125 + .03125, IRON)
    end end
    b:Box(lx - .09375, y0 + .0625, -.125, lx + .09375, y1 - .0625, .125, GLASS)
    b:Box(lx - .125, y0 + .0625, -.09375, lx + .125, y1 - .0625, .09375, GLASS)
    b:Box(lx - .15625, y0 - .0625, -.15625, lx + .15625, y0, .15625, IRON_DARK)
    b:Box(lx - .03125, y0 - .125, -.03125, lx + .03125, y0 - .0625, .03125, BRASS)
    -- 火焰在玻璃内偏下（灯芯处）
    return Vector3(lx, y0 + .125, 0)
end

-- 壁挂铁灯笼：墙托 + 弯臂 + 小灯笼。局部 +Z 背向墙（灯笼朝 +Z 伸出）
---@param b VoxelBrush
local function BuildWallLantern(b)
    b:Box(-.09375, -.1875, 0, .09375, .1875, .0625, IRON_DARK) -- 墙托板
    b:Box(-.03125, .09375, .0625, .03125, .15625, .3125, IRON)  -- 挑臂
    b:Box(-.03125, -.09375, .0625, .03125, .09375, .125, IRON)  -- 斜撑
    local z = .3125
    b:Box(-.03125, .03125, z - .03125, .03125, .09375, z + .03125, IRON_DARK)
    b:Box(-.125, -.03125, z - .125, .125, .03125, z + .125, IRON_DARK) -- 顶
    for _, sx in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
        b:Box(sx * .09375 - .03125, -.34375, z + sz * .09375 - .03125, sx * .09375 + .03125, -.03125, z + sz * .09375 + .03125, IRON)
    end end
    b:Box(-.0625, -.3125, z - .09375, .0625, -.03125, z + .09375, GLASS)
    b:Box(-.09375, -.3125, z - .0625, .09375, -.03125, z + .0625, GLASS)
    b:Box(-.125, -.40625, z - .125, .125, -.34375, z + .125, IRON_DARK)
    return Vector3(0, -.28, z)
end

-- 落地灯盏：铁三脚架上的方灯笼（露台、廊下），高约 1.1m
---@param b VoxelBrush
local function BuildFloorLantern(b)
    b:Box(-.1875, 0, -.1875, .1875, .0625, .1875, IRON_DARK)
    for _, sx in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
        b:Box(sx * .125 - .03125, .0625, sz * .125 - .03125, sx * .125 + .03125, .125, sz * .125 + .03125, IRON)
    end end
    b:Box(-.03125, .0625, -.03125, .03125, .625, .03125, IRON)
    b:Box(-.15625, .625, -.15625, .15625, .6875, .15625, IRON_DARK)
    for _, sx in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
        b:Box(sx * .125 - .03125, .6875, sz * .125 - .03125, sx * .125 + .03125, 1.0625, sz * .125 + .03125, IRON)
    end end
    b:Box(-.09375, .6875, -.125, .09375, 1.0625, .125, GLASS)
    b:Box(-.125, .6875, -.09375, .125, 1.0625, .09375, GLASS)
    b:Box(-.15625, 1.0625, -.15625, .15625, 1.125, .15625, IRON_DARK)
    b:Box(-.09375, 1.125, -.09375, .09375, 1.1875, .09375, IRON_DARK)
    b:Box(-.03125, 1.1875, -.03125, .03125, 1.25, .03125, BRASS)
    return Vector3(0, .78, 0)
end

-- 柱上火盆：铁箍托架 + 小铁碗，挂在柱面上。局部 +Z 背离柱面
---@param b VoxelBrush
local function BuildTorch(b)
    b:Box(-.0625, -.25, 0, .0625, .125, .0625, IRON_DARK)
    b:Box(-.03125, -.1875, .0625, .03125, -.125, .25, IRON)
    b:Box(-.03125, -.125, .1875, .03125, .0625, .25, IRON)
    local z = .25
    b:Box(-.125, .0625, z - .125, .125, .125, z + .125, IRON_DARK)
    b:Box(-.15625, .125, z - .15625, .15625, .25, z + .15625, IRON)
    b:Box(-.09375, .1875, z - .09375, .09375, .25, z + .09375, EMBER)
    return Vector3(0, .25, z)
end

-- 一簇三根高低不同的蜡烛（柱脚 / 台阶边）。蜡烛很细：1/32m 网格
---@param b VoxelBrush
local function BuildCandles(b, seed)
    local s = seed or 0
    local list = { { 0, 0, .25 }, { .12, .05, .17 }, { -.06, .11, .12 } }
    local tops = {}
    for i, c in ipairs(list) do
        local a = s * 1.7
        local x = c[1] * math.cos(a) - c[2] * math.sin(a)
        local z = c[1] * math.sin(a) + c[2] * math.cos(a)
        local h = c[3]
        b:Box(x - .046875, 0, z - .046875, x + .046875, .03125, z + .046875, BRASS)
        b:Box(x - .03125, .03125, z - .03125, x + .03125, h, z + .03125, WAX)
        -- 顶部流下的蜡泪
        b:Box(x + .03125, h - .0625, z - .015625, x + .046875, h - .015625, z + .015625, WAX)
        b:Box(x - .0078, h, z - .0078, x + .0078, h + .03125, z + .0078, IRON_DARK) -- 灯芯
        tops[i] = Vector3(x, h + .03, z)
    end
    return tops[1], tops
end

-- 吊灯：链条从 0（天花板）垂到 -drop，下面挂四面灯笼
---@param b VoxelBrush
local function BuildHanging(b, drop)
    b:Box(-.09375, -.0625, -.09375, .09375, 0, .09375, IRON_DARK) -- 天花板吊环座
    local y = -.0625
    local i = 0
    while y > -drop + .4 do
        local w = i % 2 == 0 and .03125 or .015625
        b:Box(-w, y - .125, -.015625, w, y, .015625, IRON)
        y = y - .125; i = i + 1
    end
    local y1, y0 = y, y - .4375
    b:Box(-.15625, y1 - .0625, -.15625, .15625, y1, .15625, IRON_DARK)
    for _, sx in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
        b:Box(sx * .125 - .03125, y0, sz * .125 - .03125, sx * .125 + .03125, y1 - .0625, sz * .125 + .03125, IRON)
    end end
    b:Box(-.09375, y0 + .0625, -.125, .09375, y1 - .0625, .125, GLASS)
    b:Box(-.125, y0 + .0625, -.09375, .125, y1 - .0625, .09375, GLASS)
    b:Box(-.15625, y0 - .0625, -.15625, .15625, y0, .15625, IRON_DARK)
    b:Box(-.03125, y0 - .125, -.03125, .03125, y0 - .0625, .03125, BRASS)
    return Vector3(0, y0 + .1, 0)
end

-- ---------------------------------------------------------------- 管理

---@param scene Scene
---@param world VoxelPhysicsWorld
---@param name string
---@return RuinsWarmLights
function M.New(scene, world, name)
    local self = setmetatable({}, M)
    self.scene, self.world = scene, world
    self.root = scene:CreateChild(name or 'WarmLights')
    ---@type table[]
    self.lamps = {}
    self.lightBudget = 99
    self.clock, self.disposed, self.stage = 0, false, nil
    ---@type VoxelVolume[]
    self.volumes = {}
    return self
end

-- 同一种特效资源只加载一次
---@type table<string, CascadeParticleSystem|false>
local effectCache = {}
---@return CascadeParticleSystem|nil
local function Effect(path)
    if not path then return nil end
    local e = effectCache[path]
    if e == nil then
        e = cache:GetResource('CascadeParticleSystem', path) or false
        if not e then print('WarmLights: missing effect ' .. path) end
        effectCache[path] = e
    end
    return e or nil
end

-- o = { kind, pos (Vector3 世界坐标，底部中心), yaw (度), height (路灯), priority (越小越优先拿点光), seed }
---@param o { kind: string, pos: Vector3, yaw: number?, height: number?, priority: number?, seed: number?, drop: number?, range: number?, brightness: number?, first: integer?, last: integer?, home: boolean? }
function M:Add(o)
    local kind = KIND[o.kind]
    assert(kind, 'WarmLights: unknown kind ' .. tostring(o.kind))
    local yaw = o.yaw or 0
    ---@type Node|nil
    local lamp_shell = nil
    ---@type Vector3
    local flame
    ---@type Vector3[]|nil
    local flames
    if o.kind ~= 'fixture' then
        local fine = (o.kind == 'candles') and .03125 or .0625
        local half = ({ campfire = .7, streetlamp = .75, wall = .45, floor = .3, torch = .4, candles = .25, hanging = .25 })[o.kind]
        local lo, hi
        if o.kind == 'hanging' then
            lo, hi = { -half, -(o.drop or 1.2) - .1, -half }, { half, .05, half }
        elseif o.kind == 'wall' or o.kind == 'torch' then
            lo, hi = { -half, -.5, -.1 }, { half, .4, half * 2 }
        elseif o.kind == 'streetlamp' then
            lo, hi = { -.4, 0, -.4 }, { .8, (o.height or 3.0) + .2, .4 }
        else
            lo, hi = { -half, 0, -half }, { half, o.kind == 'floor' and 1.3 or .6, half }
        end
        local b = Brush.New(self.world, { origin = o.pos, yaw = yaw, min = lo, max = hi, size = fine, name = 'WarmLight-' .. o.kind })
        if o.kind == 'campfire' then flame = Vector3(0, BuildCampfire(b), 0)
        elseif o.kind == 'streetlamp' then flame = BuildStreetLamp(b, o.height)
        elseif o.kind == 'wall' then flame = BuildWallLantern(b)
        elseif o.kind == 'floor' then flame = BuildFloorLantern(b)
        elseif o.kind == 'torch' then flame = BuildTorch(b)
        elseif o.kind == 'hanging' then flame = BuildHanging(b, o.drop or 1.2)
        else flame, flames = BuildCandles(b, o.seed) end
        -- 路灯、篝火有碰撞（玩家不会穿过灯柱）；小灯具只渲染。
        -- 家园灯具用 homeWindows 材质：灯罩玻璃（156 槽）跟窗户一起由 window_light 点亮。
        local solid = o.kind == 'streetlamp' or o.kind == 'campfire'
        local v = b:Finish({ visual = not solid, masonry = o.home and 'homeWindows' or nil })
        if v then
            local node = v:GetNode()
            node.name = 'WarmLightShell-' .. o.kind
            self.volumes[#self.volumes + 1] = v
            lamp_shell = node
            -- 小灯具：近处才投影，远处直接不画（与 RenderBudget 的小体素同规则）
            for _, d in ipairs(node:GetComponents('CustomGeometry', true)) do
                local dr = d --[[@as Drawable]]
                dr.shadowDistance = o.kind == 'campfire' and 30 or 18
                dr.drawDistance = o.kind == 'streetlamp' and 120 or 70
            end
        end
    else
        flame = Vector3(0, 0, 0)
    end
    local rot = Quaternion(yaw, Vector3.UP)
    local base = o.pos
    local root = self.root --[[@as Node]]
    local node = root:CreateChild('Warm-' .. o.kind)
    local offset = rot * flame --[[@as Vector3]]
    node.position = base + offset
    local lamp = { kind = o.kind, def = kind, node = node, shell = lamp_shell, priority = o.priority or 5, light = nil, fx = {},
        phase = (#self.lamps + 1) * 2.1, first = o.first or 0, last = o.last or 99, shown = true }
    -- 火焰粒子：蜡烛每根一簇，其余一处
    local fx = Effect(kind.effect)
    if fx then
        local points = flames or { flame }
        for _, p in ipairs(points) do
            local turned = rot * p --[[@as Vector3]]
            local at = base + turned
            local s = o.kind == 'candles' and .55 or 1.0
            local inst = CascadeParticle.SpawnEmitterAttached(fx, root, at, Quaternion(), Vector3(s, s, s), false, CASCADE_POOL_NONE, false)
            if inst then lamp.fx[#lamp.fx + 1] = inst end
        end
    end
    local lightNode = node:CreateChild('WarmPoint')
    lightNode.position = Vector3(0, kind.lift, 0)
    local light = lightNode:CreateComponent('Light')
    light.lightType = LIGHT_POINT
    lamp.color = Color(kind.color[1], kind.color[2], kind.color[3])
    light.color = lamp.color
    light.range = o.range or kind.range
    light.brightness = 0
    light.castShadows = false
    light.useTemperature = false
    light.affectVolumetricFog = false
    light.specularIntensity = .35
    -- 远处的点光直接淡出，只留火焰和自发光
    light.drawDistance = o.kind == 'campfire' and 70 or 45
    light.fadeDistance = light.drawDistance * .75
    lamp.light = light
    lamp.brightness = o.brightness or kind.brightness
    self.lamps[#self.lamps + 1] = lamp
    return lamp
end

-- 点光预算：按 priority 排序后前 N 盏发光；其余只保留火焰。
function M:SetLightBudget(n)
    self.lightBudget = math.max(0, math.floor(n))
    local order = {}
    for _, l in ipairs(self.lamps) do if l.shown then order[#order + 1] = l end end
    table.sort(order, function(a, b) if a.priority ~= b.priority then return a.priority < b.priority end return a.phase < b.phase end)
    for _, l in ipairs(self.lamps) do l.lit = false end
    for i, l in ipairs(order) do l.lit = i <= self.lightBudget end
    for _, l in ipairs(self.lamps) do if not l.lit then l.light.brightness = 0 end end
end

-- 家园房屋阶段：只显示 first..last 覆盖当前阶段的灯（废墟阶段没有室内灯）
function M:SetStage(stage)
    if self.disposed or stage == self.stage then return end
    self.stage = stage
    for _, l in ipairs(self.lamps) do
        l.shown = stage >= l.first and stage <= l.last
        if l.shell then l.shell:SetDeepEnabled(l.shown) end
    end
    self.on = nil -- 下一次 Update 按新的可见集合重新开关火焰
    self:SetLightBudget(self.lightBudget)
end

local function Smooth(x) x = math.max(0, math.min(1, x)); return x * x * (3 - 2 * x) end

-- 夜间强度：黄昏太阳落到地平线附近就上灯，黎明熄灭（与 DayNight.nightK 连续）
---@param dn DayNight
function M.NightLevel(dn)
    return Smooth(((dn.nightK or 0) * 1.15 + (dn.dusk or 0) * .35 * (1 - (dn.day or 1)) - .05) / .9)
end

---@param dn DayNight
function M:Update(dt, dn)
    if self.disposed then return end
    self.clock = self.clock + dt
    local k = M.NightLevel(dn)
    local on = k > .01
    if on ~= self.on then
        self.on = on
        for _, l in ipairs(self.lamps) do
            local live = on and l.shown
            for _, inst in ipairs(l.fx) do
                if live then inst:Activate(false) else inst:Deactivate() end
            end
            l.node:SetDeepEnabled(live)
        end
    end
    if not on then return end
    local t = self.clock
    for _, l in ipairs(self.lamps) do
        if l.lit then
            local p = l.phase
            -- 明火闪烁更大，灯笼与蜡烛（玻璃罩内 / 小火苗）更稳
            local amp = (l.kind == 'campfire' or l.kind == 'torch') and 1 or .45
            local flicker = 1 + amp * (.05 * math.sin(t * 7.3 + p) + .03 * math.sin(t * 13.1 + p * 1.7) + .02 * math.sin(t * 23.7 + p * .6))
            l.light.brightness = l.brightness * k * flicker
        end
    end
end

-- removeVolumes=true 时同时从体素世界移除灯具外壳（家园卸载 / 重建）；
-- 整个场景销毁时传 false，外壳随场景一起释放。
function M:Release(removeVolumes)
    if self.disposed then return end
    self.disposed = true
    if removeVolumes then
        for _, v in ipairs(self.volumes) do
            local node = v:GetNode()
            self.world:RemoveVolume(v)
            v:Dispose()
            if node then node:Dispose() end
        end
    end
    if self.root then self.root:Remove() end
    self.lamps, self.volumes, self.root = {}, {}, nil
end

-- 调试 / 测试：当前发光的点光数
function M:LitCount()
    local n = 0
    for _, l in ipairs(self.lamps) do if l.lit and l.shown then n = n + 1 end end
    return n
end

return M
