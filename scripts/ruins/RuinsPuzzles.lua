-- ====================================================================
-- RuinsPuzzles.lua — 解谜流程与时之物件的摆放
--
-- 路线（玩家从南边出生点 (0, 6, -64) 出发）：
--
--   ① 封门乱石（南城门 z≈-51）：一堆 0.25m 体素的乱石把门洞堵死。
--      → 学会「碎时」：乱石是普通可破坏体素，诺米的碎时直接打碎（引擎弹坑 + 崩落碎块）。
--   ② 断桥（南侧峡谷 z∈[-48.5, -39.5]）：石桥残块悬停在裂隙中与两岸。
--      → 学会「回溯」：对准任意碎块施放回溯，整座桥沿弧线飞回、合成完整的桥。
--   ③ 悬石阶梯（西侧内环，柱廊外的高台）：一块巨石被锁链挂在断拱下。打碎它，碎块下落时
--      施放「冻结」，碎块悬停成为跳台，爬上高台拿到「时之钥」（高台上的金色光点）。
--      冻结持续 10 秒，失败可以回溯巨石重来。
--   ④ 四座时之碑（内环 45°/135°/225°/315°）：碑体倒塌成碎块，散在底座周围。
--      必须先拿到时之钥（第 ③ 步）才能回溯碑体（碑身有封印，钥匙解锁回溯）。
--      依次回溯四座碑 → 龙庭法阵逐环点亮 → 龙苏醒（咆哮 + 展翼），遗迹看守者认可诺米。
--
-- 时之物件带「时之印记」材质（TimeVoxel.shader：金色符脉 + 蓝色脉冲），瞄准时描边发亮。
-- ====================================================================

local Brush = require("ruins.VoxelBrush")
local Noise = require("ruins.Noise")
local Pal = require("ruins.RuinsPalette")
local Terrain = require("ruins.RuinsTerrain")
local Build = require("ruins.RuinsBuild")
local TimeObject = require("ruins.TimeObject")
local P = Pal.P

local M = {}

local sin, cos, sqrt, floor, abs, max, min, pi = math.sin, math.cos, math.sqrt, math.floor, math.abs, math.max, math.min, math.pi
local Hash3 = Noise.Hash3

M.objects = {}      -- 全部时之物件（按 id）
M.list = {}
M.steps = {}        -- 进度：gate / bridge / key / stele1..4 / awake
M.events = {}       -- 回调：fn(name, data)

function M.On(fn) M.events[#M.events + 1] = fn end
local function Emit(name, data)
    for _, fn in ipairs(M.events) do fn(name, data) end
end

local function Add(obj)
    M.objects[obj.id] = obj
    M.list[#M.list + 1] = obj
    return obj
end

-- 把 brush 画好的体积转成 TimeObject 需要的体素表（然后删掉临时体积）
---@param b VoxelBrush
local function Harvest(world, b)
    local vox = b:Collect()
    local o = { voxels = vox, dims = { b.nx, b.ny, b.nz }, origin = b.origin + b.rot * Vector3(b.lmin[1] or 0, b.lmin[2] or 0, b.lmin[3] or 0), yaw = b.yaw, size = b.s }
    local volume = b.volume
    local node = volume:GetNode()
    volume.collisionMask = 0
    world:RemoveVolume(volume)
    volume:Dispose()
    if node ~= nil then node:Dispose() end
    return o
end

-- ---------------------------------------------------------------- ① 封门乱石
-- 普通可破坏体素（硬度 1），不是时之物件：碎了就碎了
local function BuildGateRubble(world)
    local R = Terrain.WALL_R
    local b = Brush.New(world, { min = { -3.2, Terrain.RING_Y - 0.25, -R - 2.2 }, max = { 3.2, Terrain.RING_Y + 4.6, -R + 2.2 }, size = 0.25 })
    local rng = Noise.Rng(5)
    -- 一堆大小不一的石块（椭球堆叠）
    for i = 1, 26 do
        local x = rng:Range(-2.4, 2.4)
        local z = -R + rng:Range(-1.4, 1.4)
        local y = Terrain.RING_Y + rng:Range(0.0, 3.6) * (1 - abs(x) / 3.2)
        local r = rng:Range(0.6, 1.3)
        local m = Pal.RUBBLES[rng:Int(1, 3)]
        b:Ellipsoid(x, y, z, r, r * rng:Range(0.6, 0.9), r * rng:Range(0.7, 1.0), function(px, py, pz)
            if py < Terrain.RING_Y then return nil end
            if Hash3(floor(px * 4), floor(py * 4), floor(pz * 4)) < 0.12 then return P.RUBBLE_C end
            return m
        end)
    end
    -- 填满门洞下半部，确保过不去（门洞宽 5.2、高 4.5）
    b:Shape(-2.6, Terrain.RING_Y, -R - 0.8, 2.6, Terrain.RING_Y + 3.0, -R + 0.8, function(x, y, z)
        local h = Hash3(floor(x * 4), floor(y * 4), floor(z * 4))
        return Pal.Pick(Pal.RUBBLES, h)
    end)
    local v = b:Finish({ destructible = true })
    -- 碎石堆单独一份材质，选中红光不影响同尺寸的其它建筑
    if v ~= nil and v.material ~= nil then
        local own = v.material:Clone()
        if own ~= nil then v.material = own; M.gateMaterial = own end
    end
    M.gateRubble = v
    M.gateRubbleSolid0 = v and v:GetSolidCount() or 0
    print("RuinsPuzzles: gate rubble voxels " .. M.gateRubbleSolid0)
end

-- ---------------------------------------------------------------- ② 断桥
-- 桥：沿 z 跨越峡谷，z ∈ [-49.75, -38.25]，宽 4.5m，0.125m 体素（与柱廊、城墙细部同精度）。
--
--   横截面（ly = y - RING_Y）：
--        扶手冠 0.5 ┌┐            ┌┐  1.0..1.125
--        扶手   0.75┴┴┐        ┌┴┴┘  0.875..1.0（外挑，外缘金线）
--        宝瓶柱      ││        ││    0.25..0.875（间距 0.625，0.25 方柱 + 0.5 柱础/柱头）
--        柱座   ────┘└─┐    ┌─┘└──  0.0..0.25（|x| 1.75..2.25）
--        桥面 D=0.25 ══════════════  中线蓝符文（金边内嵌）；两端最后 0.5m 降为 0.125 台阶
--        檐口 |x|≤2.25 ▔▔▔▔▔▔▔▔▔▔▔  -0.125..D；-0.375..-0.125 收到 2.125
--        拱肩 |x|≤2.0  错缝砌石，外层石缝凹进一格
--        拱券石        ╲__________╱  拱腹 bottom = -0.75 - 1.9u²，拱心石外凸 + 金色符印
--
-- 防闪烁：桥面顶 ≥ RING_Y + 0.125，任何外露水平面都不与两岸地表（y = RING_Y）共面。
-- 诺米 stepHeight 0.55，两级 0.125 台阶可以直接走上去。
local BRIDGE_D = 0.25
local function BridgeVoxels(world)
    local z0, z1 = -49.75, -38.25
    local Y = Terrain.RING_Y
    local s = Build.DETAIL.column
    local b = Brush.New(world, { min = { -2.5, Y - 2.75, z0 }, max = { 2.5, Y + 1.5, z1 }, size = s })
    local zc, half = (z0 + z1) * 0.5, (z1 - z0) * 0.5
    -- 栏杆竖件位置：端柱 / 中柱 / 宝瓶柱
    local function PostKind(z)
        local dz0, dz1 = z - z0, z1 - z
        if (dz0 > 0.25 and dz0 < 0.75) or (dz1 > 0.25 and dz1 < 0.75) or abs(z - zc) < 0.25 then return "newel" end
        local f = ((z - z0) / 0.625) % 1
        if f > 0.3 and f < 0.7 then return "baluster" end
        return nil
    end
    -- 拱肩错缝砌石：0.5m 一层，块长 1.0m；返回块哈希与是否在石缝上
    local function Ashlar(y, z)
        local row = floor(y * 2.0)
        local zz = z + (row % 2) * 0.5
        local fy, fz = (y * 2.0) % 1, zz % 1
        local joint = fy < 0.25 or fz < 0.125
        return Hash3(row, floor(zz), 17), joint
    end
    b:Shape(-2.5, Y - 2.75, z0, 2.5, Y + 1.5, z1, function(x, y, z)
        local ax = abs(x)
        local u = (z - zc) / half
        local ly = y - Y
        local edgeZ = min(z - z0, z1 - z)
        local deck = edgeZ < 0.5 and 0.125 or BRIDGE_D
        local bottom = -0.75 - 1.9 * u * u
        local key = abs(z - zc) < 0.375
        -- ---------------- 桥身（檐口以下）
        if ly < -0.125 then
            if ly < bottom then return nil end
            local lim = (ly >= -0.375) and 2.125 or 2.0
            if key and ly < -0.375 then lim = 2.125 end -- 拱心石外凸
            if ax > lim then return nil end
            local outer = ax > lim - s
            local vous = ly < bottom + 0.5
            if key and ly < -0.375 then
                if outer and abs(z - zc) < 0.125 and ly > bottom + 0.125 and ly < bottom + 0.5 then return P.RUNE_GOLD end
                if outer and abs(z - zc) > 0.25 then return P.MARBLE_B end
                return P.MARBLE_A
            end
            if vous then
                -- 拱券石：沿拱 0.5m 一块，外层券缝凹进
                local f = ((z - zc) / 0.5) % 1
                if outer and f < 0.25 then return nil end
                if outer and ly < bottom + 0.125 then return P.MARBLE_B end
                local h = Hash3(floor((z - zc) / 0.5), 3, 23)
                return h < 0.6 and P.MARBLE_A or P.MARBLE_B
            end
            if ly >= -0.375 then
                -- 檐口下层：顶面落苔
                return P.MARBLE_B
            end
            -- 拱肩
            local h, joint = Ashlar(y, z)
            if outer and joint then return nil end
            if h < 0.55 then return P.MARBLE_A end
            return P.MARBLE_B
        end
        -- ---------------- 檐口 + 桥面
        if ly < deck then
            if ax > 2.25 then return nil end
            if ax > 2.125 and ly < 0.0 then return P.STONE_B end -- 滴水线
            if ax > 1.75 then return P.MARBLE_B end
            local top = ly > deck - s
            if top then
                -- 中线符文：蓝芯金边，0.5m 一节，间隔 1.25m
                -- 中线只留一格宽的细符文线，不再铺深色宽边
                if abs(u) < 0.88 then
                    local f = ((z - zc) / 1.25 + 0.2) % 1
                    if ax < 0.0625 and f > 0.15 and f < 0.45 then return P.RUNE_BLUE end
                end
                -- 铺石：1.0 × 0.75m 错缝石板，缝用深色（不挖槽，避免低于两岸地表）
                local row = floor((z - z0) / 0.75)
                local xx = x + (row % 2) * 0.5
                local fz, fx = ((z - z0) / 0.75) % 1, xx % 1
                -- 石缝用浅一档的同色系，近看是细缝，远看不成网格
                if fz < 0.17 or fx < 0.125 then return P.TILE_B end
                if edgeZ < 0.5 and edgeZ > 0.375 then return P.MARBLE_B end -- 台阶前沿
                local h = Hash3(row, floor(xx), 29)
                if h < 0.55 then return P.TILE_A elseif h < 0.9 then return P.MARBLE_A end
                return P.MARBLE_B
            end
            return P.MARBLE_B
        end
        -- ---------------- 栏杆
        -- 栏杆统一以主桥面为基准；端部台阶处用柱座补齐，端柱不出现错台
        local py = ly - BRIDGE_D
        if py < 0 then
            if ax >= 1.75 and ax <= 2.25 then return P.MARBLE_B end
            return nil
        end
        if edgeZ < 0.25 and py >= 0.25 then return nil end -- 端柱外不再伸出扶手
        local kind = PostKind(z)
        if kind == "newel" then
            -- 端柱 / 中柱：0.5 方柱，0.75 柱帽，金顶
            local cz = (abs(z - zc) < 0.25) and zc or ((z - z0 < 1.0) and z0 + 0.5 or z1 - 0.5)
            local dz = abs(z - cz)
            local dx = abs(ax - 2.0)
            if py < 1.25 then
                if dx < 0.25 and dz < 0.25 then
                    if py < 0.125 then return P.STONE_B end
                    if dx > 0.125 and dz > 0.125 and py > 0.5 and py < 0.75 then return P.RUNE_GOLD end
                    return P.MARBLE_A
                end
            elseif py < 1.375 then
                if dx < 0.375 and dz < 0.375 then return P.MARBLE_B end
            elseif dx < 0.125 and dz < 0.125 then
                return P.GOLD
            end
        end
        if ax < 1.75 or ax > 2.25 then return nil end
        local dx = abs(ax - 2.0)
        if py < 0.25 then
            -- 柱座：顶层收进一格
            if py > 0.125 and dx > 0.125 then return nil end
            return P.MARBLE_B
        end
        if py < 0.875 then
            if kind ~= "baluster" then return nil end
            local f = ((z - z0) / 0.625) % 1
            local dzb = abs(f - 0.5) * 0.625
            -- 宝瓶柱：柱础 / 柱头 0.5 方，柱身 0.25 方
            local w = (py < 0.375 or py > 0.75) and 0.25 or 0.125
            if dx < w and dzb < w then return P.MARBLE_A end
            return nil
        end
        if py < 1.0 then return P.MARBLE_B end
        if py < 1.125 then
            if dx > 0.25 then return nil end
            -- 扶手冠：石材，顶面偶有苔痕（金色只留在端柱，否则金属面背光时像一条深色木板）
            return P.MARBLE_A
        end
        return nil
    end)
    return Harvest(world, b)
end

local function BuildBridge(world, scene)
    local o = BridgeVoxels(world)
    o.id = "bridge"
    o.world, o.scene = world, scene
    o.seed = 11
    o.shattered = true
    o.shatterLevel = 2
    o.canShatter = false -- 桥修好后不能再碎（避免玩家把自己的路断了卡死）
    -- 开局即静态悬停（TimeObject 的 rubble 路径），两团残块偏向两岸，中央留断口。
    local shardIndex=0
    o.startScatter = function(self, p, rng)
        shardIndex=shardIndex+1
        local s = self.size
        local cx = p.restPos.x + p.nx * s * 0.5
        local cz = p.restPos.z + p.nz * s * 0.5
        local outer = cz < -44
        -- 主残块降到不能跳回岸的低处；另两块高悬符脉保证安全路面可瞄准。
        local px = cx * .6 + rng:Range(-.8,.8)
        local pz = outer and rng:Range(-48.1,-47.2) or rng:Range(-40.8,-40.0)
        local half=Vector3(p.nx*s*.5,p.ny*s*.5,p.nz*s*.5)
        local radius=half:Length()
        local y=math.min(2.6-rng:Range(0,.6),3.3-radius)
        if shardIndex<=2 then
            px=shardIndex==1 and 3.6 or -3.6
            pz=shardIndex==1 and -47.1 or -41.0
            y=9.5+radius -- 底面高于跳跃可达高度；不能当修桥捷径
        end
        local rot = Quaternion(rng:Range(-12,12),rng:Range(-20,20),rng:Range(-12,12))
        return Vector3(px,y,pz)-rot*half,rot
    end
    local obj = Add(TimeObject.New(o))
    obj.title = "断桥"
    obj:On(function(self, ev)
        if ev == "restored" and not M.steps.bridge then
            M.steps.bridge = true
            Emit("bridge", {})
        end
    end)
end

-- ---------------------------------------------------------------- ③ 悬石阶梯
-- 位置：西南内环（塔台中心 (-36, -6)），一座 5m 高的方塔台，顶上放时之钥；塔壁光滑爬不上去。
-- 塔顶向东伸出一段断拱，拱端用锁链挂着巨石（中心离地约 5.8m）。
--
--   侧视（东 →）：
--        塔台顶 y=11 ┌────┐╭──断拱──╮ 锚点 y=14
--                    │    │         ║ 锁链
--                    │    │        (巨石) 中心 y≈11.8，底 y≈10.2
--                    │    │      ← 碎块下落途中冻结 → 形成 y 8~11 的跳台
--        地面 y=6  ──┴────┴──▆(矮墙 1.1m)──────────
-- 诺米跳高约 1.4m：地面 → 矮墙(7.1) → 冻结碎块(8~10) → 塔顶(11)。
-- 冻结 10 秒；失败了对巨石施放回溯，碎块飞回原位重新挂好。
M.TOWER = { x = -36.0, z = -6.0, h = 4.25 }
M.KEY_POS = Vector3(-36.0, Terrain.RING_Y + 4.25 + 0.9, -6.0)
local function BuildBoulderTower(world, scene)
    local tx, tz = M.TOWER.x, M.TOWER.z
    local base = Terrain.RING_Y
    local top = base + M.TOWER.h
    -- 塔台：4.5m 见方，塔壁光滑；顶部只有西、南两面护栏（东北角是上塔的入口）
    local b = Brush.New(world, { min = { tx - 3, base - 0.5, tz - 3 }, max = { tx + 3, top + 1.25, tz + 3 }, size = 0.25 })
    b:Shape(tx - 3, base - 0.5, tz - 3, tx + 3, top + 1.25, tz + 3, function(x, y, z)
        local dx, dz = abs(x - tx), abs(z - tz)
        local ly = y - base
        local e = (ly < 0.75) and 2.6 or 2.25
        if y > top then
            if y > top + 1.0 or dx > 2.25 or dz > 2.25 then return nil end
            local west, south = x < tx - 1.95, z < tz - 1.95
            if west or south then
                if ((x + z) * 2) % 2 < 1.0 or y > top + 0.75 then return P.GOLD end
            end
            return nil
        end
        if dx > e or dz > e then return nil end
        if y > top - 0.25 then return (dx < 0.9 and dz < 0.9) and P.RUNE_GOLD or P.GOLD_DARK end
        if (ly % 2.5) < 0.25 then return P.GOLD_DARK end
        return Build.MossyStone(x, y, z, base)
    end)
    M.towerVol = b:Finish({})
    -- 断梁：从塔北壁伸出，向东上扬，梁端挂锁链
    local ax, ay, az = tx + 5.0, top + 3.6, tz + 3.2
    local ab = Brush.New(world, { min = { tx - 1.5, top - 1.0, az - 0.8 }, max = { ax + 1.2, ay + 0.8, az + 0.8 }, size = 0.25 })
    ab:Shape(tx - 1.5, top - 1.0, az - 0.8, ax + 1.2, ay + 0.8, az + 0.8, function(x, y, z)
        local u = (x - (tx - 1.5)) / (ax + 1.0 - (tx - 1.5))
        if u < 0 or u > 1 then return nil end
        local cy = top - 0.6 + (ay - top + 0.6) * sin(u * pi * 0.5)
        if abs(y - cy) > 0.5 or abs(z - az) > 0.7 then return nil end
        if u > 0.97 - 0.05 * Noise.Value2(y * 3, z * 3, 3) then return nil end
        if abs(y - cy) > 0.3 and abs(z - az) < 0.25 then return P.GOLD end
        return Build.Marble(x, y, z)
    end)
    ab:Finish({})
    -- 矮墙残段（第一级台阶，巨石东侧）
    local sx0, sz0 = tx + 6.5, az + 0.3
    local sb = Brush.New(world, { min = { sx0, base - 0.25, sz0 }, max = { sx0 + 2.2, base + 1.3, sz0 + 2.2 }, size = 0.25 })
    sb:Shape(sx0, base - 0.25, sz0, sx0 + 2.2, base + 1.3, sz0 + 2.2, function(x, y, z)
        local top2 = base + 0.7 + 0.4 * Noise.Value2(x * 2, z * 2, 9)
        if y > top2 then return nil end
        return Build.MossyStone(x, y, z, base)
    end)
    sb:Finish({})
    -- 巨石（时之物件）：中心在梁端下方
    local bx, by, bz = ax, top + 0.6, az
    -- 锁链（视觉，无碰撞）
    local cb = Brush.New(world, { min = { ax - 0.375, by + 1.2, az - 0.375 }, max = { ax + 0.375, ay - 0.3, az + 0.375 }, size = 0.125 })
    cb:Shape(ax - 0.375, by + 1.2, az - 0.375, ax + 0.375, ay - 0.3, az + 0.375, function(x, y, z)
        local k = floor((y - by) / 0.375)
        local dx, dz = x - ax, z - az
        if k % 2 == 0 then
            if abs(dz) < 0.07 and abs(abs(dx) - 0.13) < 0.07 then return P.GOLD_DARK end
        else
            if abs(dx) < 0.07 and abs(abs(dz) - 0.13) < 0.07 then return P.GOLD_DARK end
        end
    end)
    M.chain = cb:Finish({ visual = true })
    local bb = Brush.New(world, { min = { bx - 2.0, by - 1.9, bz - 2.0 }, max = { bx + 2.0, by + 1.9, bz + 2.0 }, size = 0.25 })
    bb:Shape(bx - 2.0, by - 1.9, bz - 2.0, bx + 2.0, by + 1.9, bz + 2.0, function(x, y, z)
        local dx, dy, dz = x - bx, y - by, z - bz
        local d = sqrt(dx * dx + dy * dy * 1.15 + dz * dz)
        local n = Noise.Value3(x * 0.9, y * 0.9, z * 0.9, 41)
        if d > 1.35 + 0.35 * n then return nil end
        if abs(dy) < 0.13 then return P.GOLD end
        if Hash3(floor(x * 4), floor(y * 4), floor(z * 4)) < 0.05 then return P.RUNE_BLUE end
        return Build.Stone(x, y, z)
    end)
    local o = Harvest(world, bb)
    o.id = "boulder"
    o.world, o.scene = world, scene
    o.seed = 23
    o.freezeTime = 12.0
    o.pieceGravity = 0.35
    o.shatterPower = 0.35
    local obj = Add(TimeObject.New(o))
    obj.title = "悬石"
    -- 固定分块（格坐标，16x16x17）：三块大的台阶石（权重大）+ 若干小碎块
    obj.fixedSeeds = {
        { 4, 4, 4, 2.4 }, { 11, 4, 11, 2.4 }, { 8, 12, 8, 2.4 },
        { 12, 12, 3, 0.9 }, { 3, 12, 12, 0.9 }, { 13, 8, 13, 0.8 }, { 2, 8, 2, 0.8 },
    }
    -- 碎块飞行设计：最大的 3 块用 1.6s 飘到「台阶位」并悬停 2.5s，之后开始缓慢下坠（重力 0.35）。
    -- 玩家在这段时间里冻结，就得到一条通往塔顶的阶梯；错过了可以回溯重来。
    -- 台阶位（碎块中心）：碎块约 2m 高，中心 +1 ≈ 顶面。石顶 ≈ 7.0 → 8.1 → 9.2 → 塔顶 10.25（东侧无护栏）
    -- 由矮墙向西南绕到塔东壁，每级水平间距 ≈ 2.5m、高差 1m（诺米跳高约 1.3m）
    local slots = {
        Vector3(tx + 5.6, base + 0.1, tz + 1.6),  -- 顶 ≈ 7.0（从矮墙 6.9 走上去）
        Vector3(tx + 4.8, base + 1.2, tz - 1.0),  -- 顶 ≈ 8.1
        Vector3(tx + 3.6, base + 2.3, tz - 3.2),  -- 顶 ≈ 9.2
    }
    M.STAIR_SLOTS = slots
    local T_ARRIVE = 1.6
    obj.shatterAim = function(self, pieces, rng)
        local s = self.size
        local order = {}
        for i, p in ipairs(pieces) do order[i] = p end
        table.sort(order, function(a, b2) return #a.ids > #b2.ids end)
        for i, p in ipairs(order) do
            local v = p.vol
            if v ~= nil then
                local c = p.node.worldPosition + p.node.worldRotation * Vector3(p.nx * s * 0.5, p.ny * s * 0.5, p.nz * s * 0.5)
                local slot = slots[i]
                if slot ~= nil then
                    -- 「台阶石」：时间迟滞，先失重滑向台阶位并在那里悬停 ~2.5s，之后才开始下坠
                    p.aimSlot, p.aimT = slot, 0
                    p.aimFrom = c
                    v.gravityFactor = 0
                    v.linearDamping = 0
                    v.collisionMask = 0 -- 实时禁碰撞；SetCollidable 仅控制载入 adoption
                    local d = slot - c
                    v.linearVelocity = d * (1.0 / T_ARRIVE)
                    v.angularVelocity = Vector3(rng:Range(-0.3, 0.3), rng:Range(-0.6, 0.6), rng:Range(-0.3, 0.3))
                else
                    -- 小碎块：向外散开落到塔下
                    local away = Vector3(c.x - bx, 0, c.z - bz)
                    if away:LengthSquared() < 0.01 then away = Vector3(1, 0, 0) end
                    v.linearVelocity = away:Normalized() * rng:Range(1.0, 2.2) + Vector3(0, rng:Range(0.5, 1.5), 0)
                    v.angularVelocity = Vector3(rng:Range(-3, 3), rng:Range(-3, 3), rng:Range(-3, 3))
                end
            end
        end
    end
    obj:On(function(self, ev)
        if ev == "freeze" then
            for _, p in ipairs(self.pieces) do p.aimSlot = nil end
        elseif ev == "shatter" and M.chain ~= nil then
            M.chain:GetNode().enabled = false
        elseif ev == "restored" and M.chain ~= nil then
            M.chain:GetNode().enabled = true
        end
    end)
    M.boulder = obj
end

-- ---------------------------------------------------------------- ④ 时之碑
local function SteleVoxels(world, base, idx)
    -- 碑：1.4×5.2×0.9m 的石板，顶部尖拱，正面刻沙漏 / 时针符文（金 + 蓝），0.25m 体素
    local cx, cz = base.x, base.z
    local y0 = base.y + 1.25
    local a = pi / 4 + (idx - 1) * pi / 2
    -- 碑面朝龙庭：局部 -Z 指向中心
    local yaw = math.deg(math.atan(cos(a), sin(a))) + 180
    local b = Brush.New(world, { origin = Vector3(cx, y0, cz), yaw = yaw, min = { -0.875, 0, -0.5 }, max = { 0.875, 5.75, 0.5 }, size = 0.25 })
    b:Shape(-0.875, 0, -0.5, 0.875, 5.75, 0.5, function(x, y, z)
        local w = 0.875
        if y > 4.6 then w = 0.875 * (1 - (y - 4.6) / 1.15) end
        if abs(x) > w then return nil end
        local front = z < -0.25
        if front then
            -- 符文：中央沙漏轮廓 + 两侧刻度
            local yy = y - 2.6
            local hw = 0.15 + 0.32 * min(1, abs(yy) / 1.2)
            if abs(yy) < 1.3 and abs(abs(x) - hw) < 0.13 then return P.RUNE_GOLD end
            if abs(abs(yy) - 1.3) < 0.13 and abs(x) < 0.5 then return P.RUNE_GOLD end
            if abs(yy) < 0.4 and abs(x) < 0.13 then return P.RUNE_BLUE end
            -- 碑号（顶部 idx 个点）
            if y > 4.1 and y < 4.4 then
                local k = floor((x + 0.875) / 0.4375)
                if k >= 0 and k < idx and (x * 4) % 1.75 < 1.0 then return P.RUNE_BLUE end
            end
        end
        if abs(x) > w - 0.26 and y < 4.6 then return P.MARBLE_DARK end
        if y > 4.6 then return P.GOLD end
        return Build.Marble(x, y, z)
    end)
    return Harvest(world, b)
end

local function BuildSteles(world, scene)
    M.steles = {}
    for i, base in ipairs(Build.STELE_POS) do
        local o = SteleVoxels(world, base, i)
        o.id = "stele" .. i
        o.world, o.scene = world, scene
        o.seed = 40 + i
        o.shattered = true
        o.shatterLevel = 2
        o.canShatter = false
        o.canRewind = false -- 时之钥解锁
        local cx, cz = base.x, base.z
        o.startScatter = function(self, p, rng)
            local s = self.size
            -- 碑倒向外侧，碎块散在底座外 1–5m 的扇形里
            local out = Vector3(cx, 0, cz):Normalized()
            local side = Vector3(-out.z, 0, out.x)
            local hgt = (p.restPos.y - base.y) / 5.5
            local d = 1.8 + hgt * 3.2 + rng:Range(-0.6, 0.6)
            local px = cx + out.x * d + side.x * rng:Range(-1.6, 1.6)
            local pz = cz + out.z * d + side.z * rng:Range(-1.6, 1.6)
            if not Terrain.HasGround(px,pz,1) then px,pz=cx,cz end
            local gy = math.max(Terrain.HeightAt(px, pz), Terrain.CollideHeight(px, pz))
            local rot = Quaternion(rng:Range(-80, 80), rng:Range(0, 360), rng:Range(-30, 30))
            return Vector3(px - p.nx * s * 0.5, gy + 0.02, pz - p.nz * s * 0.5), rot
        end
        local obj = Add(TimeObject.New(o))
        obj.title = "时之碑 · " .. ({ "一", "二", "三", "四" })[i]
        obj.lockedHint = "碑身被封印——需要先取得「时之钥」"
        obj:On(function(self, ev)
            if ev == "restored" then
                M.steps["stele" .. i] = true
                local n = 0
                for k = 1, 4 do if M.steps["stele" .. k] then n = n + 1 end end
                Emit("stele", { index = i, count = n })
                if n == 4 and not M.steps.awake then
                    M.steps.awake = true
                    Emit("awake", {})
                end
            end
        end)
        M.steles[i] = obj
    end
end

-- 练习用：龙庭入口两侧的两只完整石瓮（时之物件，可随便碎 / 冻 / 回溯）
local function BuildUrns(world, scene)
    for i, sx in ipairs({ -5.5, 5.5 }) do
        local cx, cz = sx, -Terrain.STAIR_END - 2.0
        local base = Terrain.RING_Y
        local b = Brush.New(world, { min = { cx - 1.0, base, cz - 1.0 }, max = { cx + 1.0, base + 2.4, cz + 1.0 }, size = 0.125 })
        b:Shape(cx - 1.0, base, cz - 1.0, cx + 1.0, base + 2.4, cz + 1.0, function(x, y, z)
            local ly = y - base
            local dx, dz = x - cx, z - cz
            local d = sqrt(dx * dx + dz * dz)
            local prof
            if ly < 0.25 then prof = 0.55
            elseif ly < 0.4 then prof = 0.42
            elseif ly < 1.8 then local t = (ly - 0.4) / 1.4; prof = 0.5 + 0.38 * sin(t * pi)
            elseif ly < 2.1 then prof = 0.34
            else prof = 0.48 end
            if d > prof then return nil end
            if ly > 0.4 and d < prof - 0.2 and ly < 2.25 then return nil end -- 空心
            if abs(ly - 1.1) < 0.07 or ly > 2.2 then return P.GOLD end
            if abs(ly - 1.35) < 0.09 and Hash3(floor(math.atan(dz, dx) * 4), 1, i) < 0.5 then return P.RUNE_BLUE end
            return Build.Marble(x, y, z)
        end)
        local o = Harvest(world, b)
        o.id = "urn" .. i
        o.world, o.scene = world, scene
        o.seed = 70 + i
        local obj = Add(TimeObject.New(o))
        obj.title = "时之瓮"
    end
end

-- ---------------------------------------------------------------- 时之钥（拾取物）
local function BuildKey(scene)
    local node = scene:CreateChild("TimeKey")
    node.position = M.KEY_POS
    local sm = node:CreateComponent("StaticModel")
    sm:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.8, 0.35, 1)))
    sm:SetMaterial(mat)
    node.scale = Vector3(0.35, 0.35, 0.35)
    local inner = node:CreateChild("Core")
    local sm2 = inner:CreateComponent("StaticModel")
    sm2:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local mat2 = Material:new()
    mat2:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat2:SetShaderParameter("MatDiffColor", Variant(Color(0.35, 0.6, 1.0, 1)))
    sm2:SetMaterial(mat2)
    inner.scale = Vector3(1.5, 0.5, 0.5)
    local light = node:CreateComponent("Light")
    light.lightType = LIGHT_POINT
    light.color = Color(1.0, 0.78, 0.4)
    light.range = 6
    light.brightness = 1.5
    M.keyNode = node
end

function M.UpdateKey(t, playerPos)
    local n = M.keyNode
    if n == nil or M.steps.key then return end
    n.position = M.KEY_POS + Vector3(0, 0.25 * sin(t * 2.2), 0)
    n.rotation = Quaternion(t * 60, Vector3.UP) * Quaternion(35, Vector3.RIGHT)
    if playerPos ~= nil and (playerPos + Vector3(0, 0.8, 0) - n.position):Length() < 1.6 then
        M.steps.key = true
        n.enabled = false
        for i = 1, 4 do M.steles[i].canRewind = true end
        Emit("key", {})
    end
end

-- ---------------------------------------------------------------- 封门乱石进度
local GATE_CHECK_DT = 0.25
local GATE_RESCAN_DT = 1.0 -- 无伤害时低频复查，兼容手改 grid 与正在移动的残骸
local GATE_HEIGHTS, GATE_OFFSETS = { 0.4, 1.0, 1.6 }, { -0.5, 0, 0.5 }
local gateClock, gateNextCheck, gateNextRescan = 0, 0, 0
local gateDirty = true

local function InvalidateGate(volume, position)
    if M.steps.gate then return end
    if volume == M.gateRubble or (position ~= nil and abs(position.x) < 4.0 and abs(position.z + Terrain.WALL_R) < 4.0) then
        gateDirty = true
    end
end

---@param eventType string
---@param eventData VoxelDamagedEventData
local function GateDamaged(eventType, eventData)
    InvalidateGate(eventData:GetPtr("Volume"), eventData:GetVector3("Position"))
end

---@param eventType string
---@param eventData VoxelSeveredEventData
local function GateSevered(eventType, eventData)
    if eventData:GetPtr("Volume") == M.gateRubble then gateDirty = true end
end

function M.CheckGate()
    if M.steps.gate or M.gateRubble == nil or gateClock < gateNextCheck then return end
    if not gateDirty and gateClock < gateNextRescan then return end
    gateNextCheck = gateClock + GATE_CHECK_DT
    gateNextRescan = gateClock + GATE_RESCAN_DT
    gateDirty = false
    local now = M.gateRubble:GetSolidCount()
    if now >= M.gateRubbleSolid0 * 0.78 then return end
    -- 保持原低占用率兜底规则，避免已足够破坏后还做九次射线。
    if now < M.gateRubbleSolid0 * 0.45 then
        M.steps.gate = true
        Emit("gate", {})
        return
    end
    -- 南 → 北 6m，中心宽 1.4m/高 1.7m 的通道；任一残骸堵塞立即退出。
    -- 命中的 severed 残片也算障碍，不只比较原 gate volume。
    for _, h in ipairs(GATE_HEIGHTS) do
        for _, ox in ipairs(GATE_OFFSETS) do
            local hit = M.world:RaycastSingle(Ray(Vector3(ox, Terrain.RING_Y + h, -Terrain.WALL_R - 3.0), Vector3.FORWARD), 6.0)
            if hit.hit then return end
        end
    end
    M.steps.gate = true
    Emit("gate", {})
end

---@param world VoxelPhysicsWorld
function M.Build(world, scene)
    local t0 = os.clock()
    M.world = world
    gateClock, gateNextCheck, gateNextRescan, gateDirty = 0, 0, 0, true
    SubscribeToEvent(world, "VoxelDamaged", GateDamaged)
    SubscribeToEvent(world, "VoxelSevered", GateSevered)
    BuildGateRubble(world)
    BuildBridge(world, scene)
    BuildBoulderTower(world, scene)
    BuildSteles(world, scene)
    BuildUrns(world, scene)
    BuildKey(scene)
    print(string.format("RuinsPuzzles: built %d time objects in %.2fs", #M.list, os.clock() - t0))
end

-- 悬石的「台阶石」：到位后悬停 HOVER 秒再恢复重力（给玩家冻结的时间窗）
local HOVER = 2.5
local function UpdateStairStones(dt)
    local o = M.boulder
    if o == nil or o.state ~= "SHATTERED" then return end
    local sz = o.size
    for _, p in ipairs(o.pieces) do
        if p.aimSlot ~= nil and p.vol ~= nil and not p.frozen then
            p.aimT = p.aimT + dt
            local v = p.vol
            if p.aimT < 1.6 + HOVER then
                -- 速度伺服：沿弧线（先上抛再落位）把碎块中心拉向台阶位
                local c = p.node.worldPosition + p.node.worldRotation * Vector3(p.nx * sz * 0.5, p.ny * sz * 0.5, p.nz * sz * 0.5)
                local u = math.min(1.0, p.aimT / 1.6)
                local w = u * u * (3 - 2 * u)
                local goal = p.aimFrom:Lerp(p.aimSlot, w) + Vector3(0, math.sin(u * pi) * 1.2, 0)
                local want = (goal - c) * 8.0
                if want:Length() > 9.0 then want = want:Normalized() * 9.0 end
                v.linearVelocity = want
                v.angularVelocity = v.angularVelocity * 0.92
                v:Activate()
                if u >= 1.0 and not p.aimLanded then
                    p.aimLanded = true
                    v.collisionMask = 0xffffffff
                end
            else
                v.gravityFactor = o.pieceGravity
                v.linearDamping = 0.05
                v.collisionMask = 0xffffffff
                v:Activate()
                p.aimSlot = nil
            end
        end
    end
end

function M.Update(dt)
    gateClock = gateClock + dt
    UpdateStairStones(dt)
    for _, o in ipairs(M.list) do o:Update(dt) end
end

-- 世界点附近的时之物件（任一碎块中心或完整物件包围球在 radius 内）
---@param pos Vector3
---@param radius number
function M.FindNear(pos, radius)
    local best, bd = nil, radius
    for _, o in ipairs(M.list) do
        if o:IsWhole() then
            local d = (o.center - pos):Length() - o.radius
            if d < bd then best, bd = o, d end
        else
            for _, c in ipairs(o:PieceCenters()) do
                local d = (c - pos):Length()
                if d < bd then best, bd = o, d end
            end
        end
    end
    return best
end

-- 体积 → 所属时之物件
---@param vol VoxelVolume
function M.FindByVolume(vol)
    return TimeObject.FindByVolume(vol)
end

return M
