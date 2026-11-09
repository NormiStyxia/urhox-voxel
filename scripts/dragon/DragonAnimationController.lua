-- ====================================================================
-- DragonAnimationController.lua — 体素巨龙动画控制器（状态机 + 分层姿态 + IK）。
--
-- 三层控制，互不覆盖：
--   1. 全局移动层（loco）：root 节点的世界位置 / 偏航；飞行时的高度、速度、坡度转弯
--   2. 身体姿态层：body 节点（COM 处）的俯仰 / 侧倾 / 升降——步态重心、起跳蓄力、
--      飞行姿态、落地缓冲都在这一层
--   3. 关节动画层：各状态生成 FK 姿态表（DragonPose），按状态权重交叉淡化，
--      之后四肢 IK 按地面权重覆盖腿部，最后更新翼膜插值薄片
--
-- 状态机（数据驱动，见 STATES 表）：
--   IDLE WALK TURN SPREAD_WINGS TAKEOFF FLY GLIDE LAND ROAR
--   切换时新状态权重在 blendIn 秒内升到 1，旧状态继续以自己的时间轴播放并淡出，
--   姿势不会突变归零。
--
-- 飞行不是空气动力学仿真：竖直方向用「重力 + 升力指令 + 振翅相位升力波动」的
-- 简化模型，水平用坡度转弯近似（偏航角速度 = g·tan(坡度)/速度）。振翅下拍时
-- 升力增大，所以身体会随下拍上浮，动作和位移是联动的。
-- ====================================================================

local Pose = require("dragon.DragonPose")
local Poses = require("dragon.DragonPoses")
local IK = require("dragon.DragonIK")
local Gait = require("dragon.DragonGait")
local Rig = require("dragon.DragonRig")

---@class DragonAnimationController
---@field rig DragonRig
---@field world VoxelPhysicsWorld
---@field params table
---@field input table
---@field loco table
---@field layers table[]
---@field state string
---@field stateT number
---@field gait table
---@field chains table<string, table>
---@field demo table|nil
---@field jointTest table
---@field roarChest number|nil
---@field turnTarget number|nil
---@field turnRequest number|nil
---@field touchT number|nil
---@field jumped boolean|nil
---@field roaring boolean|nil
local C = {}
C.__index = C

local G = 9.8
local CRUISE_ALT = 6.0

local function Clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
local function Lerp(a, b, t) return a + (b - a) * t end
local function Smooth(t) t = Clamp(t, 0, 1) return t * t * (3 - 2 * t) end
local function Approach(x, target, rate, dt)
    local d = target - x
    local m = rate * dt
    if d > m then return x + m elseif d < -m then return x - m end
    return target
end
local function Damp(x, target, k, dt) return x + (target - x) * (1 - math.exp(-k * dt)) end
local function WrapDeg(a)
    a = a % 360
    if a > 180 then a = a - 360 end
    return a
end

-- 关键帧插值：keys = { {t, {k=v,...}}, ... }，段内 smoothstep
local function Keys(keys, t)
    if t <= keys[1][1] then return keys[1][2] end
    for i = 1, #keys - 1 do
        local a, b = keys[i], keys[i + 1]
        if t <= b[1] then
            local s = Smooth((t - a[1]) / (b[1] - a[1]))
            local out = {}
            for k, v in pairs(a[2]) do out[k] = Lerp(v, b[2][k] or v, s) end
            for k, v in pairs(b[2]) do if out[k] == nil then out[k] = v * s end end
            return out
        end
    end
    return keys[#keys][2]
end

-- ---------------------------------------------------------------- 构造
---@param rig DragonRig
---@param world VoxelPhysicsWorld
function C.New(rig, world)
    local self = setmetatable({}, C)
    self.rig, self.world = rig, world
    self.params = {
        playback = 1.0,   -- 动画播放速度
        walkSpeed = 1.6,  -- 步行速度 m/s
        flapHz = 1.05,    -- 振翅频率
        amp = 1.0,        -- 动作幅度
        flySpeed = 8.0,   -- 巡航速度
        turnRate = 55.0,  -- 原地转身角速度 度/秒
    }
    self.input = { move = 0, turn = 0, climb = 0 }
    self.layers = {}
    self.state = nil
    self.time = 0.0
    self.paused = false
    self.stepFrames = 0
    -- 全局移动
    self.loco = { pos = Vector3(0, 0, 0), yaw = 0.0, speed = 0.0, yawRate = 0.0, alt = 0.0, vy = 0.0,
        bank = 0.0, pitch = 0.0, altTarget = 0.0, airborne = false }
    -- 次级运动
    self.wingDeploy, self.wingDeployTarget = 0.0, 0.0
    self.wingOpenPose = Poses.WING_DISPLAY
    self.flapPhase = 0.0
    self.ikW, self.ikTarget = 1.0, 1.0
    self.ikFront, self.ikFrontTarget = 1.0, 1.0 -- 前肢单独的离地权重（起跳时前脚先离地）
    self.look = { yaw = 0, pitch = 0, tyaw = 0, tpitch = 0, timer = 2.0 }
    self.breath = 0.0
    self.impact = 0.0
    self.mask = "all"
    self.jointTest = { enabled = false, joint = "neck2", x = 0, y = 0, z = 0 }
    self.demo = nil

    -- 腿链
    local P = rig.pivots
    self.chains = {}
    local feet = {}
    for _, side in ipairs({ "_R", "_L" }) do
        local sx = (side == "_R") and 1 or -1
        local front = IK.NewChain(rig, { "armU" .. side, "armL" .. side, "hand" .. side },
            { 0.48 * sx, 0.0, 1.02 }, "back", sx)
        local hind = IK.NewChain(rig, { "legU" .. side, "legL" .. side, "legM" .. side, "foot" .. side },
            { 0.92 * sx, 0.0, -1.12 }, "front", sx)
        self.chains["F" .. side] = front
        self.chains["H" .. side] = hind
        feet[#feet + 1] = { key = "F" .. ((sx > 0) and "R" or "L"), chain = front, side = sx }
        feet[#feet + 1] = { key = "H" .. ((sx > 0) and "R" or "L"), chain = hind, side = sx }
    end
    self.gait = Gait.New(feet)
    self.groundFn = function(x, z) return self:GroundHeight(x, z) end
    Gait.Reset(self.gait, self.loco.pos, self.loco.yaw, self.groundFn)

    -- 胸腔呼吸缩放：以骨骼枢轴为中心缩放体素部件
    local chest = rig.parts.chest
    if chest ~= nil then self.chestVolOffset = chest.node.position end

    self:SetState("IDLE", 0.0)
    return self
end

-- 把龙放到指定位置 / 朝向（落地、四脚重新落在静止足位）
function C:Teleport(pos, yaw)
    local L = self.loco
    L.pos, L.yaw, L.speed, L.yawRate, L.alt, L.vy, L.airborne = Vector3(pos.x, 0, pos.z), yaw, 0, 0, 0, 0, false
    Gait.Reset(self.gait, L.pos, L.yaw, self.groundFn)
end

function C:GroundHeight(x, z)
    local hit = self.world:RaycastSingle(Ray(Vector3(x, 30.0, z), Vector3(0, -1, 0)), 60.0)
    if hit ~= nil and hit.hit then return hit.position.y end
    return 0.0
end

-- ---------------------------------------------------------------- 姿态片段
-- 翅膀分级展开：d=0 收翼，d=1 目标展开姿态。翼根先动，再近端翼骨，最后翼尖与翼膜；
-- d 回落时顺序自然反过来（翼尖先收）。
function C:GroundWing(d, open)
    open = open or self.wingOpenPose
    local F = Poses.WING_FOLD
    local pr = Smooth(d / 0.4)
    local pm = Smooth((d - 0.2) / 0.45)
    local pt = Smooth((d - 0.45) / 0.5)
    return {
        elev = Lerp(F.elev, open.elev, pr), sweep = Lerp(F.sweep, open.sweep, pr), twist = Lerp(F.twist, open.twist, pr),
        elbow = Lerp(F.elbow, open.elbow, pm),
        wrist = Lerp(F.wrist, open.wrist, pt), fan = Lerp(F.fan, open.fan, pt), curl = Lerp(F.curl, open.curl or 0, pt),
        fold2 = Lerp(F.fold2 or 0, open.fold2 or 0, Smooth((d - 0.3) / 0.5)),
    }
end

-- 振翅周期：φ∈[0,1)，下拍 0..0.42（快、有力、完全展开、前缘下压），
-- 回收 0.42..1（肘腕收拢减小翼面、前缘上翻、翼尖滞后）
function C.FlapWing(phi, amp, brake)
    brake = brake or 0
    local w = {}
    local up, down = 52 * amp, -40 * amp
    if phi < 0.42 then
        local s = Smooth(phi / 0.42)
        w.elev = Lerp(up, down, s)
        w.twist = -9 * math.sin(math.pi * s) * amp
        w.elbow = -6
        w.wrist = 4
        w.fan = 1.0
        w.curl = Lerp(-7, 6, s) * amp
        w.sweep = -4 - 18 * brake
    else
        local s = Smooth((phi - 0.42) / 0.58)
        local m = math.sin(math.pi * s)
        w.elev = Lerp(down, up, s)
        w.twist = 12 * m * amp
        w.elbow = -6 - 40 * m * amp
        w.wrist = 4 + 36 * m * amp
        w.fan = 1.0 - 0.32 * m
        w.curl = Lerp(6, -7, s) * amp + 12 * m
        w.sweep = Lerp(-4, 6, m) - 18 * brake
    end
    -- 翼尖（一指）相位滞后的独立运动
    w.tip = -10 * math.cos(2 * math.pi * phi - 0.9) * amp
    return w
end

-- 下拍升力信号（均值约 0）
local function FlapLift(phi)
    if phi < 0.42 then return math.sin(math.pi * phi / 0.42) * 1.3 - 0.35 end
    return -0.55 + 0.2 * math.sin(math.pi * (phi - 0.42) / 0.58)
end

-- 飞行收腿
local function TuckLegs(p, k)
    Pose.SetSym(p, "armU", 50 * k, 0, 6 * k)
    Pose.SetSym(p, "armL", -95 * k, 0, 0)
    Pose.SetSym(p, "hand", 70 * k, 0, 0)
    Pose.SetSym(p, "legU", 62 * k, 0, 4 * k)
    Pose.SetSym(p, "legL", 18 * k, 0, 0)
    Pose.SetSym(p, "legM", -42 * k, 0, 0)
    Pose.SetSym(p, "foot", 55 * k, 0, 0)
end

-- 降落伸腿（前伸、准备着地）
local function ReachLegs(p, k)
    Pose.SetSym(p, "armU", -28 * k, 0, 4 * k)
    Pose.SetSym(p, "armL", 14 * k, 0, 0)
    Pose.SetSym(p, "hand", 12 * k, 0, 0)
    Pose.SetSym(p, "legU", -18 * k, 0, 3 * k)
    Pose.SetSym(p, "legL", 10 * k, 0, 0)
    Pose.SetSym(p, "legM", -8 * k, 0, 0)
    Pose.SetSym(p, "foot", 18 * k, 0, 0)
end

-- 飞行时的颈 / 尾 / 身体：颈部前伸、头抬平看前方、尾巴抬平当舵
function C:FlightBody(p, phi, ext)
    local bank = self.loco.bank
    Poses.Neck(p, { pitch = 58 * ext, curve = -4 * ext, yaw = -bank * 0.35, headPitch = -52 * ext + 3 * math.sin(2 * math.pi * phi),
        headYaw = 0, jaw = 0 })
    Poses.Tail(p, { pitch = 34 * ext, yaw = bank * 0.25, waveAmp = 2.5, wavePhase = 2 * math.pi * phi, lag = 0.5,
        liftAmp = 3 * ext })
    -- 胸腔随下拍收缩，躯干微弯
    local pump = math.sin(2 * math.pi * phi)
    Pose.Set(p, "chest", -2 * pump * ext, 0, 0)
    Pose.Set(p, "waist", 1.5 * pump * ext, 0, 0)
end

-- ---------------------------------------------------------------- 状态定义
-- 每个状态：blendIn 进入淡入时长；ground 是否落地（IK）；enter / logic（只对当前状态执行）；
-- pose(self, t) 生成姿态（淡出中的旧状态也会继续调用）
local STATES = {}
C.STATES = STATES
C.STATE_ORDER = { "IDLE", "WALK", "TURN", "SPREAD_WINGS", "TAKEOFF", "FLY", "GLIDE", "LAND", "ROAR" }
C.STATE_NAMES = {
    IDLE = "待机", WALK = "行走", TURN = "转身", SPREAD_WINGS = "展翼", TAKEOFF = "起飞",
    FLY = "飞行", GLIDE = "滑翔", LAND = "降落", ROAR = "咆哮",
}

-- 待机：呼吸、颈部小幅自然运动、偶尔观察环境、尾巴轻摆、翅膀收拢
STATES.IDLE = {
    blendIn = 0.6, ground = true,
    enter = function(self) self.wingDeployTarget = 0.0 end,
    logic = function(self, dt)
        local L = self.loco
        L.speed = Approach(L.speed, 0, 3.0, dt)
        L.yawRate = Damp(L.yawRate, 0, 6, dt)
    end,
    pose = function(self, t)
        local p = Pose.New()
        local lk = self.look
        local br = math.sin(2 * math.pi * t / 3.8)
        Poses.Neck(p, { pitch = 2 + 3 * math.sin(t * 0.55) + lk.pitch * 0.5, yaw = lk.yaw * 0.7, curve = 2,
            headPitch = -2 - 2 * math.sin(t * 0.55) + lk.pitch * 0.5, headYaw = lk.yaw * 0.3, jaw = 1.5 + 1.5 * br })
        Poses.Tail(p, { yaw = 0, pitch = 0, waveAmp = 3.2, wavePhase = t * 1.05, lag = 0.5, liftAmp = 1.5 })
        local w = self:GroundWing(self.wingDeploy)
        w.elev = w.elev + 1.2 * br
        Poses.Wings(p, w)
        Pose.Set(p, "chest", -0.8 * br, 0, 0)
        Pose.SetBody(p, 0.4 * br, 0, 0, 0, 0.012 * br, 0)
        return p
    end,
}

-- 四足行走
STATES.WALK = {
    blendIn = 0.5, ground = true,
    enter = function(self) self.wingDeployTarget = 0.0 end,
    logic = function(self, dt)
        local L, inp = self.loco, self.input
        local target = self.params.walkSpeed * Clamp(1.0 + inp.move * 0.6, 0.25, 1.9)
        L.speed = Approach(L.speed, target, 1.4, dt)
        -- 键盘转向；无输入时离场地中心太远就慢慢绕回
        local steer = inp.turn * 38
        if inp.turn == 0 then
            local d = L.pos:Length()
            if d > 11 then
                local toC = math.deg(math.atan(-L.pos.x, -L.pos.z))
                steer = Clamp(WrapDeg(toC - L.yaw), -1, 1) * 22
            end
        end
        L.yawRate = Damp(L.yawRate, steer, 3.0, dt)
    end,
    pose = function(self, t)
        local p = Pose.New()
        local ph = 2 * math.pi * self.gait.phase
        local k = Clamp(self.loco.speed / 1.6, 0, 1.4) * self.params.amp
        local yr = self.loco.yawRate
        Poses.Neck(p, { pitch = 7 + 2 * math.sin(2 * ph) * k, yaw = -3 * math.sin(ph) * k + yr * 0.35, curve = 1,
            headPitch = -6 - 2 * math.sin(2 * ph) * k, headYaw = yr * 0.15, jaw = 1 })
        Poses.Tail(p, { yaw = -yr * 0.4, pitch = 3 * k, waveAmp = 6.5 * k, wavePhase = ph + 0.6, lag = 0.62, liftAmp = 2 })
        local w = self:GroundWing(self.wingDeploy)
        w.elev = w.elev + 2.0 * math.sin(2 * ph) * k
        Poses.Wings(p, w)
        -- 脊柱反向扭转：骨盆随后腿、胸随前腿
        Pose.Set(p, "waist", 0, 4 * math.sin(ph) * k, 1.5 * math.sin(ph) * k)
        Pose.Set(p, "chest", 0, -3.5 * math.sin(ph) * k, -1.5 * math.sin(ph) * k)
        Pose.Set(p, "pelvis", 0, 2 * math.sin(ph) * k, 0)
        Pose.SetBody(p, 1.0 * k, 0, 0, 0, -0.07 * math.min(k, 1.0), 0)
        return p
    end,
}

-- 原地转身：头先转、身体随后、尾巴滞后，脚由步态规划重新落点
STATES.TURN = {
    blendIn = 0.4, ground = true,
    enter = function(self)
        self.wingDeployTarget = 0.0
        self.turnTarget = WrapDeg(self.loco.yaw + (self.turnRequest or 90))
    end,
    logic = function(self, dt, t)
        local L = self.loco
        L.speed = Approach(L.speed, 0, 2.0, dt)
        local rem = WrapDeg(self.turnTarget - L.yaw)
        local rate = 0
        if t > 0.35 then -- 头先转 0.35 秒，身体再跟上
            rate = Clamp(rem * 2.2, -self.params.turnRate, self.params.turnRate)
        end
        L.yawRate = Damp(L.yawRate, rate, 5.0, dt)
        if math.abs(rem) < 1.5 and math.abs(L.yawRate) < 4 then
            self:Request(self.afterTurn or "IDLE")
        end
    end,
    pose = function(self, t)
        local p = Pose.New()
        local rem = WrapDeg((self.turnTarget or self.loco.yaw) - self.loco.yaw)
        local lead = Clamp(rem, -40, 40) * Smooth(t / 0.3)
        local yr = self.loco.yawRate
        Poses.Neck(p, { pitch = 4, yaw = lead * 0.75, curve = 1, headPitch = -3, headYaw = lead * 0.3 })
        Poses.Tail(p, { yaw = -yr * 0.55, waveAmp = 3, wavePhase = t * 1.6, lag = 0.6 })
        Poses.Wings(p, self:GroundWing(self.wingDeploy))
        Pose.Set(p, "chest", 0, lead * 0.12, 0)
        Pose.Set(p, "waist", 0, lead * 0.06, 0)
        return p
    end,
}

-- 展翼：翼根 → 近端 → 远端 / 翼尖 → 翼膜，分级展开并保持；切回待机即反向收翼
STATES.SPREAD_WINGS = {
    blendIn = 0.5, ground = true,
    enter = function(self) self.wingDeployTarget = 1.0 end,
    logic = function(self, dt)
        local L = self.loco
        L.speed = Approach(L.speed, 0, 3.0, dt)
        L.yawRate = Damp(L.yawRate, 0, 6, dt)
    end,
    pose = function(self, t)
        local p = Pose.New()
        local d = self.wingDeploy
        local br = math.sin(2 * math.pi * t / 3.2)
        Poses.Neck(p, { pitch = -4 * d + 2 * math.sin(t * 0.5), curve = 3 * d, yaw = 6 * math.sin(t * 0.35),
            headPitch = -6 * d, jaw = 2 })
        Poses.Tail(p, { pitch = 5 * d, waveAmp = 3, wavePhase = t * 1.0, lag = 0.5, liftAmp = 2 })
        local w = self:GroundWing(d)
        w.elev = w.elev + 1.5 * br * d
        w.curl = (w.curl or 0) + 2 * br * d
        Poses.Wings(p, w)
        Pose.Set(p, "chest", -3 * d, 0, 0)
        Pose.SetBody(p, -2.0 * d, 0, 0, 0, 0.0, 0)
        return p
    end,
}

-- 起飞：下蹲蓄力 → 起跳 → 翅膀迅速展开 → 第一次有力下拍 → 收腿 → 过渡到飞行
local TAKEOFF_T, JUMP_T, FLAP_T = 2.6, 0.62, 0.66
STATES.TAKEOFF = {
    blendIn = 0.35, ground = true,
    enter = function(self)
        self.wingDeployTarget = 1.0
        self.wingOpenPose = { elev = 58, sweep = 6, twist = -6, elbow = -8, wrist = 10, fan = 0.92, curl = 0 }
        self.jumped = false
    end,
    logic = function(self, dt, t)
        local L = self.loco
        -- 起跳离地：腿伸到接近全长（膝 / 肘快伸直）时释放 IK，前脚先离地、后腿最后蹬离，
        -- 避免伸直瞬间关节角剧变
        local stretchF, stretchH = 0, 0
        for _, f in ipairs(self.gait.feet) do
            local st = f.chain.stretch or 0
            if f.front then stretchF = math.max(stretchF, st) else stretchH = math.max(stretchH, st) end
        end
        if t > JUMP_T - 0.12 and stretchF > 0.8 then self.ikFrontTarget = 0.0 end
        if t < 0.05 then self.ikFrontTarget = 1.0 end
        if t < JUMP_T then
            L.speed = Approach(L.speed, 0, 3, dt)
            L.yawRate = Damp(L.yawRate, 0, 6, dt)
            self.ikTarget = 1.0
        else
            if not self.jumped then
                self.jumped = true
                L.airborne = true
                L.vy = 0.8
                L.altTarget = CRUISE_ALT
                self.flapPhase = 0.98
            end
            -- 蹬地：0.16 秒内后腿持续发力（加速度而不是瞬时冲量）
            if t < JUMP_T + 0.2 then
                L.vy = L.vy + 18.0 * dt
                L.speed = L.speed + 12.0 * dt
            end
            L.speed = Approach(L.speed, self.params.flySpeed * 0.7, 2.2, dt)
            if stretchH > 0.86 or t > JUMP_T + 0.3 then self.ikTarget = 0.0 end
        end
        if t > TAKEOFF_T then self:Request("FLY") end
    end,
    pose = function(self, t)
        local p = Pose.New()
        local k = Keys({
            { 0.0, { dy = 0, pitch = 0, neck = 4, head = -2, tuck = 0, tail = 0 } },
            { 0.5, { dy = -0.36, pitch = 5, neck = 22, head = -18, tuck = 0, tail = 6 } },
            { 0.74, { dy = 0.0, pitch = -10, neck = 30, head = -30, tuck = 0, tail = 14 } },
            { 1.3, { dy = 0, pitch = -6, neck = 48, head = -44, tuck = 0.85, tail = 26 } },
            { 2.6, { dy = 0, pitch = -3, neck = 56, head = -50, tuck = 1.0, tail = 32 } },
        }, t)
        Poses.Neck(p, { pitch = k.neck, curve = -2, headPitch = k.head })
        Poses.Tail(p, { pitch = k.tail, waveAmp = 3, wavePhase = t * 3, lag = 0.5, liftAmp = 3 })
        -- 翅膀：蓄力时分级展开到上举位，起跳后切入振翅
        local ground = self:GroundWing(self.wingDeploy)
        local flapW = Smooth((t - FLAP_T + 0.05) / 0.12)
        local w = (flapW > 0) and Poses.LerpWing(ground, C.FlapWing(self.flapPhase, self.params.amp * 1.15), flapW) or ground
        Poses.Wings(p, w)
        TuckLegs(p, k.tuck)
        -- 后腿蹬地：起跳瞬间跗关节伸展
        local push = Smooth((t - 0.5) / 0.15) * (1 - Smooth((t - 0.8) / 0.3))
        Pose.AddSym(p, "legM", 18 * push, 0, 0)
        Pose.AddSym(p, "foot", 25 * push, 0, 0)
        Pose.SetBody(p, k.pitch, 0, 0, 0, k.dy, 0)
        return p
    end,
}

-- 稳定飞行：振翅、坡度转弯、爬升 / 下降
STATES.FLY = {
    blendIn = 0.7, ground = false,
    enter = function(self) self.ikTarget = 0.0 end,
    logic = function(self, dt)
        self:FlightLogic(dt, true)
    end,
    pose = function(self, t)
        local p = Pose.New()
        local phi = self.flapPhase
        Poses.Wings(p, C.FlapWing(phi, self.params.amp * (1 + 0.15 * math.max(0, self.input.climb))))
        self:FlightBody(p, phi, 1.0)
        TuckLegs(p, 1.0)
        return p
    end,
}

-- 滑翔：完全展开、固定翼面，翼尖微颤，缓慢下沉
STATES.GLIDE = {
    blendIn = 0.9, ground = false,
    enter = function(self) self.ikTarget = 0.0 end,
    logic = function(self, dt)
        self:FlightLogic(dt, false)
        if self.loco.alt < 2.6 then self:Request("FLY") end
    end,
    pose = function(self, t)
        local p = Pose.New()
        local w = { elev = 7 + 1.5 * math.sin(t * 1.3), sweep = 3, twist = -3, elbow = -2, wrist = 2, fan = 1.0,
            curl = -4 + 1.2 * math.sin(t * 7.0), tip = 1.5 * math.sin(t * 5.3) }
        Poses.Wings(p, w)
        self:FlightBody(p, (t * 0.25) % 1.0, 1.0)
        TuckLegs(p, 1.0)
        return p
    end,
}

-- 降落：减速、仰身制动、伸腿、着地缓冲、收翼
STATES.LAND = {
    blendIn = 0.6, ground = false,
    enter = function(self)
        self.touchT = nil
        self.ikTarget = 0.0
        self.wingOpenPose = Poses.WING_DISPLAY
    end,
    logic = function(self, dt, t)
        local L = self.loco
        if self.touchT == nil then
            L.speed = Approach(L.speed, 0.0, 2.6, dt)
            L.yawRate = Damp(L.yawRate, 0, 2, dt)
            L.bank = Damp(L.bank, 0, 3, dt)
            -- 下降速度随高度递减
            L.altTarget = 0.0
            local sink = -Clamp(L.alt * 0.9, 0.7, 2.8)
            L.vy = Damp(L.vy, sink, 3.0, dt)
            L.alt = L.alt + L.vy * dt
            self.flapPhase = (self.flapPhase + dt * self.params.flapHz * 0.95) % 1.0
            self.ikTarget = (L.alt < 0.9) and 1.0 or 0.0
            if L.alt <= 0.0 then
                L.alt, L.vy, L.airborne = 0.0, 0.0, false
                self.touchT = t
                self.impact = 1.0
                Gait.Reset(self.gait, L.pos, L.yaw, self.groundFn)
                self.wingDeploy, self.wingDeployTarget = 1.0, 0.0
            end
        else
            L.speed = Approach(L.speed, 0, 3.0, dt)
            self.ikTarget = 1.0
            if t - self.touchT > 1.9 then self:Request("IDLE") end
        end
    end,
    pose = function(self, t)
        local p = Pose.New()
        local L = self.loco
        local touched = self.touchT ~= nil
        local since = touched and (t - self.touchT) or 0
        local flare = touched and (1 - Smooth(since / 0.6)) or Smooth(t / 1.2)
        -- 翅膀：空中前推制动扑翼；着地后转为张开再分级收拢
        local flapW = C.FlapWing(self.flapPhase, self.params.amp * 1.1, 1.0)
        local w
        if touched then
            w = Poses.LerpWing(flapW, self:GroundWing(self.wingDeploy), Smooth(since / 0.35))
        else
            w = flapW
        end
        Poses.Wings(p, w)
        Poses.Neck(p, { pitch = Lerp(50, 18, flare) * (touched and (1 - Smooth(since / 0.8)) or 1) + 4,
            curve = 3 * flare, headPitch = -40 * (touched and (1 - Smooth(since / 0.8)) or 1) + 6 * flare })
        Poses.Tail(p, { pitch = 20 * (touched and (1 - Smooth(since / 0.8)) or 1), waveAmp = 3, wavePhase = t * 2, lag = 0.5 })
        if not touched then
            local reach = Smooth((t - 0.4) / 1.0)
            TuckLegs(p, 1 - reach)
            local q = Pose.New()
            ReachLegs(q, reach)
            for k2, v in pairs(q.j) do Pose.AddTo(p, k2, v[1], v[2], v[3]) end
        end
        Pose.SetBody(p, -22 * flare, 0, 0, 0, 0, 0)
        return p
    end,
}

-- 咆哮：抬头、张颚、颈部伸展、胸腔扩张（预留喉部 / 口腔挂点）
STATES.ROAR = {
    blendIn = 0.35, ground = true,
    enter = function(self) self.wingDeployTarget = 0.0 end,
    logic = function(self, dt, t)
        local L = self.loco
        L.speed = Approach(L.speed, 0, 3.0, dt)
        L.yawRate = Damp(L.yawRate, 0, 6, dt)
        self.wingDeployTarget = (t > 0.6 and t < 2.5) and 0.45 or 0.0
        self.roaring = (t > 0.8 and t < 2.4)
        if t > 3.3 then self:Request("IDLE") end
    end,
    pose = function(self, t)
        local p = Pose.New()
        local k = Keys({
            { 0.0, { neck = 2, curve = 2, head = -2, jaw = 1, chest = 0, pitch = 0, dy = 0 } },
            { 0.65, { neck = 20, curve = 9, head = 14, jaw = 6, chest = 1, pitch = 3, dy = -0.06 } },
            { 0.95, { neck = -24, curve = -6, head = -22, jaw = 36, chest = 0.6, pitch = -4, dy = -0.02 } },
            { 2.3, { neck = -20, curve = -5, head = -18, jaw = 32, chest = 0.3, pitch = -3.5, dy = -0.02 } },
            { 3.3, { neck = 2, curve = 2, head = -2, jaw = 1, chest = 0, pitch = 0, dy = 0 } },
        }, t)
        local shake = (t > 0.95 and t < 2.3) and 1 or 0
        Poses.Neck(p, { pitch = k.neck, curve = k.curve, headPitch = k.head + 1.5 * math.sin(t * 31) * shake,
            headYaw = 2.5 * math.sin(t * 23) * shake, yaw = 5 * math.sin(t * 2.1) * shake,
            jaw = k.jaw + 3 * math.sin(t * 27) * shake })
        Poses.Tail(p, { pitch = 6 * k.chest, waveAmp = 5 + 4 * shake, wavePhase = t * 3.2, lag = 0.55, liftAmp = 4 * k.chest })
        local w = self:GroundWing(self.wingDeploy)
        Poses.Wings(p, w)
        Pose.Set(p, "chest", -4 * k.chest, 0, 0)
        Pose.SetBody(p, k.pitch, 0, 0, 0, k.dy, 0)
        self.roarChest = k.chest
        return p
    end,
}

-- ---------------------------------------------------------------- 飞行逻辑
-- flapping=true：振翅维持高度 / 爬升；false：滑翔下沉
function C:FlightLogic(dt, flapping)
    local L, inp, prm = self.loco, self.input, self.params
    -- 速度
    local vTarget = prm.flySpeed * Clamp(1 + inp.move * 0.45, 0.45, 1.6)
    if not flapping then vTarget = math.max(5.5, L.speed - 0.4) end
    L.speed = Approach(L.speed, vTarget, flapping and 2.0 or 0.6, dt)
    -- 坡度转弯；无输入时远离场地就绕回
    local bankTarget = inp.turn * 34
    if inp.turn == 0 then
        local d = L.pos:Length()
        if d > 22 then
            local toC = math.deg(math.atan(-L.pos.x, -L.pos.z))
            bankTarget = Clamp(WrapDeg(toC - L.yaw) / 30, -1, 1) * 26
        end
    end
    L.bank = Damp(L.bank, bankTarget, 2.2, dt)
    L.yawRate = math.deg(G * math.tan(math.rad(L.bank)) / math.max(L.speed, 2.0))
    -- 高度
    if flapping then
        L.altTarget = Clamp(L.altTarget + inp.climb * 3.2 * dt, 2.8, 40.0)
    else
        L.altTarget = L.alt - 1.0
    end
    local hz = prm.flapHz * (1 + 0.25 * math.max(0, inp.climb))
    if flapping then self.flapPhase = (self.flapPhase + dt * hz) % 1.0 end
    local cmd = Clamp(G + 2.4 * (L.altTarget - L.alt) - 2.2 * L.vy, 0.0, 2.6 * G)
    if not flapping then cmd = G - 1.1 end
    local wave = flapping and (G * 0.55 * FlapLift(self.flapPhase) * prm.amp) or 0
    L.vy = L.vy + (cmd - G + wave) * dt
    L.alt = L.alt + L.vy * dt
    if L.alt < 0.5 then L.alt, L.vy = 0.5, math.max(L.vy, 0) end
    L.pitch = Damp(L.pitch, Clamp(-L.vy * 2.6, -14, 14), 3.0, dt)
end

-- ---------------------------------------------------------------- 状态切换
function C:SetState(name, blend)
    local def = STATES[name]
    if def == nil then return end
    self.prevState = self.state
    self.state = name
    self.stateT = 0.0
    -- 每次切换都新建一层（旧层带着自己的时间轴淡出，同名状态重入也不会跳帧）
    local found = { name = name, w = 0.0, t = 0.0 }
    self.layers[#self.layers + 1] = found
    if #self.layers > 6 then table.remove(self.layers, 1) end
    found.blend = (blend ~= nil) and blend or def.blendIn
    if found.blend <= 0 then
        found.w = 1.0
        self.layers = { found }
    end
    if def.enter then def.enter(self) end
end

-- 外部请求（UI / 键盘 / 演示序列），按当前是否在空中自动插入起飞 / 降落
function C:Request(name, arg)
    local airborne = self.loco.airborne
    local cur = self.state
    if name == "TURN" then self.turnRequest = arg or 90 end
    if airborne then
        if name == "FLY" or name == "GLIDE" then
            if cur ~= "TAKEOFF" or name == "FLY" then self:SetState(name) end
        elseif name == "LAND" or STATES[name].ground then
            if cur ~= "LAND" and cur ~= "TAKEOFF" then self:SetState("LAND") end
        end
        return
    end
    if name == "FLY" or name == "GLIDE" then
        if cur ~= "TAKEOFF" then self:SetState("TAKEOFF") end
        return
    end
    if name == "LAND" then return end
    if name == cur and name ~= "TURN" then return end
    self:SetState(name)
end

function C:StartDemo()
    self.demo = {
        list = {
            { "IDLE", 2.5 }, { "ROAR", 3.4 }, { "WALK", 7.0 }, { "TURN", 3.0, 120 }, { "SPREAD_WINGS", 3.5 },
            { "IDLE", 2.5 }, { "TAKEOFF", 2.7 }, { "FLY", 9.0 }, { "GLIDE", 4.0 }, { "FLY", 3.0 }, { "LAND", 6.0 },
            { "IDLE", 3.0 },
        },
        i = 0, t = 1e9,
    }
end

-- ---------------------------------------------------------------- 主更新
function C:Update(rawDt)
    local dt = math.min(rawDt, 0.05) * self.params.playback
    if self.paused then
        if self.stepFrames > 0 then
            self.stepFrames = self.stepFrames - 1
            dt = (1.0 / 30.0) * self.params.playback
        else
            dt = 0.0
        end
    end
    if self.jointTest.enabled then
        self:ApplyJointTest()
        return
    end
    self.time = self.time + dt
    if dt > 0 then self:Step(dt) end
    self:ApplyPose(dt)
end

function C:Step(dt)
    -- 演示序列
    local demo = self.demo
    if demo ~= nil then
        demo.t = demo.t + dt
        local cur = demo.list[demo.i]
        if cur == nil or demo.t >= cur[2] then
            demo.i = demo.i + 1
            local nxt = demo.list[demo.i]
            if nxt == nil then
                self.demo = nil
            else
                demo.t = 0
                self:Request(nxt[1], nxt[3])
            end
        end
    end

    -- 状态逻辑（只有当前状态）
    self.stateT = self.stateT + dt
    local def = STATES[self.state]
    if def.logic then def.logic(self, dt, self.stateT) end

    -- 层权重
    local top = self.layers[#self.layers]
    top.w = math.min(1.0, top.w + dt / math.max(top.blend, 1e-3))
    local rest = 0.0
    for i = 1, #self.layers - 1 do rest = rest + self.layers[i].w end
    local keep = {}
    for i = 1, #self.layers - 1 do
        local l = self.layers[i]
        l.w = (rest > 0) and (l.w / rest) * (1.0 - top.w) or 0
        if l.w > 0.002 then keep[#keep + 1] = l end
    end
    keep[#keep + 1] = top
    self.layers = keep
    for _, l in ipairs(self.layers) do l.t = l.t + dt end

    -- 全局移动层
    local L = self.loco
    L.yaw = WrapDeg(L.yaw + L.yawRate * dt)
    local fwd = Quaternion(L.yaw, Vector3.UP) * Vector3.FORWARD
    L.vel = fwd * L.speed
    L.pos = L.pos + L.vel * dt
    if not STATES[self.state].ground or L.airborne then
        if self.state == "TAKEOFF" and L.airborne then
            self:TakeoffVertical(dt)
        end
    end
    if not L.airborne and self.state ~= "LAND" then
        L.bank = Damp(L.bank, 0, 4, dt)
        L.pitch = Damp(L.pitch, 0, 4, dt)
    end

    -- 地面步态；空中时落足点始终投影在身体正下方（降落伸腿时 IK 去够地面）
    if not L.airborne then
        Gait.Update(self.gait, dt, { pos = Vector3(L.pos.x, 0, L.pos.z), yaw = L.yaw, vel = L.vel, yawRate = L.yawRate,
            groundFn = self.groundFn })
    elseif self.state ~= "TAKEOFF" then
        Gait.Reset(self.gait, Vector3(L.pos.x, 0, L.pos.z), L.yaw, self.groundFn)
    end

    -- 次级变量
    self.ikW = Approach(self.ikW, self.ikTarget, (self.state == "TAKEOFF") and 5.5 or 4.0, dt)
    if self.state ~= "TAKEOFF" then self.ikFrontTarget = 1.0 end
    self.ikFront = Approach(self.ikFront, self.ikFrontTarget, 5.0, dt)
    if STATES[self.state].ground and self.state ~= "TAKEOFF" then self.ikTarget = 1.0 end
    local deployRate = (self.state == "TAKEOFF") and 1.8 or 0.62
    self.wingDeploy = Approach(self.wingDeploy, self.wingDeployTarget, deployRate, dt)
    if self.state ~= "TAKEOFF" and self.state ~= "LAND" and self.wingDeployTarget == 0 and self.wingDeploy == 0 then
        self.wingOpenPose = Poses.WING_DISPLAY
    end
    self.impact = Approach(self.impact, 0, 1.25, dt)
    -- 观察环境：每隔几秒换一个注视方向
    local lk = self.look
    lk.timer = lk.timer - dt
    if lk.timer <= 0 then
        lk.timer = 3.0 + math.random() * 4.0
        if math.random() < 0.35 then lk.tyaw, lk.tpitch = 0, 0
        else lk.tyaw, lk.tpitch = (math.random() * 2 - 1) * 40, (math.random() * 2 - 1) * 10 end
    end
    lk.yaw = Damp(lk.yaw, lk.tyaw, 1.6, dt)
    lk.pitch = Damp(lk.pitch, lk.tpitch, 1.6, dt)
    self.breath = self.breath + dt
end

function C:TakeoffVertical(dt)
    local L = self.loco
    local t = self.stateT
    if t > FLAP_T then self.flapPhase = (self.flapPhase + dt * self.params.flapHz * 1.15) % 1.0 end
    local cmd = Clamp(G + 2.0 * (L.altTarget - L.alt) - 2.0 * L.vy, 0, 2.4 * G)
    if t < JUMP_T + 0.2 then cmd = G end -- 蹬地阶段竖直速度由腿部发力决定
    local wave = (t > FLAP_T) and (G * 0.7 * FlapLift(self.flapPhase)) or 0
    L.vy = L.vy + (cmd - G + wave) * dt
    L.alt = math.max(0.0, L.alt + L.vy * dt)
    L.pitch = Damp(L.pitch, Clamp(-L.vy * 2.2, -14, 14), 3.0, dt)
end

-- 混合各层姿态 → FK → IK → 翼膜
function C:ApplyPose(dt)
    local rig = self.rig
    local acc = Pose.New()
    for _, l in ipairs(self.layers) do
        if l.w > 0 then Pose.Accumulate(acc, STATES[l.name].pose(self, l.t), l.w) end
    end
    if self.mask ~= "all" then self:ApplyMask(acc) end

    -- 全局移动层 → root；身体姿态层 → body
    local L = self.loco
    local gy = L.airborne and 0.0 or self:GroundHeight(L.pos.x, L.pos.z)
    rig.root.position = Vector3(L.pos.x, gy + L.alt, L.pos.z)
    rig.root.rotation = Quaternion(L.yaw, Vector3.UP)
    local drop, roll, pitchG = Gait.BodyMotion(self.gait)
    local gw = self.ikW
    local b = acc.body
    local impactDy = -0.32 * math.sin(math.pi * Clamp(1 - self.impact, 0, 1)) * (self.impact > 0 and 1 or 0)
    b[5] = b[5] - 0.045 * drop * gw + impactDy
    b[1] = b[1] + L.pitch - 1.2 * pitchG * gw
    b[3] = b[3] - L.bank + 2.2 * roll * gw
    Pose.Apply(rig, acc)

    -- 胸腔呼吸（缩放胸部体素，以骨骼枢轴为中心）
    local chest = rig.parts.chest
    if chest ~= nil and self.chestVolOffset ~= nil then
        local s = 1.0 + 0.012 * math.sin(2 * math.pi * self.breath / 3.8) + 0.05 * (self.roarChest or 0) * ((self.state == "ROAR") and 1 or 0)
        chest.node.scale = Vector3(s, s, s)
        chest.node.position = self.chestVolOffset * s
    end

    -- 四肢 IK（地面权重）；肩胛滑动位移随 IK 权重回到静止位置
    for _, f in ipairs(self.gait.feet) do f.chain.nodes[1].position = f.chain.rootRest end
    if gw > 0.001 then self:ApplyLegIK(gw) end
    rig:UpdateMembranes()
end

function C:ApplyLegIK(wAll)
    local yawQ = Quaternion(self.loco.yaw, Vector3.UP)
    for _, f in ipairs(self.gait.feet) do
        local c = f.chain
        local target = f.pos
        local w = wAll * (f.front and self.ikFront or 1.0)
        if target ~= nil and w > 0.001 then
            -- 摆动相：足尖下垂、跖骨后摆
            local toe = f.lift * (f.front and 28 or 34)
            local qs = IK.Solve(c, target, yawQ * Quaternion(toe, Vector3.RIGHT), f.lift * 30)
            for i, node in ipairs(c.nodes) do
                if w >= 0.999 then
                    node.rotation = qs[i]
                else
                    node.rotation = node.rotation:Slerp(qs[i], w)
                end
            end
            if w < 0.999 then
                local root = c.nodes[1]
                root.position = c.rootRest:Lerp(root.position, w)
            end
        end
    end
end

-- 部位独立测试：其余部位冻结在静止姿态
local MASK_GROUPS = {
    wings = function(n) return n:sub(1, 1) == "w" end,
    neck = function(n) return n:sub(1, 4) == "neck" or n == "head" or n == "jaw" end,
    legs = function(n) return n:find("arm") or n:find("leg") or n:find("hand") or n:find("foot") end,
    tail = function(n) return n:sub(1, 4) == "tail" end,
}
C.MASK_GROUPS = MASK_GROUPS
function C:ApplyMask(acc)
    local keep = MASK_GROUPS[self.mask]
    if keep == nil then return end
    local idle = STATES.IDLE.pose(self, 0)
    for name, _ in pairs(acc.j) do
        if not keep(name) then acc.j[name] = idle.j[name] end
    end
end

-- 关节测试：IDLE 静止姿态 + 单个关节手动旋转，纯 FK，冻结状态机
function C:ApplyJointTest()
    local rig = self.rig
    local p = STATES.IDLE.pose(self, 0)
    Pose.SetBody(p, 0, 0, 0, 0, 0, 0)
    local jt = self.jointTest
    Pose.AddTo(p, jt.joint, jt.x, jt.y, jt.z)
    rig.root.position = Vector3(self.loco.pos.x, 0, self.loco.pos.z)
    rig.root.rotation = Quaternion(self.loco.yaw, Vector3.UP)
    Pose.Apply(rig, p)
    rig:UpdateMembranes()
end

-- 调试信息
function C:Status()
    local L = self.loco
    local parts = {}
    for _, l in ipairs(self.layers) do
        parts[#parts + 1] = string.format("%s %.0f%%", C.STATE_NAMES[l.name] or l.name, l.w * 100)
    end
    return string.format("状态: %s   混合: %s\n速度 %.1f m/s  偏航 %.0f°  高度 %.1f m  坡度 %.0f°  步频 %.2f Hz  IK %.0f%%  展翼 %.0f%%",
        C.STATE_NAMES[self.state] or self.state, table.concat(parts, " / "),
        L.speed, L.yaw, L.alt, L.bank, self.gait.freq, self.ikW * 100, self.wingDeploy * 100)
end

return C
