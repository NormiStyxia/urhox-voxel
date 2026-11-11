-- ====================================================================
-- RuinsPuzzles.lua — 解谜流程与时之物件的摆放
--
-- 路线（玩家从南边出生点 (0, 6, -64) 出发）：
--
--   ① 封门乱石（南城门 z≈-51）：一堆 0.25m 体素的乱石把门洞堵死。
--      → 学会「碎时」：乱石是普通可破坏体素，诺米的碎时直接打碎（引擎弹坑 + 崩落碎块）。
--   ② 断桥（南侧峡谷 z∈[-48.5, -39.5]）：石桥早已碎落在谷底与两岸。
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
    local o = { voxels = vox, dims = { b.nx, b.ny, b.nz }, origin = b.origin + b.rot * Vector3(b.lmin[1], b.lmin[2], b.lmin[3]), yaw = b.yaw, size = b.s }
    world:RemoveVolume(b.volume)
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
        return Pal.RUBBLES[(h < 0.4) and 1 or ((h < 0.8) and 2 or 3)]
    end)
    local v = b:Finish({ destructible = true })
    M.gateRubble = v
    M.gateRubbleSolid0 = v and v:GetSolidCount() or 0
    print("RuinsPuzzles: gate rubble voxels " .. M.gateRubbleSolid0)
end

-- ---------------------------------------------------------------- ② 断桥
local function BridgeVoxels(world)
    -- 桥：沿 z 跨越峡谷，z ∈ [-49.5, -38.5]，宽 4.5m（x ∈ [-2.25, 2.25]），桥面 y=6，
    -- 下方一道浅拱，两侧栏杆 + 金饰；0.25m 体素
    local z0, z1 = -49.75, -38.25
    local b = Brush.New(world, { min = { -2.5, Terrain.RING_Y - 2.5, z0 }, max = { 2.5, Terrain.RING_Y + 1.25, z1 }, size = 0.25 })
    local zc, half = (z0 + z1) * 0.5, (z1 - z0) * 0.5
    b:Shape(-2.5, Terrain.RING_Y - 2.5, z0, 2.5, Terrain.RING_Y + 1.25, z1, function(x, y, z)
        local u = (z - zc) / half
        local ly = y - Terrain.RING_Y
        -- 拱腹：桥面下方的弧，中间最薄 0.75m、两端 2.5m
        local bottom = -0.75 - 1.75 * u * u
        if abs(x) > 2.25 then return nil end
        if ly < 0 then
            if ly < bottom then return nil end
            if abs(x) > 2.0 and abs(ly - bottom) < 0.3 then return P.GOLD_DARK end
            return Build.Marble(x, y, z)
        end
        -- 栏杆
        if abs(x) > 1.8 then
            if ly < 0.25 then return Build.Marble(x, y, z) end
            if ly < 1.0 then
                if (z * 2) % 1.5 < 0.5 then return Build.Marble(x, y, z) end
                return nil
            end
            return P.GOLD
        end
        return nil
    end)
    -- 桥面中线的蓝色符文（回溯后会亮着）
    b:Shape(-0.5, Terrain.RING_Y - 0.25, z0 + 1, 0.5, Terrain.RING_Y, z1 - 1, function(x, y, z)
        if abs(x) < 0.15 and (z % 1.0) < 0.5 then return P.RUNE_BLUE end
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
    -- 开局散落：碎块落在谷底、谷壁台阶上（按块在桥上的位置分布）
    o.startScatter = function(self, p, rng)
        local s = self.size
        local cx = p.restPos.x + p.nx * s * 0.5
        local cz = p.restPos.z + p.nz * s * 0.5
        local px = cx + rng:Range(-3.5, 3.5)
        local pz = cz + rng:Range(-1.5, 1.5)
        -- 靠两岸的碎块挂在岸边台阶上，中段落到谷底
        local edgeK = abs(cz - (-44.0)) / 5.5
        local gy = Terrain.HeightAt(px, pz)
        local y = gy + 0.05
        if edgeK > 0.75 then y = max(gy, Terrain.RING_Y - 5.5) + 0.05 end
        local rot = Quaternion(rng:Range(-35, 35), rng:Range(0, 360), rng:Range(-35, 35))
        return Vector3(px - p.nx * s * 0.5, y, pz - p.nz * s * 0.5), rot
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
-- 位置：西侧内环（x≈-31, z≈-3），一座高 13m 的断塔台（柱廊外），顶上放时之钥。
-- 巨石挂在旁边的断拱下（y≈14），下方是空地；打碎后碎块下落，冻结它们当跳台。
M.KEY_POS = Vector3(-33.0, Terrain.RING_Y + 13.6, -3.0)
local function BuildBoulderTower(world, scene)
    local tx, tz = -33.0, -3.0
    local base = Terrain.RING_Y
    local top = base + 13.0
    -- 塔台：方形石台 4.5×4.5，四周光滑无法攀爬；顶部金色平台
    local b = Brush.New(world, { min = { tx - 3, base - 0.5, tz - 3 }, max = { tx + 3, top + 1.5, tz + 3 }, size = 0.25 })
    b:Shape(tx - 3, base - 0.5, tz - 3, tx + 3, top + 1.5, tz + 3, function(x, y, z)
        local dx, dz = abs(x - tx), abs(z - tz)
        local ly = y - base
        local e = (ly < 1.0) and 2.6 or 2.25
        if y > top then
            -- 顶部护栏（只有三面，朝东开口，让跳台方向进入）
            if y > top + 1.0 then return nil end
            if dx > 2.0 or dz > 2.0 then
                if x > tx + 1.9 then return nil end
                if (x + z) % 1.0 < 0.5 then return P.GOLD end
                return nil
            end
            return nil
        end
        if dx > e or dz > e then return nil end
        if y > top - 0.25 then return P.GOLD_DARK end
        if (ly % 3.0) < 0.25 then return P.GOLD_DARK end
        return Build.MossyStone(x, y, z, base)
    end)
    Keep = nil
    local v = b:Finish({})
    M.towerVol = v
    -- 断拱：从塔顶向东伸出的一段拱（挂巨石的锚点在拱端 x=tx+9, y=top+3）
    local ab = Brush.New(world, { min = { tx, top - 1, tz - 1.0 }, max = { tx + 11, top + 4.5, tz + 1.0 }, size = 0.25 })
    ab:Shape(tx, top - 1, tz - 1.0, tx + 11, top + 4.5, tz + 1.0, function(x, y, z)
        local u = (x - tx) / 10.0
        if u < 0 or u > 1 then return nil end
        local cy = top + 0.5 + 3.0 * sin(u * pi * 0.6)
        if abs(y - cy) > 0.55 or abs(z - tz) > 0.8 then return nil end
        if u > 0.92 - 0.06 * Noise.Value2(y * 3, z * 3, 3) then return nil end
        if abs(y - cy) > 0.35 and abs(z - tz) < 0.25 then return P.GOLD end
        return Build.Marble(x, y, z)
    end)
    ab:Finish({})
    -- 锁链（视觉，静态无碰撞）：锚点到巨石顶
    local anchor = Vector3(tx + 8.6, top + 3.0, tz)
    local cb = Brush.New(world, { min = { anchor.x - 0.4, top - 1.5, tz - 0.4 }, max = { anchor.x + 0.4, anchor.y + 0.2, tz + 0.4 }, size = 0.125 })
    cb:Shape(anchor.x - 0.4, top - 1.5, tz - 0.4, anchor.x + 0.4, anchor.y, tz + 0.4, function(x, y, z)
        local k = floor((y - top) / 0.375)
        local dx, dz = x - anchor.x, z - tz
        if k % 2 == 0 then
            if abs(dz) < 0.07 and abs(abs(dx) - 0.14) < 0.07 then return P.GOLD_DARK end
        else
            if abs(dx) < 0.07 and abs(abs(dz) - 0.14) < 0.07 then return P.GOLD_DARK end
        end
    end)
    M.chain = cb:Finish({ visual = true })
    -- 巨石：直径 ~3.4m 的不规则岩块，挂在锚点下（底部 y≈top-4.8），时之物件（0.25m 体素）
    local bx, by, bz = anchor.x, top - 3.2, tz
    local bb = Brush.New(world, { min = { bx - 2.0, by - 1.9, bz - 2.0 }, max = { bx + 2.0, by + 1.9, bz + 2.0 }, size = 0.25 })
    bb:Shape(bx - 2.0, by - 1.9, bz - 2.0, bx + 2.0, by + 1.9, bz + 2.0, function(x, y, z)
        local dx, dy, dz = x - bx, y - by, z - bz
        local d = sqrt(dx * dx + dy * dy * 1.15 + dz * dz)
        local n = Noise.Value3(x * 0.9, y * 0.9, z * 0.9, 41)
        if d > 1.5 + 0.35 * n then return nil end
        -- 金色箍带 + 蓝色时纹
        if abs(dy) < 0.13 then return P.GOLD end
        if Hash3(floor(x * 4), floor(y * 4), floor(z * 4)) < 0.05 then return P.RUNE_BLUE end
        return Build.Stone(x, y, z)
    end)
    local o = Harvest(world, bb)
    o.id = "boulder"
    o.world, o.scene = world, scene
    o.seed = 23
    local obj = Add(TimeObject.New(o))
    obj.title = "悬石"
    obj.hangY = by
    obj:On(function(self, ev)
        if ev == "shatter" and M.chain ~= nil then
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
            local gy = Terrain.HeightAt(px, pz)
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
function M.CheckGate()
    if M.steps.gate or M.gateRubble == nil then return end
    local now = M.gateRubble:GetSolidCount()
    -- 门洞中心一条 1.4m 宽的通道：射线检查（诺米体高 1.7，用 3 条水平射线）
    if now < M.gateRubbleSolid0 * 0.78 then
        local world = M.world
        local clear = true
        for _, h in ipairs({ 0.4, 1.0, 1.6 }) do
            for _, ox in ipairs({ -0.5, 0, 0.5 }) do
                local hit = world:RaycastSingle(Ray(Vector3(ox, Terrain.RING_Y + h, -Terrain.WALL_R - 3.0), Vector3(0, 0, 1)), 6.0)
                if hit.hit and hit.volume == M.gateRubble then clear = false end
            end
        end
        if clear then
            M.steps.gate = true
            Emit("gate", {})
        end
    end
end

---@param world VoxelPhysicsWorld
function M.Build(world, scene)
    local t0 = os.clock()
    M.world = world
    BuildGateRubble(world)
    BuildBridge(world, scene)
    BuildBoulderTower(world, scene)
    BuildSteles(world, scene)
    BuildUrns(world, scene)
    BuildKey(scene)
    print(string.format("RuinsPuzzles: built %d time objects in %.2fs", #M.list, os.clock() - t0))
end

function M.Update(dt)
    for _, o in ipairs(M.list) do o:Update(dt) end
end

-- 体积 → 所属时之物件
---@param vol VoxelVolume
function M.FindByVolume(vol)
    if vol == nil then return nil end
    for _, o in ipairs(M.list) do
        if o:Owns(vol) then return o end
    end
    return nil
end

return M
