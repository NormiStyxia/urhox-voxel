-- ====================================================================
-- DragonBreath.lua — 龙吐息：中号「霜焰吐息」/ 大号「星陨龙息」
--
-- 两种型号的区别：
--   中号 · 霜焰：后仰吸气 → 口前一面六芒雪花法阵 + 脚下霜阵 → 前探喷出一股冰蓝霜焰
--         （锥形粒子流 + 冰晶碎屑），落点结霜、冒出一圈冰刺，霜环向外扩散。
--   大号 · 星陨：低伏蓄力，脚下巨型七芒星阵展开，口前沿射线依次亮起三层法阵，
--         星屑螺旋汇聚入口 → 一道紫金光束贯穿三层法阵射向地面，落点连续冲击环 + 火花迸射，
--         镜头震动。
--
-- 动作：在控制器上注册一个外挂状态 BREATH（不改控制器源码），姿态按关键帧生成；
-- 喷射阶段用头部俯仰的反馈修正，让口部方向对准前方地面上的落点。
-- 特效全部挂在场景根下独立的 FX 节点上（世界坐标），每帧按口部挂点更新；
-- 拆龙 / 换型号时 Destroy 一次即可。
-- 依赖资源：Shaders/BLGL/DragonRune.shader（法阵）、Shaders/BLGL/DragonBeam.shader（光束），
-- 粒子贴图在 Lua 里用 Image 生成。
-- ====================================================================

local Pose = require("dragon.DragonPose")
local Poses = require("dragon.DragonPoses")

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
    main = Color(0.30, 0.72, 1.6), accent = Color(0.85, 0.97, 1.6),
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
    main = Color(0.62, 0.32, 1.7), accent = Color(1.6, 1.15, 0.45),
    lightColor = Color(0.8, 0.55, 1.0),
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

-- ---------------------------------------------------------------- 资源（程序化贴图 / 材质）
---@type table<string, Texture2D>
local texCache = {}

-- kind: "dot" 柔光点；"puff" 带噪声的雾团
---@return Texture2D
local function MakeTexture(kind)
    local cached = texCache[kind]
    if cached ~= nil then return cached end
    local N = 64
    local img = Image()
    img:SetSize(N, N, 4)
    local seed = { }
    for i = 1, 16 do seed[i] = math.sin(i * 12.9898) * 43758.5453 % 1 end
    for y = 0, N - 1 do
        for x = 0, N - 1 do
            local u, v = (x + 0.5) / N * 2 - 1, (y + 0.5) / N * 2 - 1
            local r = math.sqrt(u * u + v * v)
            local a
            if kind == "dot" then
                a = math.exp(-r * r * 5.0) * (1 - Smooth((r - 0.85) / 0.15))
            else
                local ang = math.atan(v, u)
                local n = 0.65 + 0.2 * math.sin(ang * 5 + seed[1] * 6) + 0.15 * math.sin(ang * 9 + r * 7 + seed[2] * 6)
                a = math.max(0, 1 - r / n) ^ 1.6
            end
            img:SetPixel(x, y, Color(a, a, a, a))
        end
    end
    local tex = Texture2D:new()
    tex:SetData(img, true)
    texCache[kind] = tex
    return tex
end

local function AddMaterial(kind)
    local m = Material:new()
    m:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffUnlitParticleAdd.xml"))
    local tex = MakeTexture(kind)
    m:SetTexture(TU_DIFFUSE, tex)
    return m
end

local function ShaderMaterial(path)
    local m = Material:new()
    if not m:SetSurfaceShader(path) then
        print("DragonBreath: failed to load " .. path)
    end
    return m
end

local function SetF(m, name, v) m:SetShaderParameter(name, Variant(v)) end
local function SetC(m, name, c) m:SetShaderParameter(name, Variant(c)) end
local function Scaled(c, k) return Color(c.r * k, c.g * k, c.b * k, 1.0) end

-- 法阵面片：局部 XY 平面上的单位正方形（UV 0..1）
---@param parent Node
local function MakeRune(parent, name, style, main, accent)
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
    SetC(mat, "main_color", main)
    SetC(mat, "accent_color", accent)
    SetF(mat, "fade", 0.0)
    geom:SetMaterial(mat)
    geom.castShadows = false
    node.enabled = false
    return { node = node, mat = mat }
end

local function SetRune(r, fade, reveal, spin, spin2, pulse, intensity)
    if fade <= 0.002 then
        if r.node.enabled then r.node.enabled = false end
        return
    end
    if not r.node.enabled then r.node.enabled = true end
    SetF(r.mat, "fade", fade)
    SetF(r.mat, "reveal", reveal)
    SetF(r.mat, "spin", spin)
    SetF(r.mat, "spin2", spin2)
    SetF(r.mat, "pulse", pulse)
    SetF(r.mat, "intensity", intensity)
end

---@param parent Node
local function MakeEmitter(parent, name, kind, setup)
    local node = parent:CreateChild(name)
    local fx = ParticleEffect:new()
    fx:SetMaterial(AddMaterial(kind))
    fx:SetRelative(false)
    fx:SetUpdateInvisible(true)
    fx:SetMinEmissionRate(0)
    fx:SetMaxEmissionRate(0)
    setup(fx)
    local em = node:CreateComponent("ParticleEmitter")
    em:SetEffect(fx)
    em.castShadows = false
    em:SetEmitting(false)
    return { node = node, fx = fx, em = em, on = false }
end

local function SetEmit(e, on)
    if e.on ~= on then
        e.on = on
        e.em:SetEmitting(on)
    end
end

local function Beam(parent, name, core, edge, sharp, darken)
    local node = parent:CreateChild(name)
    local sm = node:CreateComponent("StaticModel")
    sm:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    local mat = ShaderMaterial("Shaders/BLGL/DragonBeam.shader")
    SetC(mat, "core_color", core)
    SetC(mat, "edge_color", edge)
    SetF(mat, "sharp", sharp)
    SetF(mat, "darken", darken)
    sm:SetMaterial(mat)
    sm.castShadows = false
    node.enabled = false
    return { node = node, mat = mat }
end

-- ---------------------------------------------------------------- 构建
---@class DragonBreath
local B = {}
B.__index = B

---@param scene Scene
---@param rig DragonRig
---@param ctrl DragonAnimationController
---@return DragonBreath
function M.New(scene, rig, ctrl, variantId)
    local self = setmetatable({}, B)
    self.rig, self.ctrl = rig, ctrl
    self.S = rig.size or 1.0
    self.cfg = CFG[variantId or "medium"]
    self.shake = 0.0
    self.master = 0.0
    self.lastTime = ctrl.time
    self.fxT = 0.0
    ctrl.breathCfg = self.cfg
    if self.cfg == nil then
        print("DragonBreath: variant " .. tostring(variantId) .. " has no breath")
        return self
    end
    self:Build(scene)
    print(string.format("DragonBreath: %s ready (size %.2f)", self.cfg.name, self.S))
    return self
end

function B:Available() return self.cfg ~= nil end

-- 开始吐息（只能在地面且不在起降中）
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

function B:Busy() return self.ctrl.state == "BREATH" end

function B:Build(scene)
    local cfg, S = self.cfg, self.S
    local root = scene:CreateChild("DragonBreathFX")
    root.temporary = true
    self.root = root
    local main, accent = cfg.main, cfg.accent

    -- 法阵：中号口前一面 + 地面一面；大号口前三层 + 地面巨阵
    self.runes = {}
    if cfg.style == 0 then
        self.runes[1] = MakeRune(root, "MouthRune", 0, main, accent)
        self.runes[1].size, self.runes[1].dist = 2.4 * S, 1.0 * S
        self.ground = MakeRune(root, "GroundRune", 0, Scaled(main, 0.8), accent)
        self.ground.size = 7.5 * S
    else
        local layers = { { 2.0, 1.1 }, { 3.1, 2.6 }, { 4.4, 4.4 } }
        for i, ly in ipairs(layers) do
            local r = MakeRune(root, "MouthRune" .. i, 1, (i == 2) and accent or main, (i == 2) and main or accent)
            r.size, r.dist = ly[1] * S, ly[2] * S
            self.runes[i] = r
        end
        self.ground = MakeRune(root, "GroundRune", 1, main, accent)
        self.ground.size = 13.0 * S
    end
    -- 落点冲击环（对象池）
    self.rings = {}
    for i = 1, 4 do
        local r = MakeRune(root, "ImpactRing" .. i, 2, (cfg.style == 0) and Scaled(accent, 0.9) or accent, main)
        r.age = 1.0
        r.node.rotation = Quaternion(90, Vector3.RIGHT)
        self.rings[i] = r
    end
    self.ringTimer = 0.0

    -- 粒子
    local k = S
    if cfg.style == 0 then
        -- 霜焰主流：锥形喷出，雾团逐渐膨胀、由白转蓝再消散
        self.stream = MakeEmitter(root, "FrostStream", "puff", function(fx)
            fx:SetNumParticles(900)
            fx:SetEmitterType(EMITTER_SPHERE)
            fx:SetEmitterSize(Vector3(0.15, 0.15, 0.15) * k)
            fx:SetMinDirection(Vector3(-0.13, -0.13, 1))
            fx:SetMaxDirection(Vector3(0.13, 0.13, 1))
            fx:SetMinVelocity(11 * k); fx:SetMaxVelocity(16 * k)
            fx:SetDampingForce(1.2)
            fx:SetMinTimeToLive(0.55); fx:SetMaxTimeToLive(0.85)
            fx:SetMinParticleSize(Vector2(0.35, 0.35) * k); fx:SetMaxParticleSize(Vector2(0.6, 0.6) * k)
            fx:SetSizeAdd(2.6 * k)
            fx:SetMinRotationSpeed(-90); fx:SetMaxRotationSpeed(90)
            fx:SetMinRotation(0); fx:SetMaxRotation(360)
            fx:SetMinEmissionRate(520); fx:SetMaxEmissionRate(620)
            fx:AddColorTime(Color(0.95, 1.0, 1.0, 1), 0.0)
            fx:AddColorTime(Color(0.45, 0.8, 1.0, 1), 0.18)
            fx:AddColorTime(Color(0.12, 0.38, 0.95, 1), 0.5)
            fx:AddColorTime(Color(0.0, 0.0, 0.0, 0), 0.85)
        end)
        -- 冰晶碎屑：细长亮点，速度更快，略受重力
        self.sparks = MakeEmitter(root, "FrostShards", "dot", function(fx)
            fx:SetNumParticles(400)
            fx:SetEmitterType(EMITTER_SPHERE)
            fx:SetEmitterSize(Vector3(0.2, 0.2, 0.2) * k)
            fx:SetMinDirection(Vector3(-0.2, -0.16, 1))
            fx:SetMaxDirection(Vector3(0.2, 0.2, 1))
            fx:SetMinVelocity(14 * k); fx:SetMaxVelocity(22 * k)
            fx:SetConstantForce(Vector3(0, -6, 0))
            fx:SetMinTimeToLive(0.4); fx:SetMaxTimeToLive(0.7)
            fx:SetMinParticleSize(Vector2(0.05, 0.35) * k); fx:SetMaxParticleSize(Vector2(0.08, 0.55) * k)
            fx:SetMinEmissionRate(160); fx:SetMaxEmissionRate(220)
            fx:AddColorTime(Color(1, 1, 1, 1), 0.0)
            fx:AddColorTime(Color(0.6, 0.9, 1.0, 1), 0.4)
            fx:AddColorTime(Color(0, 0, 0, 0), 0.7)
        end)
        self.sparks.em:SetFaceCameraMode(FC_DIRECTION)
        -- 落点霜雾：贴地缓慢翻滚
        self.impactFx = MakeEmitter(root, "FrostMist", "puff", function(fx)
            fx:SetNumParticles(260)
            fx:SetEmitterType(EMITTER_SPHERE)
            fx:SetEmitterSize(Vector3(1.6, 0.3, 1.6) * k)
            fx:SetMinDirection(Vector3(-1, 0.1, -1)); fx:SetMaxDirection(Vector3(1, 0.5, 1))
            fx:SetMinVelocity(1.0 * k); fx:SetMaxVelocity(2.6 * k)
            fx:SetDampingForce(1.5)
            fx:SetMinTimeToLive(1.0); fx:SetMaxTimeToLive(1.6)
            fx:SetMinParticleSize(Vector2(0.8, 0.8) * k); fx:SetMaxParticleSize(Vector2(1.4, 1.4) * k)
            fx:SetSizeAdd(1.4 * k)
            fx:SetMinRotationSpeed(-40); fx:SetMaxRotationSpeed(40)
            fx:SetMaxRotation(360)
            fx:SetMinEmissionRate(110); fx:SetMaxEmissionRate(140)
            fx:AddColorTime(Color(0.5, 0.8, 1.0, 0.7), 0.0)
            fx:AddColorTime(Color(0.2, 0.45, 0.9, 0.5), 0.5)
            fx:AddColorTime(Color(0, 0, 0, 0), 1.6)
        end)
        -- 冰刺：落点周围一圈体素冰柱，喷射中长出、结束后碎缩
        local iceMat = Material:new()
        iceMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        iceMat:SetShaderParameter("MatDiffColor", Variant(Color(0.75, 0.9, 1.0, 1.0)))
        iceMat:SetShaderParameter("MatEmissiveColor", Variant(Color(0.25, 0.55, 1.1)))
        iceMat:SetShaderParameter("Roughness", Variant(0.15))
        iceMat:SetShaderParameter("Metallic", Variant(0.0))
        self.ice = {}
        for i = 1, 14 do
            local n = root:CreateChild("IceSpike" .. i)
            local sm = n:CreateComponent("StaticModel")
            sm:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            sm:SetMaterial(iceMat)
            n.enabled = false
            local a = (i / 14) * math.pi * 2 + math.sin(i * 7.1) * 0.35
            local rr = (0.9 + 1.8 * ((math.sin(i * 3.7) * 0.5 + 0.5))) * S
            self.ice[i] = { node = n, a = a, r = rr, h = (0.7 + 1.1 * (math.sin(i * 5.3) * 0.5 + 0.5)) * S,
                w = (0.16 + 0.12 * (math.sin(i * 2.1) * 0.5 + 0.5)) * S, delay = (i % 5) * 0.12,
                tilt = 14 + 18 * (math.sin(i * 9.7) * 0.5 + 0.5) }
        end
    else
        -- 光束：外层紫色宽光 + 内核金白细光
        self.beamOuter = Beam(root, "BeamOuter", Color(0.9, 0.6, 1.6), Color(0.35, 0.12, 1.2), 1.2, 0.0)
        self.beamCore = Beam(root, "BeamCore", Color(1.8, 1.6, 1.2), Color(1.4, 0.8, 0.35), 2.5, 0.0)
        -- 沿光束飞出的星屑
        self.stream = MakeEmitter(root, "AstralEmbers", "dot", function(fx)
            fx:SetNumParticles(700)
            fx:SetEmitterType(EMITTER_SPHERE)
            fx:SetEmitterSize(Vector3(0.6, 0.6, 0.6) * k)
            fx:SetMinDirection(Vector3(-0.06, -0.06, 1))
            fx:SetMaxDirection(Vector3(0.06, 0.06, 1))
            fx:SetMinVelocity(22 * k); fx:SetMaxVelocity(34 * k)
            fx:SetMinTimeToLive(0.35); fx:SetMaxTimeToLive(0.6)
            fx:SetMinParticleSize(Vector2(0.07, 0.6) * k); fx:SetMaxParticleSize(Vector2(0.12, 1.1) * k)
            fx:SetMinEmissionRate(380); fx:SetMaxEmissionRate(460)
            fx:AddColorTime(Color(1, 0.9, 0.6, 1), 0.0)
            fx:AddColorTime(Color(0.75, 0.45, 1.0, 1), 0.35)
            fx:AddColorTime(Color(0, 0, 0, 0), 0.6)
        end)
        self.stream.em:SetFaceCameraMode(FC_DIRECTION)
        -- 落点火花：向上迸射、受重力落下
        self.impactFx = MakeEmitter(root, "ImpactSparks", "dot", function(fx)
            fx:SetNumParticles(700)
            fx:SetEmitterType(EMITTER_SPHERE)
            fx:SetEmitterSize(Vector3(0.6, 0.2, 0.6) * k)
            fx:SetMinDirection(Vector3(-1, 0.6, -1)); fx:SetMaxDirection(Vector3(1, 1.6, 1))
            fx:SetMinVelocity(6 * k); fx:SetMaxVelocity(15 * k)
            fx:SetConstantForce(Vector3(0, -16, 0))
            fx:SetMinTimeToLive(0.6); fx:SetMaxTimeToLive(1.2)
            fx:SetMinParticleSize(Vector2(0.06, 0.4) * k); fx:SetMaxParticleSize(Vector2(0.1, 0.7) * k)
            fx:SetMinEmissionRate(380); fx:SetMaxEmissionRate(480)
            fx:AddColorTime(Color(1, 0.95, 0.8, 1), 0.0)
            fx:AddColorTime(Color(1.0, 0.6, 0.25, 1), 0.3)
            fx:AddColorTime(Color(0.6, 0.2, 0.9, 1), 0.7)
            fx:AddColorTime(Color(0, 0, 0, 0), 1.2)
        end)
        self.impactFx.em:SetFaceCameraMode(FC_DIRECTION)
        -- 落点烟尘（紫色辉光）
        self.sparks = MakeEmitter(root, "ImpactGlow", "puff", function(fx)
            fx:SetNumParticles(200)
            fx:SetEmitterType(EMITTER_SPHERE)
            fx:SetEmitterSize(Vector3(1.0, 0.2, 1.0) * k)
            fx:SetMinDirection(Vector3(-1, 0.3, -1)); fx:SetMaxDirection(Vector3(1, 1.0, 1))
            fx:SetMinVelocity(1.5 * k); fx:SetMaxVelocity(4 * k)
            fx:SetDampingForce(1.4)
            fx:SetMinTimeToLive(0.8); fx:SetMaxTimeToLive(1.3)
            fx:SetMinParticleSize(Vector2(1.2, 1.2) * k); fx:SetMaxParticleSize(Vector2(2.0, 2.0) * k)
            fx:SetSizeAdd(2.0 * k)
            fx:SetMaxRotation(360)
            fx:SetMinRotationSpeed(-60); fx:SetMaxRotationSpeed(60)
            fx:SetMinEmissionRate(70); fx:SetMaxEmissionRate(90)
            fx:AddColorTime(Color(0.9, 0.6, 1.0, 0.8), 0.0)
            fx:AddColorTime(Color(0.35, 0.12, 0.7, 0.5), 0.5)
            fx:AddColorTime(Color(0, 0, 0, 0), 1.3)
        end)
    end

    -- 光点：口部 / 落点辉光，大号额外有汇聚星屑（手动驱动的 Billboard）
    local bbNode = root:CreateChild("Flares")
    local bb = bbNode:CreateComponent("BillboardSet")
    bb:SetMaterial(AddMaterial("dot"))
    bb:SetRelative(false)
    bb:SetSorted(false)
    bb.castShadows = false
    self.nMotes = (cfg.style == 1) and 56 or 0
    bb:SetNumBillboards(2 + self.nMotes)
    for i = 0, 1 + self.nMotes do bb:GetBillboard(i).enabled = false end
    bb:Commit()
    self.bb = bb
    self.motes = {}
    for i = 1, self.nMotes do
        local h = function(n) return math.sin(i * n) * 0.5 + 0.5 end
        self.motes[i] = { a = h(12.9) * math.pi * 2, r = (2.2 + 3.2 * h(7.3)) * S, off = h(3.1) * 1.2,
            dur = 0.7 + 0.5 * h(5.7), up = (h(9.1) - 0.5) * 2.0 * S, gold = h(1.7) > 0.45 }
    end

    -- 灯光
    local function MakeLight(name)
        local n = root:CreateChild(name)
        local l = n:CreateComponent("Light")
        l.lightType = LIGHT_POINT
        l.color = cfg.lightColor
        l.brightness = 0
        l.range = 9 * S
        l.castShadows = false
        n.enabled = false
        return { node = n, light = l }
    end
    self.mouthLight = MakeLight("MouthLight")
    self.impactLight = MakeLight("ImpactLight")
    self.impactLight.light.range = 12 * S
end

function B:Destroy()
    if self.ctrl ~= nil and self.ctrl.breathCfg == self.cfg then self.ctrl.breathCfg = nil end
    if self.root ~= nil then self.root:Remove() end
    self.root = nil
end

-- ---------------------------------------------------------------- 更新
-- 口部挂点的世界位置与方向（头部枢轴 → 口部挂点）
function B:MouthFrame()
    local rig = self.rig
    local mouth = rig.sockets.mouth
    local head = rig.bones.head
    local p = mouth.worldPosition
    local d = p - head.worldPosition
    if d:LengthSquared() < 1e-6 then d = head.worldRotation * Vector3.FORWARD end
    return p, d:Normalized()
end

local function Flare(bb, i, pos, size, col)
    local b = bb:GetBillboard(i)
    if size <= 0.001 or col.a <= 0.002 then
        b.enabled = false
        return
    end
    b.enabled = true
    b.position = pos
    b.size = Vector2(size, size)
    b.color = col
end

function B:Update()
    if self.cfg == nil or self.root == nil then return end
    local c, cfg, S = self.ctrl, self.cfg, self.S
    local dt = c.time - self.lastTime
    self.lastTime = c.time
    if dt < 0 then dt = 0 end
    local active = (c.state == "BREATH")
    if active then self.fxT = c.stateT end
    local t = self.fxT
    -- 被打断（换状态）时整体快速淡出
    self.master = active and 1.0 or math.max(0, self.master - dt * 2.5)
    local m = self.master
    if m <= 0 and not active then
        if not self.hidden then self:HideAll() end
        return
    end
    self.hidden = false

    local origin, dir = self:MouthFrame()
    local fire = Window(t, cfg.fireStart, cfg.fireEnd, 0.08, 0.3) * m
    local gy = c:GroundHeight(origin.x, origin.z)

    -- 头部瞄准反馈：让口部指向前方地面上的落点
    local L = c.loco
    local yawR = math.rad(L.yaw)
    local fwd = Vector3(math.sin(yawR), 0, math.cos(yawR))
    local horiz = math.sqrt(dir.x * dir.x + dir.z * dir.z)
    local curPitch = math.deg(math.atan(-dir.y, math.max(horiz, 1e-4)))
    local wantPitch = math.deg(math.atan(origin.y - gy, cfg.aimDist * S))
    if active and t > cfg.fireStart - 0.25 and t < cfg.fireEnd then
        c.breathAim = Clamp((c.breathAim or 0) + (wantPitch - curPitch) * 5.0 * dt, -40, 40)
    end

    -- 落点：与地面平面求交，取不到就用最大射程
    local len = cfg.maxLen * S
    if dir.y < -0.02 then len = math.min(len, (origin.y - gy) / -dir.y) end
    local hit = origin + dir * len
    local hitGround = dir.y < -0.02 and len < cfg.maxLen * S - 0.01
    local frontQ = Quaternion(Vector3.FORWARD, dir)

    -- 地面法阵：龙胸下方，沿朝向略前
    local chest = self.rig.bones.chest.worldPosition
    local gp = Vector3(chest.x, c:GroundHeight(chest.x, chest.z) + 0.035, chest.z) + fwd * ((cfg.style == 1) and 1.2 or 0.6) * S
    local spinBase = c.time
    local g = self.ground
    g.node.position = gp
    g.node.rotation = Quaternion(L.yaw, Vector3.UP) * Quaternion(90, Vector3.RIGHT)
    g.node.scale = Vector3(g.size, g.size, 1)

    local pulse = 0.5 + 0.5 * math.sin(c.time * 9.0)
    if cfg.style == 0 then
        local inT = Window(t, 0.2, cfg.fireEnd + 0.2, 0.35, 0.5) * m
        local reveal = Smooth((t - 0.2) / 0.7)
        SetRune(g, inT * 0.9, reveal, spinBase * 0.25, -spinBase * 0.4, 0.3 * fire * pulse, 2.0)
        local r = self.runes[1]
        r.node.position = origin + dir * r.dist
        r.node.rotation = frontQ
        local sz = r.size * (1.0 + 0.08 * fire * math.sin(c.time * 20.0))
        r.node.scale = Vector3(sz, sz, 1)
        SetRune(r, Window(t, 0.3, cfg.fireEnd + 0.1, 0.3, 0.4) * m, Smooth((t - 0.3) / 0.55),
            spinBase * 1.2, -spinBase * 2.0, fire * (0.6 + 0.4 * pulse), 2.6 + 1.2 * fire)
    else
        local inT = Window(t, 0.0, cfg.fireEnd + 0.3, 0.4, 0.6) * m
        SetRune(g, inT, Smooth(t / 0.9), spinBase * 0.15, -spinBase * 0.22, 0.25 + 0.75 * fire * pulse, 2.2)
        for i, r in ipairs(self.runes) do
            local t0 = 0.45 + 0.32 * (i - 1)
            r.node.position = origin + dir * r.dist
            local sgn = (i % 2 == 0) and -1 or 1
            r.node.rotation = frontQ
            local sz = r.size * (1.0 + 0.06 * fire * math.sin(c.time * 16.0 + i))
            r.node.scale = Vector3(sz, sz, 1)
            SetRune(r, Window(t, t0, cfg.fireEnd + 0.15 * i, 0.3, 0.45) * m, Smooth((t - t0) / 0.45),
                sgn * spinBase * (0.9 + 0.3 * i), -sgn * spinBase * 1.4, fire * (0.5 + 0.5 * pulse), 2.4 + 1.6 * fire)
        end
    end

    -- 粒子发射器跟随口部 / 落点
    self.stream.node.position = origin + dir * 0.2 * S
    self.stream.node.rotation = frontQ
    SetEmit(self.stream, fire > 0.5)
    if cfg.style == 0 then
        self.sparks.node.position = origin + dir * 0.2 * S
        self.sparks.node.rotation = frontQ
        SetEmit(self.sparks, fire > 0.5)
        self.impactFx.node.position = Vector3(hit.x, gy + 0.2 * S, hit.z)
        SetEmit(self.impactFx, fire > 0.5 and hitGround and t > cfg.fireStart + 0.25)
    else
        self.impactFx.node.position = Vector3(hit.x, gy + 0.1, hit.z)
        self.sparks.node.position = Vector3(hit.x, gy + 0.3 * S, hit.z)
        SetEmit(self.impactFx, fire > 0.5 and hitGround)
        SetEmit(self.sparks, fire > 0.5 and hitGround)
        -- 光束：从口部伸向落点（0.15 秒内射出）
        local ext = Smooth((t - cfg.fireStart) / 0.15)
        local bl = math.max(0.05, len * ext)
        local flick = 0.92 + 0.08 * math.sin(c.time * 47.0) + 0.04 * math.sin(c.time * 83.0)
        for idx, bm in ipairs({ self.beamOuter, self.beamCore }) do
            if fire > 0.002 then
                if not bm.node.enabled then bm.node.enabled = true end
                local w = ((idx == 1) and 1.25 or 0.42) * S * (0.6 + 0.4 * fire) * flick
                bm.node.position = origin + dir * (bl * 0.5)
                bm.node.rotation = Quaternion(Vector3.UP, dir)
                bm.node.scale = Vector3(w, bl, w)
                SetF(bm.mat, "fade", fire)
                SetF(bm.mat, "scroll", c.time)
                SetF(bm.mat, "intensity", (idx == 1) and 2.6 or 4.5)
            elseif bm.node.enabled then
                bm.node.enabled = false
            end
        end
    end

    -- 冲击环
    self.ringTimer = self.ringTimer - dt
    local spawnEvery = (cfg.style == 1) and 0.2 or 0.42
    if fire > 0.5 and hitGround and self.ringTimer <= 0 then
        self.ringTimer = spawnEvery
        for _, r in ipairs(self.rings) do
            if r.age >= 1.0 then
                r.age = 0.0
                r.pos = Vector3(hit.x, gy + 0.05, hit.z)
                break
            end
        end
    end
    local ringLife = (cfg.style == 1) and 0.75 or 1.1
    local ringSize = ((cfg.style == 1) and 9.0 or 6.0) * S
    for i, r in ipairs(self.rings) do
        if r.age < 1.0 then
            r.age = math.min(1.0, r.age + dt / ringLife)
            r.node.position = r.pos
            r.node.scale = Vector3(ringSize, ringSize, 1)
            SetF(r.mat, "ring_r", 0.08 + 0.9 * (1 - (1 - r.age) ^ 2.2))
            SetRune(r, (1 - r.age) * m, 1, c.time + i, 0, 0, (cfg.style == 1) and 3.5 or 2.4)
        else
            SetRune(r, 0, 0, 0, 0, 0, 0)
        end
    end

    -- 冰刺（中号）
    if self.ice ~= nil then
        local grow = active and Smooth((t - cfg.fireStart - 0.35) / 0.5) or 0
        local melt = Smooth((t - cfg.fireEnd - 0.1) / 0.7)
        if self.iceCenter == nil or (active and t < cfg.fireEnd) then
            self.iceCenter = Vector3(hit.x, gy, hit.z)
        end
        for _, s in ipairs(self.ice) do
            local k2 = Smooth((grow * 1.4 - s.delay)) * (1 - Smooth(melt * 1.3 - s.delay)) * m
            if k2 > 0.01 and hitGround then
                s.node.enabled = true
                local dx, dz = math.cos(s.a), math.sin(s.a)
                local base = self.iceCenter + Vector3(dx * s.r, 0, dz * s.r)
                local h = s.h * k2
                -- 向外倾斜：绕切线方向转 tilt，再绕自身竖轴随机转一下
                local tilt = Quaternion(s.tilt, Vector3(-dz, 0, dx))
                s.node.rotation = tilt * Quaternion(math.deg(s.a) * 2.0, Vector3.UP)
                s.node.position = base + tilt * Vector3(0, h * 0.5, 0)
                s.node.scale = Vector3(s.w, h, s.w)
            elseif s.node.enabled then
                s.node.enabled = false
            end
        end
    end

    -- 光点与汇聚星屑
    local bb = self.bb
    local charge = (cfg.style == 1) and Window(t, 0.3, cfg.fireStart + 0.1, 0.4, 0.2) or Window(t, 0.25, cfg.fireStart, 0.4, 0.15)
    local glowK = math.max(charge * Smooth((t - 0.2) / math.max(0.3, cfg.fireStart - 0.2)), fire)
    local glowC = (cfg.style == 1) and Color(1.0, 0.8, 0.95, 1) or Color(0.7, 0.9, 1.0, 1)
    local fl = 0.85 + 0.15 * math.sin(c.time * 31.0)
    Flare(bb, 0, origin + dir * 0.25 * S, (0.8 + 1.4 * glowK) * S * fl, Color(glowC.r, glowC.g, glowC.b, glowK * m))
    local hk = hitGround and fire or 0
    Flare(bb, 1, Vector3(hit.x, gy + 0.4 * S, hit.z), ((cfg.style == 1) and 5.0 or 3.2) * S * fl * hk,
        Color(glowC.r, glowC.g, glowC.b, hk))
    for i, mo in ipairs(self.motes) do
        local idx = 1 + i
        local ct = t - 0.3
        local on = (cfg.style == 1) and ct > 0 and t < cfg.fireStart + 0.05
        if on then
            local ph = ((ct + mo.off) % mo.dur) / mo.dur
            local p = ph ^ 1.6
            local rad = mo.r * (1 - p)
            local ang = mo.a + p * math.pi * 3.0
            local side = Vector3(dir.z, 0, -dir.x)
            if side:LengthSquared() < 1e-4 then side = Vector3.RIGHT end
            side = side:Normalized()
            local up = dir:CrossProduct(side)
            local pos = origin + dir * ((1 - p) * 2.5 * S) + (side * math.cos(ang) + up * math.sin(ang)) * rad
                + Vector3(0, mo.up * (1 - p), 0)
            local a = Smooth(ph / 0.2) * (1 - Smooth((ph - 0.85) / 0.15)) * m * Smooth(ct / 0.4)
            local col = mo.gold and Color(1.0, 0.75, 0.35, a) or Color(0.7, 0.45, 1.0, a)
            Flare(bb, idx, pos, (0.18 + 0.22 * (1 - p)) * S, col)
        else
            bb:GetBillboard(idx).enabled = false
        end
    end
    bb:Commit()

    -- 灯光
    local ml = self.mouthLight
    ml.node.enabled = glowK > 0.01
    ml.node.position = origin + dir * 0.6 * S
    ml.light.brightness = ((cfg.style == 1) and 60 or 40) * glowK * fl
    local il = self.impactLight
    il.node.enabled = hk > 0.01
    il.node.position = Vector3(hit.x, gy + 1.0 * S, hit.z)
    il.light.brightness = ((cfg.style == 1) and 120 or 60) * hk * fl

    -- 镜头震动强度（DragonTest 读取）
    local target = (cfg.style == 1) and (0.2 * Window(t, cfg.fireStart, cfg.fireEnd, 0.05, 0.3) +
        0.5 * math.exp(-math.max(0, t - cfg.fireStart) * 4.0) * (t > cfg.fireStart and 1 or 0)) or 0.07 * fire
    self.shake = target * m
end

-- 关掉所有可见元素（粒子发射器只停止发射，已有粒子自然消散）
function B:HideAll()
    self.hidden = true
    self.shake = 0
    for _, r in ipairs(self.runes) do SetRune(r, 0, 0, 0, 0, 0, 0) end
    SetRune(self.ground, 0, 0, 0, 0, 0, 0)
    for _, r in ipairs(self.rings) do r.age = 1.0; SetRune(r, 0, 0, 0, 0, 0, 0) end
    for _, e in ipairs({ self.stream, self.sparks, self.impactFx }) do SetEmit(e, false) end
    if self.beamOuter ~= nil then self.beamOuter.node.enabled = false; self.beamCore.node.enabled = false end
    if self.ice ~= nil then for _, s in ipairs(self.ice) do s.node.enabled = false end end
    self.iceCenter = nil
    for i = 0, 1 + self.nMotes do self.bb:GetBillboard(i).enabled = false end
    self.bb:Commit()
    self.mouthLight.node.enabled = false
    self.impactLight.node.enabled = false
end

return M
