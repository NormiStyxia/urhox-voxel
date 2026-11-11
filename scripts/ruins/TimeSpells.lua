-- ====================================================================
-- TimeSpells.lua — 诺米的时间系法术（数据驱动，留好魔法构筑的扩展口）
--
-- 法术定义表 SPELLS：每个法术 = { id, name, key, color, cooldown, range, cast = function(ctx, aim) }
--   ctx  = 施法上下文（world、puzzles、fx、施法者位置 / 朝向）
--   aim  = 瞄准结果 { hit, pos, normal, volume, object(时之物件或 nil), dir }
-- 以后做「魔法构筑」：给法术加 modifiers（范围 / 强度 / 连锁 / 持续），或把多个法术串成组合，
-- 只需要往表里加条目 / 在 Cast 里套一层 modifier 处理，不用改 TimeObject。
--
-- 三个基础法术：
--   碎时 Shatter（左键 / 1）：时之物件 → 碎成大小不一的块（按住蓄力 0.6s → 碎成最小单元）；
--        普通可破坏体素（封门乱石等）→ 引擎弹坑 + 崩落碎块。
--   冻结 Freeze（右键 / 2）：范围 3.5m 内正在运动的时之碎块定格 10 秒，可当平台踩。
--   回溯 Rewind（R / 3）：被瞄准的时之物件（或它的任一碎块）沿轨迹倒放、重组为完整物件。
-- 配色：蓝为主（0.22, 0.46, 1.0），偏蓝紫（0.42, 0.34, 1.0），金色点缀（1.0, 0.74, 0.30）。
-- ====================================================================

local VoxelFX = require("dragon.VoxelFX")

local M = {}

M.BLUE = Color(0.25, 0.5, 1.0)
M.VIOLET = Color(0.45, 0.38, 1.0)
M.GOLD = Color(1.0, 0.76, 0.32)
M.WHITE = Color(0.9, 0.95, 1.0)

local function Clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
local function Rand(a, b) return a + (b - a) * math.random() end

-- ---------------------------------------------------------------- 法术定义
M.SPELLS = {
    {
        id = "shatter", name = "碎时", key = KEY_1, cooldown = 0.35, range = 40.0,
        color = M.GOLD, icon = "✦",
        desc = "左键：打碎时之物件 / 碎石（按住蓄力碎成最小单元）",
        cast = function(ctx, aim, charge)
            if not aim.hit then return false, "没有目标" end
            local obj = aim.object
            local level = (charge >= 1.0) and 3 or ((charge >= 0.5) and 2 or 1)
            if obj ~= nil then
                if not obj.canShatter then return false, obj.title .. "无法被打碎" end
                local ok = obj:Shatter({ level = level, point = aim.pos, dir = aim.dir, power = 1.0 + 0.6 * charge })
                if ok then ctx.fx:Burst(aim.pos, "shatter", 1.0 + charge) end
                return ok, ok and nil or "它已经碎了"
            end
            -- 普通可破坏体素：引擎伤害（power 3：碎石硬度 1 能碎，古石硬度 4 打不动）
            local vol = aim.volume
            if vol ~= nil and vol.destructible then
                local r = 0.9 + 0.7 * charge
                local removed = ctx.world:ApplyDamageAtWorldPoint(aim.pos, r, 3.0)
                ctx.world:ApplyRadialImpulse(aim.pos, r * 1.8, 1200.0 * (1 + charge))
                ctx.fx:Burst(aim.pos, "shatter", 0.8 + charge)
                return removed > 0, (removed > 0) and nil or "太坚硬了"
            end
            ctx.fx:Burst(aim.pos, "fizzle", 0.6)
            return false, "古石太坚硬，只有带时之印记的物件和碎石能被打碎"
        end,
    },
    {
        id = "freeze", name = "冻结", key = KEY_2, cooldown = 0.6, range = 40.0,
        color = M.BLUE, icon = "❄",
        desc = "右键：定格范围内的时之碎块 10 秒（可以踩上去）",
        cast = function(ctx, aim)
            local center = aim.hit and aim.pos or aim.far
            local n = 0
            for _, obj in ipairs(ctx.puzzles.list) do
                if obj.state == "SHATTERED" then
                    local near = false
                    for _, c in ipairs(obj:PieceCenters()) do
                        if (c - center):Length() < 4.0 then near = true; break end
                    end
                    if near or aim.object == obj then
                        if obj:Freeze(obj.freezeTime or 10.0) then n = n + 1 end
                    end
                end
            end
            ctx.fx:Burst(center, "freeze", 1.0)
            if n == 0 then return true, "附近没有正在坠落的时之碎块" end
            return true, nil
        end,
    },
    {
        id = "rewind", name = "回溯", key = KEY_3, cooldown = 0.8, range = 60.0,
        color = M.VIOLET, icon = "⟲",
        desc = "R：让时之物件沿时间倒流，重组为原样",
        cast = function(ctx, aim)
            local obj = aim.object
            if obj == nil and aim.hit then obj = ctx.puzzles.FindNear(aim.pos, 2.5) end
            if obj == nil then
                ctx.fx:Burst(aim.hit and aim.pos or aim.far, "fizzle", 0.6)
                return false, "回溯只对带「时之印记」的物件生效"
            end
            if not obj.canRewind then
                ctx.fx:Burst(aim.pos or obj.center, "fizzle", 0.8)
                return false, obj.lockedHint or "它无法回溯"
            end
            if obj:IsWhole() then return false, obj.title .. "完好无损" end
            if obj.state == "REWIND" then return false, nil end
            local ok = obj:Rewind()
            if ok then ctx.fx:StartRewind(obj) end
            return ok, nil
        end,
    },
}
M.BY_ID = {}
for _, s in ipairs(M.SPELLS) do M.BY_ID[s.id] = s end

-- ---------------------------------------------------------------- 施法器
---@class TimeCaster
local C = {}
C.__index = C

---@param ctx table { world, puzzles, scene, fx }
function M.NewCaster(ctx)
    local self = setmetatable({}, C)
    self.ctx = ctx
    self.cool = {}
    self.charge = 0
    self.charging = false
    self.message = nil
    self.messageT = 0
    self.lastCast = nil
    self.castAnim = 0
    return self
end

function C:Ready(id) return (self.cool[id] or 0) <= 0 end

function C:Cast(id, aim)
    local sp = M.BY_ID[id]
    if sp == nil or not self:Ready(id) then return false end
    local ok, msg = sp.cast(self.ctx, aim, self.charge)
    self.cool[id] = sp.cooldown
    self.lastCast = id
    self.castAnim = 0.35
    if msg ~= nil then self:Say(msg) end
    -- 施法光束（手 → 目标）
    self.ctx.fx:Beam(self.ctx.handPos(), aim.hit and aim.pos or aim.far, sp.color)
    print(string.format("TimeSpells: cast %s ok=%s msg=%s", id, tostring(ok), tostring(msg)))
    return ok
end

function C:Say(msg, t)
    self.message = msg
    self.messageT = t or 2.5
end

function C:Update(dt)
    for k, v in pairs(self.cool) do self.cool[k] = math.max(0, v - dt) end
    self.messageT = math.max(0, self.messageT - dt)
    if self.messageT <= 0 then self.message = nil end
    self.castAnim = math.max(0, self.castAnim - dt)
    if self.charging then self.charge = math.min(1.0, self.charge + dt / 0.6) end
end

-- ---------------------------------------------------------------- 法术特效
-- 全部基于 VoxelFX：像素公告板粒子（Motes）+ 小立方体碎块（Debris）+ 光束（拉长的立方体）
---@class TimeFX
local F = {}
F.__index = F

---@param scene Scene
function M.NewFX(scene)
    local self = setmetatable({}, F)
    local root = scene:CreateChild("TimeFX")
    self.root = root
    self.motesB = VoxelFX.Motes(root, "MotesBlue", 900, "square", true)
    self.motesG = VoxelFX.Motes(root, "MotesGold", 500, "star", true)
    self.debris = VoxelFX.Debris(root, 80)
    self.beams = {}
    for i = 1, 6 do
        local n = root:CreateChild("Beam" .. i)
        local sm = n:CreateComponent("StaticModel")
        sm:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        sm.castShadows = false
        n.enabled = false
        self.beams[i] = { node = n, sm = sm, age = 1, life = 0.25 }
    end
    self.rewinds = {}
    -- 手上的法术光（跟随施法者的手）
    local hand = root:CreateChild("HandLight")
    local l = hand:CreateComponent("Light")
    l.lightType = LIGHT_POINT
    l.range = 4.0
    l.brightness = 0.0
    l.color = M.BLUE
    self.handLight = hand
    self.handL = l
    self.handGlow = 0
    return self
end

-- 爆点：kind = shatter / freeze / fizzle / restore
function F:Burst(pos, kind, k)
    k = k or 1
    if kind == "shatter" then
        for i = 1, math.floor(40 * k) do
            local d = Vector3(Rand(-1, 1), Rand(-0.3, 1), Rand(-1, 1)):Normalized()
            self.motesG:Spawn({ pos = pos, vel = d * Rand(3, 8) * k, life = Rand(0.4, 0.9), size = Rand(0.12, 0.24),
                colors = { Color(1, 0.95, 0.75, 1), M.GOLD, Color(0.95, 0.6, 0.2, 1) }, grav = 6, drag = 3 })
        end
        for i = 1, math.floor(30 * k) do
            local d = Vector3(Rand(-1, 1), Rand(-1, 1), Rand(-1, 1)):Normalized()
            self.motesB:Spawn({ pos = pos + d * 0.3, vel = d * Rand(1.5, 4), life = Rand(0.5, 1.1), size = Rand(0.08, 0.16),
                colors = { M.WHITE, M.BLUE, M.VIOLET }, drag = 2.5 })
        end
        -- 时之裂纹：扩散的金色环
        for i = 0, 23 do
            local a = i / 24 * math.pi * 2
            local d = Vector3(math.cos(a), 0, math.sin(a))
            self.motesG:Spawn({ pos = pos, vel = d * 6.0 * k, life = 0.35, size = 0.14, colors = { M.GOLD, Color(1, 0.9, 0.6, 1) }, drag = 4 })
        end
    elseif kind == "freeze" then
        -- 蓝色冰环（3 层）+ 冰晶屑缓慢下沉
        for ring = 1, 3 do
            for i = 0, 31 do
                local a = i / 32 * math.pi * 2
                local d = Vector3(math.cos(a), (ring - 2) * 0.35, math.sin(a)):Normalized()
                self.motesB:Spawn({ pos = pos, vel = d * (2.5 + ring * 1.3), life = 0.7, size = 0.16,
                    colors = { M.WHITE, M.BLUE, M.VIOLET, M.BLUE }, drag = 3.5 })
            end
        end
        for i = 1, 50 do
            local p = pos + Vector3(Rand(-3.5, 3.5), Rand(-1.5, 2.5), Rand(-3.5, 3.5))
            self.motesB:Spawn({ pos = p, vel = Vector3(0, -0.3, 0), life = Rand(1.0, 2.0), size = Rand(0.06, 0.12),
                colors = { M.WHITE, M.BLUE, M.VIOLET } })
        end
    elseif kind == "fizzle" then
        for i = 1, 14 do
            local d = Vector3(Rand(-1, 1), Rand(0, 1), Rand(-1, 1)):Normalized()
            self.motesB:Spawn({ pos = pos, vel = d * Rand(1, 2.5), life = Rand(0.3, 0.6), size = 0.08,
                colors = { M.VIOLET, Color(0.3, 0.3, 0.5, 1) }, drag = 3 })
        end
    elseif kind == "restore" then
        -- 复原完成：金色闪光 + 向上飘的蓝色光点
        for i = 1, math.floor(60 * k) do
            local d = Vector3(Rand(-1, 1), Rand(-0.2, 1), Rand(-1, 1)):Normalized()
            self.motesG:Spawn({ pos = pos + d * Rand(0.2, 1.5 * k), vel = d * Rand(1, 3) + Vector3(0, 1.5, 0), life = Rand(0.6, 1.4),
                size = Rand(0.1, 0.22), colors = { Color(1, 0.97, 0.85, 1), M.GOLD, M.BLUE }, drag = 1.5 })
        end
        for i = 1, math.floor(50 * k) do
            local p = pos + Vector3(Rand(-2, 2), Rand(-1, 1), Rand(-2, 2)) * k
            self.motesB:Spawn({ pos = p, vel = Vector3(0, Rand(1.5, 3.5), 0), life = Rand(1.0, 2.0), size = Rand(0.06, 0.12),
                colors = { M.WHITE, M.BLUE, M.VIOLET } })
        end
    end
end

-- 施法光束：一条拉长的发光立方体，0.25 秒淡出
function F:Beam(from, to, color)
    local b = nil
    for _, it in ipairs(self.beams) do
        if it.age >= it.life then b = it; break end
    end
    if b == nil then return end
    local d = to - from
    local len = d:Length()
    if len < 0.1 then return end
    b.from, b.to, b.color, b.age, b.len = from, to, color, 0, len
    b.node.enabled = true
    b.node.position = (from + to) * 0.5
    b.node.rotation = Quaternion(Vector3.FORWARD, d * (1.0 / len))
    b.sm:SetMaterial(VoxelFX.CubeMaterial(color, 3.0))
    -- 沿光束的像素点
    local n = math.min(40, math.floor(len * 2))
    for i = 1, n do
        local p = from + d * (i / n)
        self.motesB:Spawn({ pos = p + Vector3(Rand(-0.1, 0.1), Rand(-0.1, 0.1), Rand(-0.1, 0.1)), vel = Vector3(0, 0.4, 0),
            life = Rand(0.2, 0.45), size = Rand(0.06, 0.12), colors = { M.WHITE, color } })
    end
end

-- 回溯特效：碎块回飞期间沿每块撒蓝紫光点，物件中心一个旋转的金色时钟环
function F:StartRewind(obj)
    self.rewinds[#self.rewinds + 1] = { obj = obj, t = 0 }
end

function F:Update(dt, handPos, glowColor, glow)
    self.motesB:Update(dt)
    self.motesG:Update(dt)
    self.debris:Update(dt)
    for _, b in ipairs(self.beams) do
        if b.age < b.life then
            b.age = b.age + dt
            local k = 1 - b.age / b.life
            local w = 0.06 + 0.1 * k
            b.node.scale = Vector3(w, w, b.len)
            if b.age >= b.life then b.node.enabled = false end
        end
    end
    local keep = {}
    for _, r in ipairs(self.rewinds) do
        r.t = r.t + dt
        local obj = r.obj
        if obj.state == "REWIND" then
            local cs = obj:PieceCenters(40)
            for i = 1, #cs do
                if math.random() < 0.5 then
                    self.motesB:Spawn({ pos = cs[i] + Vector3(Rand(-0.3, 0.3), Rand(-0.3, 0.3), Rand(-0.3, 0.3)), vel = Vector3(0, 0, 0),
                        life = Rand(0.3, 0.6), size = Rand(0.07, 0.14), colors = { M.WHITE, M.BLUE, M.VIOLET } })
                end
            end
            -- 时钟环：绕物件中心旋转的 24 个金点（逆时针 = 倒流）
            local c = obj.center
            local R = math.max(1.2, obj.radius * 0.9)
            for i = 0, 2 do
                local a = -r.t * 4.0 + i * 2.094
                self.motesG:Spawn({ pos = c + Vector3(math.cos(a) * R, 0.2 * math.sin(r.t * 3 + i), math.sin(a) * R), vel = Vector3(0, 0, 0),
                    life = 0.5, size = 0.16, colors = { Color(1, 0.95, 0.8, 1), M.GOLD } })
            end
            keep[#keep + 1] = r
        elseif obj.state == "WHOLE" then
            self:Burst(obj.center, "restore", math.min(2.0, 0.6 + obj.radius * 0.25))
        end
    end
    self.rewinds = keep
    -- 手光
    self.handGlow = self.handGlow + ((glow or 0) - self.handGlow) * (1 - math.exp(-10 * dt))
    if handPos ~= nil then
        self.handLight.position = handPos
        self.handL.brightness = 1.6 * self.handGlow
        if glowColor ~= nil then self.handL.color = glowColor end
        if self.handGlow > 0.1 and math.random() < self.handGlow * 0.8 then
            local d = Vector3(Rand(-1, 1), Rand(-1, 1), Rand(-1, 1)):Normalized()
            self.motesB:Spawn({ pos = handPos + d * 0.25, vel = -d * 0.6 + Vector3(0, 0.3, 0), life = 0.4, size = 0.06,
                colors = { M.WHITE, glowColor or M.BLUE } })
        end
    end
end

return M
