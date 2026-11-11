-- ====================================================================
-- DragonBreath.lua — 龙吐息：中号「霜焰吐息」/ 大号「星陨龙息」（体素风特效）
--
-- 风格：像素法阵（DragonRune.shader 量化成低分辨率像素格、阶梯线、4 阶调色、定格旋转），
-- 粒子全部是硬边像素贴图（方块 / 十字 / 雪花 / 像素云团），颜色阶梯跳变；
-- 落点长出真正的体素晶簇（VoxelVolume），结束碎成立方体碎块；地面体素临时改色
-- （结霜 / 灼痕）并逐格蔓延、退回。震动统一由 trauma 驱动（镜头 + 法阵 glitch）。
--
--   中号 · 霜焰（参考冰与火冰龙）：后仰吸气、冰晶螺旋汇入口部 → 雪花像素法阵 →
--         三层冰息（亮白方块核 / 体素冰雾 / 雪花片）→ 落点结霜蔓延、冰晶簇破土、冰渣迸射
--   大号 · 星陨：低伏蓄力，七芒星地阵逐段点亮（每段一震）、星屑螺旋汇聚 →
--         口前三层法阵依次弹出 → 体素光柱一节节射出、开火卡帧重震 →
--         落点深蓝冰川晶簇林、地面冰封、冰青火花 + 霜烬、连续像素冲击环（全程蓝白，与中号的天青 / 雪白区分）
--
-- 动作：在控制器上注册外挂状态 BREATH（不改控制器源码）；喷射阶段用头部俯仰反馈对准落点。
-- 破坏预留：B:OnHit(fn) 每帧广播命中 { pos, radius, power, element, dir, origin }，
-- 以后接 ApplyDamageCone / Capsule；碎屑可复用 VoxelFX.Debris / Motes。
-- ====================================================================

local Pose = require("dragon.DragonPose")
local Poses = require("dragon.DragonPoses")
local VoxelFX = require("dragon.VoxelFX")

local M = {}

local function Clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
local function Lerp(a, b, t) return a + (b - a) * t end
local function Smooth(t) t = Clamp(t, 0, 1) return t * t * (3 - 2 * t) end
-- 窗口：t 在 [a, b] 内为 1，两端各用 ea / eb 秒淡入淡出
local function Window(t, a, b, ea, eb)
    return Smooth((t - a) / ea) * (1 - Smooth((t - b) / eb))
end

local function Keys(keys, t)
    if t <= keys[1][1] then return keys[1][2] end
    for i = 1, #keys - 1 do
        local a, b = keys[i], keys[i + 1]
        if t <= b[1] then
            local s = Smooth((t - a[1]) / (b[1] - a[1]))
            local out = {}
            for k, v in pairs(a[2]) do out[k] = Lerp(v, b[2][k] or v, s) end
            return out
        end
    end
    return keys[#keys][2]
end

-- ---------------------------------------------------------------- 型号配置
-- 时间单位秒；距离按中号写，运行时乘型号尺度 S
local CFG = {}
M.CFG = CFG

CFG.medium = {
    name = "霜焰吐息", style = 0,
    total = 4.5, fireStart = 0.95, fireEnd = 3.6,
    aimDist = 8.0, maxLen = 13.0, wings = 0.35,
    main = Color(0.08, 0.45, 1.9), accent = Color(0.35, 0.95, 1.8),
    lightColor = Color(0.55, 0.8, 1.0),
    keys = {
        { 0.0, { neck = 2, curve = 2, head = -2, jaw = 1, chest = 0, pitch = 0, dy = 0, tail = 0 } },
        { 0.8, { neck = -28, curve = -9, head = -14, jaw = 9, chest = 1, pitch = -5, dy = 0.04, tail = 6 } },
        { 1.05, { neck = 24, curve = 5, head = 0, jaw = 36, chest = 0.2, pitch = 3, dy = -0.08, tail = -2 } },
        { 3.5, { neck = 20, curve = 4, head = 0, jaw = 32, chest = 0.1, pitch = 2.5, dy = -0.07, tail = -2 } },
        { 4.5, { neck = 2, curve = 2, head = -2, jaw = 1, chest = 0, pitch = 0, dy = 0, tail = 0 } },
    },
}

CFG.large = {
    name = "星陨龙息", style = 1,
    total = 6.4, fireStart = 1.95, fireEnd = 5.1,
    aimDist = 12.0, maxLen = 26.0, wings = 0.85,
    main = Color(0.12, 0.3, 1.9), accent = Color(1.4, 1.7, 2.0),
    lightColor = Color(0.55, 0.78, 1.0),
    keys = {
        { 0.0, { neck = 2, curve = 2, head = -2, jaw = 1, chest = 0, pitch = 0, dy = 0, tail = 0 } },
        { 0.7, { neck = -18, curve = -10, head = -20, jaw = 6, chest = 1, pitch = -4, dy = 0.02, tail = 8 } },
        { 1.75, { neck = -24, curve = -12, head = -24, jaw = 12, chest = 1.2, pitch = -6, dy = -0.04, tail = 10 } },
        { 2.05, { neck = 26, curve = 6, head = 2, jaw = 38, chest = 0.2, pitch = 4, dy = -0.14, tail = -4 } },
        { 5.0, { neck = 22, curve = 5, head = 2, jaw = 34, chest = 0.1, pitch = 3.5, dy = -0.13, tail = -4 } },
        { 6.4, { neck = 2, curve = 2, head = -2, jaw = 1, chest = 0, pitch = 0, dy = 0, tail = 0 } },
    },
}

---@class DragonAnimationController
---@field breathCfg table|nil 当前型号的吐息配置（DragonBreath.New 写入）
---@field breathAim number|nil 吐息瞄准：额外的头部俯仰（度）

-- ---------------------------------------------------------------- 外挂动作状态
-- ctrl.breathCfg 由 Breath.New 写入；没有配置的型号（小号）不能吐息
function M.Register(Controller)
    if Controller.STATES.BREATH ~= nil then return end
    Controller.STATE_NAMES.BREATH = "吐息"
    Controller.STATES.BREATH = {
        blendIn = 0.35, ground = true,
        enter = function(self)
            self.breathAim = self.breathAim or 0
            self.wingOpenPose = Poses.WING_DISPLAY
        end,
        logic = function(self, dt, t)
            local L = self.loco
            local cfg = self.breathCfg
            L.speed = math.max(0, L.speed - 3.0 * dt)
            L.yawRate = L.yawRate + (0 - L.yawRate) * (1 - math.exp(-6 * dt))
            self.wingDeployTarget = (t < cfg.fireEnd + 0.2) and cfg.wings or 0.0
            if t > cfg.total then self:Request("IDLE") end
        end,
        pose = function(self, t)
            local p = Pose.New()
            local cfg = self.breathCfg
            local k = Keys(cfg.keys, t)
            local fire = Window(t, cfg.fireStart, cfg.fireEnd, 0.12, 0.35)
            -- 喷射时的颤动（大号更沉、更慢）
            local hz = (cfg.style == 1) and 19 or 27
            local shake = fire * ((cfg.style == 1) and 0.8 or 1.2)
            local aimW = Window(t, cfg.fireStart - 0.1, cfg.fireEnd, 0.2, 0.4)
            Poses.Neck(p, { pitch = k.neck, curve = k.curve, yaw = 2.5 * math.sin(t * 2.3) * fire,
                headPitch = k.head + (self.breathAim or 0) * aimW + shake * math.sin(t * hz),
                headYaw = shake * 1.4 * math.sin(t * hz * 0.83 + 1.0),
                jaw = k.jaw + 2.5 * math.sin(t * hz * 1.1) * fire })
            Poses.Tail(p, { pitch = k.tail, waveAmp = 3 + 5 * fire, wavePhase = t * (2.0 + 2.0 * fire), lag = 0.55,
                liftAmp = 2 + 2 * fire })
            Poses.Wings(p, self:GroundWing(self.wingDeploy))
            Pose.Set(p, "chest", -4 * k.chest, 0, 0)
            Pose.SetBody(p, k.pitch, 0, 0, 0, k.dy, 0)
            return p
        end,
    }
end

-- ---------------------------------------------------------------- 调色板 / 槽位
-- 龙用 40–57，地面 60/61；龙息占 62–77
--   中号「霜焰」：天青 / 雪白，通透明亮
--   大号「寒星」：深蓝宝石 / 冰川青，对比更重、发光更强
local PAL = {
    -- 中号晶簇
    ICE_BODY = 62, ICE_EDGE = 63, ICE_GLOW = 64, ICE_LIGHT = 70, ICE_DARK = 71, ICE_ROOT = 72,
    -- 中号地面霜
    FROST_A = 65, FROST_B = 66,
    -- 大号晶簇
    GLA_BODY = 67, GLA_GLOW = 68, GLA_EDGE = 73, GLA_LIGHT = 74, GLA_DARK = 75, GLA_ROOT = 76,
    -- 大号地面冰封
    FLOOR_A = 69, FLOOR_B = 77,
}
M.PAL = PAL

-- { 槽位, 颜色, 粗糙度, 自发光(rgb, 强度) }
local PAL_DEF = {
    { PAL.ICE_BODY, { 0.34, 0.64, 0.98 }, 0.12, { 0.2, 0.5, 1.0, 0.25 } },
    { PAL.ICE_LIGHT, { 0.62, 0.86, 1.0 }, 0.10, { 0.4, 0.75, 1.0, 0.35 } },
    { PAL.ICE_DARK, { 0.16, 0.40, 0.86 }, 0.15, { 0.1, 0.3, 1.0, 0.15 } },
    { PAL.ICE_EDGE, { 0.86, 0.97, 1.0 }, 0.08, { 0.7, 0.95, 1.0, 0.8 } },
    { PAL.ICE_GLOW, { 0.95, 1.0, 1.0 }, 0.05, { 0.8, 0.97, 1.0, 2.2 } },
    { PAL.ICE_ROOT, { 0.84, 0.91, 1.0 }, 0.6, nil },
    { PAL.FROST_A, { 0.72, 0.87, 1.0 }, 0.2, { 0.3, 0.6, 1.0, 0.12 } },
    { PAL.FROST_B, { 0.55, 0.76, 0.98 }, 0.2, { 0.2, 0.5, 1.0, 0.18 } },
    { PAL.GLA_BODY, { 0.10, 0.27, 0.80 }, 0.10, { 0.05, 0.2, 1.0, 0.35 } },
    { PAL.GLA_LIGHT, { 0.24, 0.55, 0.96 }, 0.08, { 0.15, 0.45, 1.0, 0.45 } },
    { PAL.GLA_DARK, { 0.04, 0.12, 0.46 }, 0.12, { 0.02, 0.1, 0.8, 0.2 } },
    { PAL.GLA_EDGE, { 0.45, 0.94, 1.0 }, 0.05, { 0.35, 0.9, 1.0, 1.2 } },
    { PAL.GLA_GLOW, { 0.80, 1.0, 1.0 }, 0.05, { 0.6, 1.0, 1.0, 3.0 } },
    { PAL.GLA_ROOT, { 0.32, 0.46, 0.76 }, 0.5, nil },
    { PAL.FLOOR_A, { 0.24, 0.44, 0.80 }, 0.08, { 0.1, 0.3, 1.0, 0.18 } },
    { PAL.FLOOR_B, { 0.36, 0.60, 0.93 }, 0.08, { 0.2, 0.55, 1.0, 0.3 } },
}

local function SetupPalette(world)
    for _, d in ipairs(PAL_DEF) do
        local c, e = d[2], d[4]
        world:SetPaletteEntry(d[1], Color(c[1], c[2], c[3]), 2.0)
        world:SetPaletteEntryPBR(d[1], d[3], 0.0, 0.8, e and Color(e[1], e[2], e[3], e[4]) or Color(0, 0, 0, 0))
    end
end

-- ---------------------------------------------------------------- 材质工具
local function ShaderMaterial(path)
    local m = Material:new()
    if not m:SetSurfaceShader(path) then print("DragonBreath: failed to load " .. path) end
    return m
end
local function SetF(m, name, v) m:SetShaderParameter(name, Variant(v)) end
local function SetC(m, name, c) m:SetShaderParameter(name, Variant(c)) end
local function C(r, g, b, a) return Color(r, g, b, a or 1) end

-- 法阵面片：局部 XY 平面的单位正方形
---@param parent Node
local function MakeRune(parent, name, style, pal, grid, seed)
    local node = parent:CreateChild(name)
    local geom = node:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, TRIANGLE_LIST)
    local c = { { -0.5, -0.5, 0, 0 }, { 0.5, -0.5, 1, 0 }, { 0.5, 0.5, 1, 1 },
        { -0.5, -0.5, 0, 0 }, { 0.5, 0.5, 1, 1 }, { -0.5, 0.5, 0, 1 } }
    for _, v in ipairs(c) do
        geom:DefineVertex(Vector3(v[1], v[2], 0))
        geom:DefineNormal(Vector3(0, 0, -1))
        geom:DefineTexCoord(Vector2(v[3], v[4]))
    end
    geom:Commit()
    local mat = ShaderMaterial("Shaders/BLGL/DragonRune.shader")
    SetF(mat, "style", style)
    SetF(mat, "grid", grid)
    SetF(mat, "seed", seed or 0)
    SetC(mat, "dark_color", pal[1]); SetC(mat, "main_color", pal[2])
    SetC(mat, "light_color", pal[3]); SetC(mat, "hot_color", pal[4])
    SetF(mat, "fade", 0)
    geom:SetMaterial(mat)
    geom.castShadows = false
    node.enabled = false
    return { node = node, mat = mat, last = {} }
end

-- 只在值变化时写参数（避免每帧大量 Variant）
local function RuneParam(r, name, v)
    if r.last[name] ~= v then
        r.last[name] = v
        SetF(r.mat, name, v)
    end
end

local function SetRune(r, fade, reveal, spin, spin2, pulse, glitch, intensity)
    if fade <= 0.01 then
        if r.node.enabled then r.node.enabled = false end
        return
    end
    if not r.node.enabled then r.node.enabled = true end
    -- 数值量化：像素法阵按步进变化，不做连续平滑（定格动画感）
    local q = function(x, n) return math.floor(x * n + 0.5) / n end
    RuneParam(r, "fade", q(fade, 16))
    RuneParam(r, "reveal", q(reveal, 40))
    RuneParam(r, "spin", spin)
    RuneParam(r, "spin2", spin2)
    RuneParam(r, "pulse", q(pulse, 8))
    RuneParam(r, "glitch", q(glitch, 8))
    RuneParam(r, "intensity", intensity)
end

-- 旋转步进：每秒 steps 次，每次转 1/k 圈 → 像素图案一格一格地跳
local function StepAngle(t, speed, steps)
    return math.floor(t * steps) / steps * speed
end

-- ---------------------------------------------------------------- 体素光柱（大号）
-- 一节节方形截面的光段，沿轴向前推；用 Box + 光束 shader
local function MakeBeamSegs(parent, n, core, edge)
    local list = {}
    local model = cache:GetResource("Model", "Models/Box.mdl")
    for i = 1, n do
        local node = parent:CreateChild("BeamSeg" .. i)
        local sm = node:CreateComponent("StaticModel")
        sm:SetModel(model)
        local mat = ShaderMaterial("Shaders/BLGL/DragonBeam.shader")
        local outer = (i > 1)
        SetC(mat, "core_color", outer and C(0.7, 1.0, 1.0) or core)
        SetC(mat, "edge_color", outer and C(0.25, 0.75, 1.0) or edge)
        SetC(mat, "dark_color", C(0.02, 0.06, 0.25))
        SetF(mat, "seed", i * 1.37)
        SetF(mat, "cells", outer and 3 or 10)
        sm:SetMaterial(mat)
        sm.castShadows = false
        node.enabled = false
        list[i] = { node = node, mat = mat, outer = outer }
    end
    return list
end

-- ---------------------------------------------------------------- 构建
---@class DragonBreath
local B = {}
B.__index = B

---@param scene Scene
---@param rig DragonRig
---@param ctrl DragonAnimationController
---@param ground table|nil { volume, origin, cell }：可改色的地面体积
---@return DragonBreath
function M.New(scene, rig, ctrl, variantId, ground)
    local self = setmetatable({}, B)
    self.rig, self.ctrl = rig, ctrl
    self.world = ctrl.world
    self.S = rig.size or 1.0
    self.cfg = CFG[variantId or "medium"]
    self.trauma, self.shake, self.hitstop = 0.0, 0.0, 0.0
    self.master = 0.0
    self.lastTime = ctrl.time
    self.fxT, self.prevT = 0.0, 0.0
    self.events = {}
    self.listeners = {}
    ctrl.breathCfg = self.cfg
    if self.cfg == nil then
        print("DragonBreath: variant " .. tostring(variantId) .. " has no breath")
        return self
    end
    SetupPalette(self.world)
    if ground ~= nil then
        self.ground = VoxelFX.GroundPainter(ground.volume, ground.origin, ground.cell, 0)
    end
    self:Build(scene)
    print(string.format("DragonBreath: %s ready (size %.2f, crystals %d)", self.cfg.name, self.S, #self.crystals))
    return self
end

function B:Available() return self.cfg ~= nil end
function B:Busy() return self.ctrl.state == "BREATH" end

-- 命中广播：fn(info)，info = { pos, radius, power, element = "frost"/"astral", dir }
-- 供以后的体素破坏接入（ApplyDamageCone / Capsule），同一帧可能多次回调
function B:OnHit(fn) self.listeners[#self.listeners + 1] = fn end

function B:Trigger()
    local c = self.ctrl
    if self.cfg == nil or c.loco.airborne then return false end
    if c.state == "BREATH" or c.state == "TAKEOFF" or c.state == "LAND" then return false end
    c.demo = nil
    c.breathAim = 0
    c:Request("BREATH")
    print("DragonBreath: trigger " .. self.cfg.name)
    return c.state == "BREATH"
end

function B:Build(scene)
    local cfg, S = self.cfg, self.S
    local root = scene:CreateChild("DragonBreathFX")
    root.temporary = true
    self.root = root
    ---@type VoxelFXCrystal[]
    self.crystals = {}
    local frost = (cfg.style == 0)

    -- 法阵
    self.runes = {}
    if frost then
        local pal = { C(0.02, 0.07, 0.24), C(0.12, 0.5, 1.0), C(0.45, 0.9, 1.0), C(0.95, 1.0, 1.0) }
        self.runes[1] = MakeRune(root, "MouthRune", 0, pal, 44, 1)
        self.runes[1].size, self.runes[1].dist = 2.6 * S, 1.0 * S
        self.groundRune = MakeRune(root, "GroundRune", 0, pal, 72, 2)
        self.groundRune.size = 8.0 * S
    else
        local palV = { C(0.01, 0.03, 0.16), C(0.1, 0.3, 0.95), C(0.4, 0.72, 1.0), C(0.9, 1.0, 1.0) }
        local palG = { C(0.01, 0.1, 0.2), C(0.2, 0.75, 1.0), C(0.6, 0.97, 1.0), C(1.0, 1.0, 1.0) }
        local layers = { { 2.2, 1.2, palV, 40 }, { 3.3, 2.7, palG, 52 }, { 4.6, 4.5, palV, 64 } }
        for i, ly in ipairs(layers) do
            local r = MakeRune(root, "MouthRune" .. i, 1, ly[3], ly[4], i * 3)
            r.size, r.dist = ly[1] * S, ly[2] * S
            self.runes[i] = r
        end
        self.groundRune = MakeRune(root, "GroundRune", 1, palV, 96, 9)
        self.groundRune.size = 14.0 * S
    end
    -- 冲击环池
    self.rings = {}
    local ringPal = frost and { C(0.02, 0.07, 0.24), C(0.3, 0.7, 1.0), C(0.75, 0.96, 1.0), C(1, 1, 1) }
        or { C(0.01, 0.03, 0.16), C(0.15, 0.45, 1.0), C(0.5, 0.92, 1.0), C(1, 1, 1) }
    for i = 1, 5 do
        local r = MakeRune(root, "Ring" .. i, 2, ringPal, frost and 56 or 80, i * 11)
        r.age = 1.0
        self.rings[i] = r
    end
    self.ringTimer = 0.0

    -- 粒子：引擎发射器（大量）
    local k = S
    self.em = {}
    if frost then
        -- 核心冰流：亮白小方块，速度快
        self.em.core = VoxelFX.Emitter(root, "FrostCore", { kind = "square", additive = true, n = 600, setup = function(fx)
            fx:SetEmitterType(EMITTER_SPHERE); fx:SetEmitterSize(Vector3(0.12, 0.12, 0.12) * k)
            fx:SetMinDirection(Vector3(-0.07, -0.07, 1)); fx:SetMaxDirection(Vector3(0.07, 0.07, 1))
            fx:SetMinVelocity(16 * k); fx:SetMaxVelocity(22 * k)
            fx:SetMinTimeToLive(0.35); fx:SetMaxTimeToLive(0.55)
            fx:SetMinParticleSize(Vector2(0.16, 0.16) * k); fx:SetMaxParticleSize(Vector2(0.26, 0.26) * k)
            VoxelFX.Steps(fx, { { 0, C(1, 1, 1, 1) }, { 0.2, C(0.6, 0.92, 1.0, 1) }, { 0.4, C(0.5, 0.78, 1.0, 0.9) }, { 0.55, C(0, 0, 0, 0) } })
        end })
        -- 体素冰雾：块状云团，膨胀
        self.em.mist = VoxelFX.Emitter(root, "FrostMist", { kind = "cloud", n = 700, setup = function(fx)
            fx:SetEmitterType(EMITTER_SPHERE); fx:SetEmitterSize(Vector3(0.2, 0.2, 0.2) * k)
            fx:SetMinDirection(Vector3(-0.15, -0.14, 1)); fx:SetMaxDirection(Vector3(0.15, 0.16, 1))
            fx:SetMinVelocity(10 * k); fx:SetMaxVelocity(15 * k)
            fx:SetDampingForce(1.3)
            fx:SetMinTimeToLive(0.6); fx:SetMaxTimeToLive(0.9)
            fx:SetMinParticleSize(Vector2(0.35, 0.35) * k); fx:SetMaxParticleSize(Vector2(0.6, 0.6) * k)
            fx:SetSizeAdd(1.3 * k)
            VoxelFX.Steps(fx, { { 0, C(0.92, 0.98, 1.0, 0.75) }, { 0.15, C(0.7, 0.9, 1.0, 0.55) }, { 0.38, C(0.55, 0.8, 1.0, 0.35) },
                { 0.62, C(0.5, 0.72, 0.98, 0.18) }, { 0.85, C(0, 0, 0, 0) } })
        end })
        -- 雪花片：外围，减速后下沉
        self.em.flake = VoxelFX.Emitter(root, "Flakes", { kind = "flake", n = 500, setup = function(fx)
            fx:SetEmitterType(EMITTER_SPHERE); fx:SetEmitterSize(Vector3(0.3, 0.3, 0.3) * k)
            fx:SetMinDirection(Vector3(-0.3, -0.2, 1)); fx:SetMaxDirection(Vector3(0.3, 0.35, 1))
            fx:SetMinVelocity(8 * k); fx:SetMaxVelocity(14 * k)
            fx:SetDampingForce(2.2)
            fx:SetConstantForce(Vector3(0, -2.5, 0))
            fx:SetMinTimeToLive(0.9); fx:SetMaxTimeToLive(1.6)
            fx:SetMinParticleSize(Vector2(0.14, 0.14) * k); fx:SetMaxParticleSize(Vector2(0.24, 0.24) * k)
            fx:SetMinRotationSpeed(-120); fx:SetMaxRotationSpeed(120)
            VoxelFX.Steps(fx, { { 0, C(1, 1, 1, 1) }, { 0.5, C(0.7, 0.9, 1.0, 1) }, { 0.85, C(0.5, 0.75, 1.0, 0.7) }, { 1.0, C(0, 0, 0, 0) } })
        end })
        -- 落点：贴地霜雾
        self.em.ground = VoxelFX.Emitter(root, "GroundMist", { kind = "cloud", n = 300, setup = function(fx)
            fx:SetEmitterType(EMITTER_BOX); fx:SetEmitterSize(Vector3(2.0, 0.2, 2.0) * k)
            fx:SetMinDirection(Vector3(-1, 0.05, -1)); fx:SetMaxDirection(Vector3(1, 0.3, 1))
            fx:SetMinVelocity(1.5 * k); fx:SetMaxVelocity(3.5 * k)
            fx:SetDampingForce(1.6)
            fx:SetMinTimeToLive(1.0); fx:SetMaxTimeToLive(1.7)
            fx:SetMinParticleSize(Vector2(0.5, 0.5) * k); fx:SetMaxParticleSize(Vector2(0.9, 0.9) * k)
            fx:SetSizeAdd(0.8 * k)
            VoxelFX.Steps(fx, { { 0, C(0.85, 0.95, 1.0, 0.0) }, { 0.1, C(0.82, 0.94, 1.0, 0.5) }, { 0.5, C(0.7, 0.86, 1.0, 0.3) }, { 0.85, C(0.6, 0.8, 1.0, 0.15) }, { 1.0, C(0, 0, 0, 0) } })
        end })
        -- 落点：冰渣迸射（小方块，抛物线）
        self.em.chips = VoxelFX.Emitter(root, "IceChips", { kind = "square", n = 400, setup = function(fx)
            fx:SetEmitterType(EMITTER_SPHERE); fx:SetEmitterSize(Vector3(0.8, 0.2, 0.8) * k)
            fx:SetMinDirection(Vector3(-1, 1.0, -1)); fx:SetMaxDirection(Vector3(1, 2.2, 1))
            fx:SetMinVelocity(4 * k); fx:SetMaxVelocity(9 * k)
            fx:SetConstantForce(Vector3(0, -20, 0))
            fx:SetMinTimeToLive(0.6); fx:SetMaxTimeToLive(1.0)
            fx:SetMinParticleSize(Vector2(0.1, 0.1) * k); fx:SetMaxParticleSize(Vector2(0.18, 0.18) * k)
            VoxelFX.Steps(fx, { { 0, C(1, 1, 1, 1) }, { 0.35, C(0.7, 0.92, 1.0, 1) }, { 0.7, C(0.4, 0.7, 1.0, 1) }, { 1.0, C(0, 0, 0, 0) } })
        end })
    else
        -- 绕束星屑（白 / 冰青 / 深蓝，加色）
        self.em.core = VoxelFX.Emitter(root, "AstralSparks", { kind = "cross", additive = true, n = 700, setup = function(fx)
            fx:SetEmitterType(EMITTER_SPHERE); fx:SetEmitterSize(Vector3(0.7, 0.7, 0.7) * k)
            fx:SetMinDirection(Vector3(-0.05, -0.05, 1)); fx:SetMaxDirection(Vector3(0.05, 0.05, 1))
            fx:SetMinVelocity(24 * k); fx:SetMaxVelocity(34 * k)
            fx:SetMinTimeToLive(0.4); fx:SetMaxTimeToLive(0.7)
            fx:SetMinParticleSize(Vector2(0.26, 0.26) * k); fx:SetMaxParticleSize(Vector2(0.4, 0.4) * k)
            VoxelFX.Steps(fx, { { 0, C(1, 1, 1, 1) }, { 0.3, C(0.6, 0.95, 1.0, 1) }, { 0.6, C(0.3, 0.55, 1.0, 1) }, { 1.0, C(0, 0, 0, 0) } })
        end })
        -- 束外寒雾（深一点的蓝）
        self.em.mist = VoxelFX.Emitter(root, "AstralSmoke", { kind = "cloud", n = 500, setup = function(fx)
            fx:SetEmitterType(EMITTER_SPHERE); fx:SetEmitterSize(Vector3(0.9, 0.9, 0.9) * k)
            fx:SetMinDirection(Vector3(-0.25, -0.25, 1)); fx:SetMaxDirection(Vector3(0.25, 0.25, 1))
            fx:SetMinVelocity(6 * k); fx:SetMaxVelocity(11 * k)
            fx:SetDampingForce(1.8)
            fx:SetMinTimeToLive(0.6); fx:SetMaxTimeToLive(1.0)
            fx:SetMinParticleSize(Vector2(0.4, 0.4) * k); fx:SetMaxParticleSize(Vector2(0.65, 0.65) * k)
            fx:SetSizeAdd(0.9 * k)
            VoxelFX.Steps(fx, { { 0, C(0.8, 0.92, 1.0, 0.0) }, { 0.08, C(0.6, 0.8, 1.0, 0.45) }, { 0.4, C(0.42, 0.62, 0.95, 0.28) }, { 0.75, C(0.3, 0.46, 0.85, 0.12) }, { 1.0, C(0, 0, 0, 0) } })
        end })
        -- 落点：火花（方块，抛物线）
        self.em.chips = VoxelFX.Emitter(root, "ImpactSparks", { kind = "square", additive = true, n = 800, setup = function(fx)
            fx:SetEmitterType(EMITTER_SPHERE); fx:SetEmitterSize(Vector3(0.8, 0.2, 0.8) * k)
            fx:SetMinDirection(Vector3(-1, 0.8, -1)); fx:SetMaxDirection(Vector3(1, 2.4, 1))
            fx:SetMinVelocity(7 * k); fx:SetMaxVelocity(16 * k)
            fx:SetConstantForce(Vector3(0, -22, 0))
            fx:SetMinTimeToLive(0.7); fx:SetMaxTimeToLive(1.3)
            fx:SetMinParticleSize(Vector2(0.14, 0.14) * k); fx:SetMaxParticleSize(Vector2(0.24, 0.24) * k)
            VoxelFX.Steps(fx, { { 0, C(1, 1, 1, 1) }, { 0.25, C(0.7, 1.0, 1.0, 1) }, { 0.55, C(0.35, 0.75, 1.0, 1) }, { 0.8, C(0.18, 0.4, 0.95, 1) }, { 1.0, C(0, 0, 0, 0) } })
        end })
        -- 落点：冰雾烟柱
        self.em.ground = VoxelFX.Emitter(root, "ImpactSmoke", { kind = "cloud", n = 300, setup = function(fx)
            fx:SetEmitterType(EMITTER_SPHERE); fx:SetEmitterSize(Vector3(1.4, 0.3, 1.4) * k)
            fx:SetMinDirection(Vector3(-1, 0.6, -1)); fx:SetMaxDirection(Vector3(1, 1.6, 1))
            fx:SetMinVelocity(2.5 * k); fx:SetMaxVelocity(6 * k)
            fx:SetDampingForce(1.4)
            fx:SetMinTimeToLive(0.9); fx:SetMaxTimeToLive(1.5)
            fx:SetMinParticleSize(Vector2(0.5, 0.5) * k); fx:SetMaxParticleSize(Vector2(0.9, 0.9) * k)
            fx:SetSizeAdd(0.7 * k)
            VoxelFX.Steps(fx, { { 0, C(0.95, 1.0, 1.0, 0.6) }, { 0.12, C(0.7, 0.88, 1.0, 0.42) }, { 0.45, C(0.5, 0.7, 0.98, 0.26) }, { 0.8, C(0.38, 0.55, 0.9, 0.12) }, { 1.0, C(0, 0, 0, 0) } })
        end })
        -- 光束（体素光柱）
        self.beam = MakeBeamSegs(root, 5, C(0.95, 1.0, 1.0), C(0.15, 0.4, 1.0))
    end

    -- Lua 粒子：螺旋汇聚 / 绕束 / 余烬 / 闪光
    self.motes = VoxelFX.Motes(root, "Motes", 420, frost and "star" or "cross", true)
    self.motesA = VoxelFX.Motes(root, "MotesAlpha", 260, "square", false)
    -- 立方体碎块
    self.debris = VoxelFX.Debris(root, 70)

    -- 晶簇（真正的体素体积）
    -- 中号：细长尖锐的天青冰刺，围成一圈向外炸开
    -- 大号：粗壮的深蓝冰川六棱柱，两圈「晶林」，尖顶短
    local mats = frost and { body = PAL.ICE_BODY, light = PAL.ICE_LIGHT, dark = PAL.ICE_DARK,
            edge = PAL.ICE_EDGE, glow = PAL.ICE_GLOW, root = PAL.ICE_ROOT }
        or { body = PAL.GLA_BODY, light = PAL.GLA_LIGHT, dark = PAL.GLA_DARK,
            edge = PAL.GLA_EDGE, glow = PAL.GLA_GLOW, root = PAL.GLA_ROOT }
    local palMat = self.world:GetPaletteMaterial()
    -- { 环半径, 高度, 粗细, 侧晶数, 外倾角 }（按中号尺寸写，乘 S）
    local layout = frost and {
        { 0, 2.7, 0.36, 5, 0 },
        { 1.5, 1.7, 0.24, 3, 16 }, { 1.7, 1.4, 0.22, 3, 20 }, { 1.4, 1.9, 0.25, 3, 14 },
        { 1.8, 1.2, 0.2, 2, 24 }, { 1.6, 1.6, 0.23, 3, 18 },
        { 2.8, 0.9, 0.16, 2, 32 }, { 3.0, 0.7, 0.14, 1, 38 }, { 2.7, 1.0, 0.17, 2, 30 },
        { 3.2, 0.6, 0.13, 1, 40 }, { 2.9, 0.8, 0.15, 2, 34 },
    } or {
        { 0, 3.3, 0.62, 4, 0 },
        { 2.2, 2.4, 0.46, 2, 10 }, { 2.4, 2.0, 0.42, 2, 12 }, { 2.1, 2.7, 0.5, 2, 8 },
        { 2.5, 1.8, 0.4, 2, 14 }, { 2.3, 2.2, 0.44, 2, 11 },
        { 4.0, 1.4, 0.34, 1, 18 }, { 4.3, 1.1, 0.3, 1, 22 }, { 3.9, 1.5, 0.36, 2, 16 },
        { 4.4, 1.0, 0.28, 1, 24 }, { 4.1, 1.3, 0.32, 1, 20 }, { 4.5, 0.9, 0.26, 1, 26 },
    }
    local n = #layout
    local ring1 = 0
    for _, ly in ipairs(layout) do if ly[1] > 0 and ly[1] < 2.6 then ring1 = ring1 + 1 end end
    local i1, i2 = 0, 0
    for i, ly in ipairs(layout) do
        local main = (i == 1)
        local a
        if main then a = 0
        elseif ly[1] < 2.6 then
            a = i1 / ring1 * math.pi * 2 + VoxelFX.Hash(i * 9.1) * 0.5; i1 = i1 + 1
        else
            a = (i2 + 0.5) / (n - 1 - ring1) * math.pi * 2 + VoxelFX.Hash(i * 5.3) * 0.4; i2 = i2 + 1
        end
        local cr = VoxelFX.Crystal(self.world, palMat, root, "Crystal" .. i, {
            voxel = (frost and 0.09 or 0.1) * S, height = ly[2] * S, radius = ly[3] * S,
            count = 1 + ly[4], seed = i * 2.7 + (frost and 0 or 50), tip = frost and 0.5 or 0.8, mats = mats })
        local rr = ly[1] * S
        cr.off = Vector3(math.cos(a) * rr, 0, math.sin(a) * rr)
        cr.lean = ly[5]
        cr.out = Vector3(math.cos(a), 0, math.sin(a))
        -- 先中心后外圈：一波向外炸开
        cr.delay = main and 0 or ((ly[1] / (frost and 3.2 or 4.5)) * 0.35 + 0.06 * VoxelFX.Hash(i * 6.1))
        cr.yaw = VoxelFX.Hash(i * 2.9) * 360
        cr.state = "hidden"
        self.crystals[i] = cr
    end
    self.crystalLinger = frost and 2.2 or 3.0  -- 喷射结束后晶簇停留多久再碎

    -- 灯光
    local function MakeLight(name, range)
        local nd = root:CreateChild(name)
        local l = nd:CreateComponent("Light")
        l.lightType = LIGHT_POINT
        l.color = cfg.lightColor
        l.brightness = 0
        l.range = range
        l.castShadows = false
        nd.enabled = false
        return { node = nd, light = l }
    end
    self.mouthLight = MakeLight("MouthLight", 9 * S)
    self.impactLight = MakeLight("ImpactLight", 14 * S)

    -- 音效
    self.snd = {}
    local function Src(name)
        local nd = root:CreateChild("Snd_" .. name)
        local src = nd:CreateComponent("SoundSource3D")
        src:SetDistanceAttenuation(4 * S, 70 * S, 1.0)
        src.soundType = SOUND_EFFECT
        return { node = nd, src = src }
    end
    self.snd.mouth = Src("mouth")
    self.snd.impact = Src("impact")
    self.snd.extra = Src("extra")
    self.sounds = frost and {
        charge = "audio/sfx/breath_frost_charge.mp3", blast = "audio/sfx/breath_frost_blast.mp3",
        grow = "audio/sfx/breath_ice_grow.mp3", shatter = "audio/sfx/breath_ice_shatter.mp3",
    } or {
        charge = "audio/sfx/breath_astral_charge.mp3", blast = "audio/sfx/breath_astral_beam.mp3",
        grow = "audio/sfx/breath_astral_impact.mp3", shatter = "audio/sfx/breath_ice_shatter.mp3",
    }
end

function B:Play(which, src, gain, pitch)
    local path = self.sounds[which]
    if path == nil then return end
    local snd = cache:GetResource("Sound", path)
    if snd == nil then return end
    local s = self.snd[src].src
    s:Play(snd, (pitch or 1.0) * snd.frequency, gain or 1.0)
end

function B:Destroy()
    if self.ctrl ~= nil and self.ctrl.breathCfg == self.cfg then self.ctrl.breathCfg = nil end
    if self.ground ~= nil then self.ground:Recede(0, 0, 0); self.ground:Flush() end
    for _, cr in ipairs(self.crystals or {}) do
        if cr.volume ~= nil then self.world:RemoveVolume(cr.volume) end
    end
    self.crystals = {}
    if self.root ~= nil then self.root:Remove() end
    self.root = nil
end

-- ---------------------------------------------------------------- 工具
function B:MouthFrame()
    local rig = self.rig
    local p = rig.sockets.mouth.worldPosition
    local d = p - rig.bones.head.worldPosition
    if d:LengthSquared() < 1e-6 then d = rig.bones.head.worldRotation * Vector3.FORWARD end
    return p, d:Normalized()
end

local function Basis(dir)
    local side = Vector3(dir.z, 0, -dir.x)
    if side:LengthSquared() < 1e-4 then side = Vector3.RIGHT end
    side = side:Normalized()
    return side, dir:CrossProduct(side)
end

local function Rand(a, b) return a + (b - a) * math.random() end

-- 冲击量：加到 trauma（0..1），镜头震动 = trauma²
function B:Kick(amount)
    self.trauma = math.min(1.0, self.trauma + amount)
end

-- 跨越时间点（本帧 t 越过 at）
local function Crossed(prev, t, at) return prev < at and t >= at end

-- ---------------------------------------------------------------- 晶簇
---@param pos Vector3
function B:CrystalAt(i, pos)
    local cr = self.crystals[i]
    local b = Vector3(pos.x + cr.off.x, pos.y, pos.z + cr.off.z)
    cr.base = b
    cr.base = Vector3(b.x, self.ctrl:GroundHeight(b.x, b.z), b.z)
    cr.grow, cr.state, cr.age = 0, "grow", -cr.delay
end

function B:UpdateCrystals(dt)
    local S = self.S
    for _, cr in ipairs(self.crystals) do
        if cr.state == "grow" or cr.state == "hold" then
            cr.age = cr.age + dt
            if cr.age >= 0 then
                if not cr.holder.enabled then
                    cr.holder.enabled = true
                    -- 破土瞬间：一圈冰渣 / 碎石方块
                    for _ = 1, 6 do
                        local a = math.random() * math.pi * 2
                        self.debris:Spawn({ pos = cr.base + Vector3(math.cos(a) * 0.3 * S, 0.15 * S, math.sin(a) * 0.3 * S),
                            vel = Vector3(math.cos(a) * Rand(1.5, 3.5), Rand(3, 6), math.sin(a) * Rand(1.5, 3.5)) * S,
                            size = Rand(0.08, 0.16) * S, color = (self.cfg.style == 0) and C(0.84, 0.93, 1.0) or C(0.32, 0.46, 0.76),
                            glow = 0.4, life = Rand(0.8, 1.3), spin = 540, groundFn = self.groundFn })
                    end
                end
                -- 分段升起（体素感：一节节顶出来），最后一段过冲回弹
                local steps = (self.cfg.style == 0) and 6 or 8
                local dur = (self.cfg.style == 0) and 0.3 or 0.42
                local u = math.min(1, cr.age / dur)
                local stepped = math.floor(u * steps) / steps
                local over = (u >= 1) and (1 + 0.06 * math.max(0, 1 - (cr.age - dur) / 0.15)) or stepped
                cr.grow = over
                -- 向外倾斜（绕切线轴），中心主晶直立
                local tilt = Quaternion(cr.lean or 0, Vector3(cr.out.z, 0, -cr.out.x))
                local up = tilt * Vector3.UP
                cr.holder.position = cr.base - up * (cr.height * (1 - math.min(1, over)))
                cr.holder.rotation = tilt * Quaternion(cr.yaw, Vector3.UP)
                local sc = 0.75 + 0.25 * math.min(1, over)
                cr.holder.scale = Vector3(sc, over, sc)
                -- 立住以后：晶面上零星闪光（像素星），停留期间一直有
                if u >= 1 then
                    cr.glint = (cr.glint or 0) - dt
                    if cr.glint <= 0 then
                        cr.glint = Rand(0.15, 0.45)
                        local hgt = Rand(0.3, 1.0) * cr.height
                        local p = cr.base + up * hgt + Vector3(Rand(-1, 1), 0, Rand(-1, 1)) * cr.radius * (1.1 - hgt / cr.height)
                        local frost = (self.cfg.style == 0)
                        self.motes:Spawn({ pos = p, vel = Vector3(0, 0.3 * S, 0), life = Rand(0.3, 0.55),
                            size = Rand(0.16, 0.28) * S, colors = frost and { C(1, 1, 1), C(0.75, 0.95, 1.0), C(0.45, 0.8, 1.0) }
                                or { C(1, 1, 1), C(0.55, 1.0, 1.0), C(0.25, 0.6, 1.0) } })
                    end
                end
            end
        end
    end
end

-- 碎裂：晶簇隐藏，换成一批立方体碎块（颜色取晶体调色板）
function B:ShatterCrystals()
    local S, frost = self.S, (self.cfg.style == 0)
    local cols = frost and { C(0.42, 0.72, 0.98), C(0.72, 0.92, 1.0), C(0.92, 1.0, 1.0) }
        or { C(0.1, 0.27, 0.8), C(0.24, 0.55, 0.96), C(0.45, 0.94, 1.0), C(0.8, 1.0, 1.0) }
    local any = false
    for _, cr in ipairs(self.crystals) do
        if cr.holder.enabled then
            any = true
            cr.holder.enabled = false
            local n = math.max(4, math.floor(10 * cr.height / (2.6 * S)))
            for j = 1, n do
                local y = (j / n) * cr.height * 0.9
                local p = cr.base + Vector3(Rand(-0.25, 0.25) * S, y, Rand(-0.25, 0.25) * S)
                local out = (p - cr.base); out = Vector3(out.x, 0, out.z)
                if out:LengthSquared() < 1e-4 then out = Vector3(Rand(-1, 1), 0, Rand(-1, 1)) end
                out = out:Normalized()
                self.debris:Spawn({ pos = p, vel = (out * Rand(2, 5) + Vector3(0, Rand(2, 6), 0)) * math.sqrt(S),
                    size = Rand(0.14, 0.3) * S, color = cols[math.random(1, #cols)], glow = frost and 0.5 or 0.9,
                    life = Rand(1.2, 2.0), spin = 400, groundFn = self.groundFn, bounce = 0.4 })
            end
            -- 碎晶闪粉
            for _ = 1, 10 do
                self.motes:Spawn({ pos = cr.base + Vector3(Rand(-0.4, 0.4) * S, Rand(0, cr.height), Rand(-0.4, 0.4) * S),
                    vel = Vector3(Rand(-2, 2), Rand(1, 4), Rand(-2, 2)) * S, grav = 6, drag = 1.5, life = Rand(0.5, 0.9),
                    size = Rand(0.12, 0.2) * S, colors = frost and { C(1, 1, 1), C(0.6, 0.9, 1.0), C(0.3, 0.6, 1.0) }
                        or { C(1, 1, 1), C(0.5, 0.95, 1.0), C(0.2, 0.45, 1.0) } })
            end
        end
        cr.state = "hidden"
    end
    if any then self:Play("shatter", "extra", 0.9, frost and 1.0 or 0.8); self:Kick(0.25) end
end

-- ---------------------------------------------------------------- 主更新
function B:Update()
    if self.cfg == nil or self.root == nil then return end
    local c, cfg, S = self.ctrl, self.cfg, self.S
    local dt = c.time - self.lastTime
    self.lastTime = c.time
    if dt < 0 then dt = 0 end
    self.groundFn = self.groundFn or function(x, z) return c:GroundHeight(x, z) end
    local active = (c.state == "BREATH")
    local prevT = self.fxT
    if active then self.fxT = c.stateT else self.fxT = self.fxT + dt end
    local t = self.fxT
    if active and t < prevT then prevT = -1 end -- 重新开始
    self.master = active and 1.0 or math.max(0, self.master - dt * 3.0)
    local m = self.master
    local frost = (cfg.style == 0)

    -- 一直要跑的：碎块 / Lua 粒子 / 晶簇 / 地面霜蔓延 / 冲击环
    self.motes:Update(dt)
    self.motesA:Update(dt)
    self.debris:Update(dt)
    self:UpdateCrystals(dt)
    self:UpdateRings(dt)
    self:UpdateGround(dt, t, active)
    self.trauma = math.max(0, self.trauma - dt * 1.4)
    self.hitstop = math.max(0, self.hitstop - dt)
    -- 晶簇在喷射结束后停留 crystalLinger 秒再碎（BREATH 状态结束后照样计时）
    if self.crystalT ~= nil and t > self.crystalT then self.crystalT = nil; self:ShatterCrystals() end

    if m <= 0 and not active then
        if not self.hidden then self:HideAll() end
        self.shake = self.trauma * self.trauma
        return
    end
    self.hidden = false

    local origin, dir = self:MouthFrame()
    local side, up = Basis(dir)
    local fire = Window(t, cfg.fireStart, cfg.fireEnd, 0.06, 0.25) * m
    local gy = c:GroundHeight(origin.x, origin.z)
    local L = c.loco
    local yawR = math.rad(L.yaw)
    local fwd = Vector3(math.sin(yawR), 0, math.cos(yawR))

    -- 瞄准反馈
    local horiz = math.sqrt(dir.x * dir.x + dir.z * dir.z)
    local curPitch = math.deg(math.atan(-dir.y, math.max(horiz, 1e-4)))
    local wantPitch = math.deg(math.atan(origin.y - gy, cfg.aimDist * S))
    if active and t > cfg.fireStart - 0.25 and t < cfg.fireEnd then
        c.breathAim = Clamp((c.breathAim or 0) + (wantPitch - curPitch) * 5.0 * dt, -40, 40)
    end

    -- 落点
    local len = cfg.maxLen * S
    if dir.y < -0.02 then len = math.min(len, (origin.y - gy) / -dir.y) end
    local hit = origin + dir * len
    local hitGround = dir.y < -0.02 and len < cfg.maxLen * S - 0.01
    local hitG = Vector3(hit.x, c:GroundHeight(hit.x, hit.z), hit.z)
    self.hitPos = hitG
    local frontQ = Quaternion(Vector3.FORWARD, dir)

    -- ---------------- 时间事件
    if active then
        if Crossed(prevT, t, 0.05) then self:Play("charge", "mouth", 0.85) end
        if Crossed(prevT, t, cfg.fireStart) then
            self:Play("blast", "mouth", 1.0)
            self:Kick(frost and 0.35 or 0.75)
            if not frost then self.hitstop = 0.07 end
            -- 开火瞬间：口部炸出一圈闪粉
            for _ = 1, frost and 30 or 50 do
                local a = math.random() * math.pi * 2
                local v = (side * math.cos(a) + up * math.sin(a)) * Rand(3, 7) + dir * Rand(2, 6)
                self.motes:Spawn({ pos = origin + dir * 0.4 * S, vel = v * S, drag = 3, life = Rand(0.3, 0.55),
                    size = Rand(0.14, 0.26) * S, colors = frost and { C(1, 1, 1), C(0.7, 0.95, 1.0), C(0.35, 0.7, 1.0) }
                        or { C(1, 1, 1), C(0.55, 0.95, 1.0), C(0.2, 0.45, 1.0) } })
            end
        end
        local tCrystal = cfg.fireStart + (frost and 0.45 or 0.3)
        if Crossed(prevT, t, tCrystal) and hitGround then
            for i = 1, #self.crystals do self:CrystalAt(i, hitG) end
            self.crystalT = cfg.fireEnd + self.crystalLinger
            self:Play("grow", "impact", 1.0)
            self:Kick(frost and 0.3 or 0.45)
        end

        if not frost then
            -- 蓄力阶段：地面阵每亮一段震一下
            for j = 1, 4 do
                if Crossed(prevT, t, 0.3 + 0.35 * j) then self:Kick(0.12) end
            end
        end
    end


    -- 持续震动：喷射中维持一个底噪
    if fire > 0.3 then self.trauma = math.max(self.trauma, frost and 0.32 or 0.5) end
    local glitch = Clamp(self.trauma * 1.4, 0, 1)

    -- ---------------- 法阵
    local chest = self.rig.bones.chest.worldPosition
    local gp = Vector3(chest.x, c:GroundHeight(chest.x, chest.z) + 0.04, chest.z) + fwd * (frost and 0.6 or 1.4) * S
    local gr = self.groundRune
    gr.node.position = gp
    gr.node.rotation = Quaternion(L.yaw, Vector3.UP) * Quaternion(90, Vector3.RIGHT)
    gr.node.scale = Vector3(gr.size, gr.size, 1)
    local now = c.time
    local beat = (math.floor(now * 8) % 2 == 0) and 1 or 0.6
    if frost then
        SetRune(gr, Window(t, 0.15, cfg.fireEnd + 0.25, 0.3, 0.5) * m, Smooth((t - 0.15) / 0.6),
            StepAngle(now, 0.35, 6), -StepAngle(now, 0.55, 6), 0.4 * fire * beat, glitch * 0.6, 1.4)
        local r = self.runes[1]
        r.node.position = origin + dir * r.dist + (side * Rand(-1, 1) + up * Rand(-1, 1)) * 0.03 * S * glitch
        r.node.rotation = frontQ
        local pop = 1.0 + 0.12 * math.max(0, 1 - (t - cfg.fireStart) / 0.15) * (t > cfg.fireStart and 1 or 0)
        r.node.scale = Vector3(r.size * pop, r.size * pop, 1)
        SetRune(r, Window(t, 0.3, cfg.fireEnd + 0.1, 0.25, 0.3) * m, Smooth((t - 0.3) / 0.5),
            StepAngle(now, 1.6, 10), -StepAngle(now, 2.4, 10), fire * beat, glitch, 1.6 + 0.8 * fire)
    else
        SetRune(gr, Window(t, 0.0, cfg.fireEnd + 0.35, 0.3, 0.6) * m, Smooth(t / 1.4),
            StepAngle(now, 0.2, 5), -StepAngle(now, 0.3, 5), 0.3 + 0.7 * fire * beat, glitch * 0.7, 1.5)
        for i, r in ipairs(self.runes) do
            local t0 = 0.45 + 0.35 * (i - 1)
            local sgn = (i % 2 == 0) and -1 or 1
            r.node.position = origin + dir * r.dist + (side * Rand(-1, 1) + up * Rand(-1, 1)) * 0.04 * S * glitch
            r.node.rotation = frontQ
            local pop = 1.0 + 0.15 * math.max(0, 1 - (t - cfg.fireStart - 0.05 * i) / 0.18) * (t > cfg.fireStart + 0.05 * i and 1 or 0)
            r.node.scale = Vector3(r.size * pop, r.size * pop, 1)
            SetRune(r, Window(t, t0, cfg.fireEnd + 0.12 * i, 0.2, 0.35) * m, Smooth((t - t0) / 0.4),
                sgn * StepAngle(now, 1.0 + 0.4 * i, 8), -sgn * StepAngle(now, 1.6, 8), fire * beat, glitch, 1.6 + 1.0 * fire)
            if Crossed(prevT, t, t0) then self:Kick(0.1) end
        end
    end

    -- ---------------- 蓄力粒子：向口部螺旋汇聚
    local chargeW = Window(t, 0.15, cfg.fireStart, 0.3, 0.05) * m
    if active and chargeW > 0.05 then
        local rate = (frost and 70 or 140) * chargeW
        self.chargeAcc = (self.chargeAcc or 0) + rate * dt
        while self.chargeAcc >= 1 do
            self.chargeAcc = self.chargeAcc - 1
            local a0 = math.random() * math.pi * 2
            local r0 = Rand(1.6, frost and 3.2 or 5.0) * S
            local back = Rand(0.5, 2.5) * S
            local life = Rand(0.45, 0.8)
            local o = origin + dir * 0.5 * S
            local gold = (not frost) and math.random() < 0.45
            self.motes:Spawn({ life = life, size = Rand(0.14, 0.24) * S,
                colors = frost and { C(0.5, 0.8, 1.0), C(0.75, 0.95, 1.0), C(1, 1, 1) }
                    or (gold and { C(0.3, 0.85, 1.0), C(0.65, 1.0, 1.0), C(1, 1, 1) } or { C(0.12, 0.3, 1.0), C(0.4, 0.62, 1.0), C(0.9, 0.96, 1.0) }),
                fn = function(mo, _, u)
                    local p = u * u
                    local ang = a0 + p * math.pi * 2.2
                    local rad = r0 * (1 - p)
                    local o2, d2 = self:MouthFrame()
                    local s2, u2 = Basis(d2)
                    -- 螺旋：像素化的位置（量化到 0.1m 网格）
                    local pos = o2 + d2 * (0.5 * S + back * (1 - p)) + (s2 * math.cos(ang) + u2 * math.sin(ang)) * rad
                    local g = 0.1 * S
                    mo.pos = Vector3(math.floor(pos.x / g + 0.5) * g, math.floor(pos.y / g + 0.5) * g, math.floor(pos.z / g + 0.5) * g)
                end, pos = o })
        end
    end

    -- ---------------- 吐息流
    local emitPos = origin + dir * 0.25 * S
    for _, key in ipairs({ "core", "mist", "flake" }) do
        local e = self.em[key]
        if e ~= nil then
            e.node.position = emitPos
            e.node.rotation = frontQ
        end
    end
    local firing = fire > 0.35
    -- 发射率随噪声脉动（吐息有呼吸感，不是匀速水管）
    local surge = 0.75 + 0.25 * math.sin(now * 11.0) + 0.15 * math.sin(now * 23.0 + 1.0)
    if frost then
        VoxelFX.SetRate(self.em.core, 340 * surge); VoxelFX.SetEmit(self.em.core, firing)
        VoxelFX.SetRate(self.em.mist, 240 * surge); VoxelFX.SetEmit(self.em.mist, firing)
        VoxelFX.SetRate(self.em.flake, 150); VoxelFX.SetEmit(self.em.flake, firing)
        local gOn = firing and hitGround and t > cfg.fireStart + 0.2
        self.em.ground.node.position = hitG + Vector3(0, 0.25 * S, 0)
        VoxelFX.SetRate(self.em.ground, 90); VoxelFX.SetEmit(self.em.ground, gOn)
        self.em.chips.node.position = hitG + Vector3(0, 0.1, 0)
        VoxelFX.SetRate(self.em.chips, 160 * surge); VoxelFX.SetEmit(self.em.chips, gOn)
    else
        VoxelFX.SetRate(self.em.core, 320 * surge); VoxelFX.SetEmit(self.em.core, firing)
        VoxelFX.SetRate(self.em.mist, 45); VoxelFX.SetEmit(self.em.mist, firing)
        local gOn = firing and hitGround
        self.em.chips.node.position = hitG + Vector3(0, 0.1, 0)
        VoxelFX.SetRate(self.em.chips, 380 * surge); VoxelFX.SetEmit(self.em.chips, gOn)
        self.em.ground.node.position = hitG + Vector3(0, 0.3 * S, 0)
        VoxelFX.SetRate(self.em.ground, 28); VoxelFX.SetEmit(self.em.ground, gOn)
        self:UpdateBeam(origin, dir, len, fire, t, now)
        -- 绕束旋转的方块星屑
        if firing then
            self.orbitAcc = (self.orbitAcc or 0) + 90 * dt
            while self.orbitAcc >= 1 do
                self.orbitAcc = self.orbitAcc - 1
                local a0 = math.random() * math.pi * 2
                local d0 = Rand(0.5, 0.95)
                local gold = math.random() < 0.4
                self.motes:Spawn({ life = Rand(0.35, 0.6), size = Rand(0.16, 0.3) * S,
                    colors = gold and { C(1, 1, 1), C(0.6, 1.0, 1.0), C(0.25, 0.7, 1.0) } or { C(0.85, 0.92, 1.0), C(0.4, 0.6, 1.0), C(0.12, 0.25, 0.9) },
                    pos = origin, fn = function(mo, _, u)
                        local o2, d2 = self:MouthFrame()
                        local s2, u2 = Basis(d2)
                        local along = (d0 + 0.25 * u) * (self.beamLen or len)
                        local ang = a0 + u * 9.0
                        local rad = (0.55 + 0.6 * u) * S
                        mo.pos = o2 + d2 * along + (s2 * math.cos(ang) + u2 * math.sin(ang)) * rad
                    end })
            end
        end
    end

    -- ---------------- 落点：冲击环 / 碎块 / 命中广播
    self.ringTimer = self.ringTimer - dt
    if firing and hitGround and self.ringTimer <= 0 then
        self.ringTimer = frost and 0.38 or 0.18
        self:SpawnRing(hitG, frost and 6.5 * S or 10 * S, frost and 0.9 or 0.65)
        -- 冲击波掀起的地面方块
        local n = frost and 3 or 6
        for _ = 1, n do
            local a = math.random() * math.pi * 2
            local rr = Rand(0.5, frost and 2.5 or 4.0) * S
            local p = hitG + Vector3(math.cos(a) * rr, 0.1 * S, math.sin(a) * rr)
            self.debris:Spawn({ pos = p, vel = Vector3(math.cos(a) * Rand(1, 3), Rand(4, 8), math.sin(a) * Rand(1, 3)) * math.sqrt(S),
                size = Rand(0.16, 0.32) * S, color = frost and C(0.86, 0.93, 1.0) or C(0.3, 0.45, 0.78), glow = frost and 0.25 or 0.6,
                life = Rand(1.0, 1.6), spin = 300, groundFn = self.groundFn, bounce = 0.3 })
        end
        if not frost then self:Kick(0.08) end
    end
    if firing and hitGround then
        local info = { pos = hitG, radius = (frost and 1.6 or 2.6) * S, power = (frost and 1.0 or 3.0) * fire,
            element = frost and "frost" or "astral", dir = dir, origin = origin }
        for _, fn in ipairs(self.listeners) do fn(info) end
        -- 星陨：落点持续上升的霜烬
        if not frost then
            self.emberAcc = (self.emberAcc or 0) + 50 * dt
            while self.emberAcc >= 1 do
                self.emberAcc = self.emberAcc - 1
                local a = math.random() * math.pi * 2
                local rr = Rand(0.3, 3.0) * S
                self.motes:Spawn({ pos = hitG + Vector3(math.cos(a) * rr, 0.2, math.sin(a) * rr),
                    vel = Vector3(Rand(-0.5, 0.5), Rand(2, 5), Rand(-0.5, 0.5)) * S, drag = 0.8, life = Rand(0.8, 1.6),
                    size = Rand(0.14, 0.24) * S, colors = { C(1, 1, 1), C(0.6, 0.95, 1.0), C(0.3, 0.6, 1.0), C(0.12, 0.25, 0.8) } })
            end
        end
    end

    -- ---------------- 灯光
    local glowK = math.max(chargeW * 0.6, fire)
    local flick = (math.floor(now * 14) % 2 == 0) and 1.0 or 0.82
    local ml = self.mouthLight
    ml.node.enabled = glowK > 0.01
    ml.node.position = origin + dir * 0.6 * S
    ml.light.brightness = (frost and 45 or 70) * glowK * flick
    local il = self.impactLight
    local hk = hitGround and fire or 0
    il.node.enabled = hk > 0.01
    il.node.position = hitG + Vector3(0, 1.0 * S, 0)
    il.light.brightness = (frost and 70 or 140) * hk * flick

    self.snd.mouth.node.position = origin
    self.snd.impact.node.position = hitG
    self.snd.extra.node.position = hitG
    self.shake = self.trauma * self.trauma
end

-- 体素光柱：两层方形截面的 Box，外层按 45° 扭转、宽度阶梯脉动
function B:UpdateBeam(origin, dir, len, fire, t, now)
    local cfg, S = self.cfg, self.S
    local ext = math.floor(Smooth((t - cfg.fireStart) / 0.12) * 6) / 6 -- 一节节射出
    local bl = math.max(0.05, len * ext)
    self.beamLen = bl
    local pulse = (math.floor(now * 16) % 3 == 0) and 1.12 or 1.0
    local side, up = Basis(dir)
    local base = Quaternion(Vector3.UP, dir)
    for i, seg in ipairs(self.beam) do
        if fire > 0.01 then
            if not seg.node.enabled then seg.node.enabled = true end
            if seg.outer then
                -- 四根冰青细光棱绕主束螺旋（每 1/8 秒跳一档角度）
                local a = (i - 2) * math.pi * 0.5 + math.floor(now * 8) * (math.pi / 12)
                local rr = 0.95 * S * (0.6 + 0.4 * fire)
                local w = 0.22 * S * pulse
                seg.node.position = origin + dir * (bl * 0.5) + (side * math.cos(a) + up * math.sin(a)) * rr
                seg.node.rotation = base * Quaternion(45, Vector3.UP)
                seg.node.scale = Vector3(w, bl * 0.92, w)
            else
                local w = 1.25 * S * (0.5 + 0.5 * fire) * pulse
                seg.node.position = origin + dir * (bl * 0.5)
                seg.node.rotation = base * Quaternion(45, Vector3.UP)
                seg.node.scale = Vector3(w, bl, w)
            end
            SetF(seg.mat, "fade", fire)
            SetF(seg.mat, "scroll", now * (seg.outer and 1.3 or 1.0))
            SetF(seg.mat, "intensity", seg.outer and 2.4 or 2.8)
            SetF(seg.mat, "beam_len", bl)
        elseif seg.node.enabled then
            seg.node.enabled = false
        end
    end
end

function B:SpawnRing(pos, size, life)
    for _, r in ipairs(self.rings) do
        if r.age >= 1.0 then
            r.age, r.pos, r.size, r.life = 0.0, pos + Vector3(0, 0.06, 0), size, life
            r.node.rotation = Quaternion(90, Vector3.RIGHT)
            return
        end
    end
end

function B:UpdateRings(dt)
    for i, r in ipairs(self.rings) do
        if r.age < 1.0 then
            r.age = math.min(1.0, r.age + dt / r.life)
            r.node.position = r.pos
            r.node.scale = Vector3(r.size, r.size, 1)
            -- 半径一档一档跳（像素扩散）
            local rr = 0.1 + 0.85 * (1 - (1 - r.age) ^ 2.0)
            RuneParam(r, "ring_r", math.floor(rr * 24) / 24)
            SetRune(r, 1 - r.age * r.age, 1, 0, 0, 0, 0.3, 1.6)
        else
            SetRune(r, 0, 0, 0, 0, 0, 0, 0)
        end
    end
end

-- 地面结霜 / 灼痕：喷射中从落点逐格蔓延，结束后逐格退回
function B:UpdateGround(dt, t, active)
    local gp = self.ground
    if gp == nil then return end
    local cfg, S, frost = self.cfg, self.S, (self.cfg.style == 0)
    self.paintT = (self.paintT or 0) + dt
    if self.paintT < 0.06 then return end -- 一秒约 16 次，蔓延是一格格跳的
    self.paintT = 0
    local maxR = (frost and 5.5 or 6.5) * S
    if active and t > cfg.fireStart + 0.15 and t < cfg.fireEnd and self.hitPos ~= nil then
        self.paintCenter = self.hitPos
        self.paintR = math.min(maxR, (self.paintR or 0) + (frost and 6 or 9) * S * 0.06)
        local cx, cz = self.paintCenter.x, self.paintCenter.z
        gp:Paint(cx, cz, self.paintR, function(i, k, d)
            if frost then
                return (VoxelFX.Hash(i * 3.7 + k * 1.3) > 0.45 + 0.4 * d) and PAL.FROST_B or PAL.FROST_A
            end
            -- 大号：深蓝冰封地面，靠近中心更亮
            return (d < 0.35 or VoxelFX.Hash(i * 5.1 + k * 2.3) > 0.55 + 0.35 * d) and PAL.FLOOR_B or PAL.FLOOR_A
        end)
    elseif self.paintCenter ~= nil and gp:HasPaint() then
        -- 冰晶碎掉之后地面霜 / 冰封再退
        local holdEnd = cfg.fireEnd + self.crystalLinger + 0.2
        if t > holdEnd then
            self.paintR = math.max(0, (self.paintR or 0) - 5 * S * 0.06)
            gp:Recede(self.paintCenter.x, self.paintCenter.z, self.paintR)
            if self.paintR <= 0 then gp:Recede(0, 0, 0); self.paintCenter = nil end
        end
    end
    gp:Flush()
end

function B:HideAll()
    self.hidden = true
    for _, r in ipairs(self.runes) do SetRune(r, 0, 0, 0, 0, 0, 0, 0) end
    SetRune(self.groundRune, 0, 0, 0, 0, 0, 0, 0)
    for _, e in pairs(self.em) do VoxelFX.SetEmit(e, false) end
    if self.beam ~= nil then for _, seg in ipairs(self.beam) do seg.node.enabled = false end end
    self.mouthLight.node.enabled = false
    self.impactLight.node.enabled = false
    self.paintR = self.paintR or 0
end

return M
