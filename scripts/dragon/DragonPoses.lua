-- ====================================================================
-- DragonPoses.lua — 语义化姿态构造：翅膀、颈部、尾巴、四肢的参数 → 姿态表
--
-- 所有状态（待机 / 行走 / 起飞 / 飞行 …）都用这里的函数拼姿态，参数可调、
-- 可插值，不写死逐关节角度。
-- ====================================================================

local Spec = require("dragon.DragonSpec")
local Pose = require("dragon.DragonPose")

local M = {}

local FINGERS = Spec.WING.fingers

-- ---------------------------------------------------------------- 翅膀
-- w = {
--   elev  翼根抬升（+ 向上），sweep 后掠（+ 向后），twist 翼根扭转（+ 前缘下压）
--   elbow 肘：前臂在翼平面内的折叠（- 收向前方）
--   wrist 腕：手部在翼平面内的折叠（+ 指骨收向后方）
--   fan   指骨展开度 0..1（1 = 完全展开，不允许超过 1，否则翼膜会撕开）
--   curl  指尖下弯（度），curlStep 每根指额外增量
--   fold2 远端指节在翼平面内的折叠（收翼用，+ 向后下）
--   tip   一指（翼尖）额外独立运动
-- }
function M.Wing(pose, side, w)
    Pose.SetSide(pose, "wing", side, w.twist or 0, w.sweep or 0, w.elev or 0)
    Pose.SetSide(pose, "wfore", side, 0, w.elbow or 0, 0)
    Pose.SetSide(pose, "whand", side, 0, w.wrist or 0, 0)
    local fan = math.max(0.0, math.min(1.0, w.fan or 1.0))
    local a1 = FINGERS[1].a
    for i, f in ipairs(FINGERS) do
        local g = (fan - 1.0) * (f.a - a1)
        Pose.SetSide(pose, "wf" .. i, side, 0, g, 0)
        local c = (w.curl or 0) + (w.curlStep or 0) * (i - 1)
        if i == 1 then c = c + (w.tip or 0) end
        pose.j["wf" .. i .. "m" .. side] = { c, (w.fold2 or 0) * (1.0 - 0.12 * (i - 1)), 0 }
    end
end

-- 对称翅膀
function M.Wings(pose, w, wl)
    M.Wing(pose, "_R", w)
    M.Wing(pose, "_L", wl or w)
end

-- 预设翼姿（参数表，可互相插值）
-- 收翼（待机）：即参考图三视图的抬翼静姿——腕关节高举、翼面向外前方斜开，正面看两翼成 V 形张角
M.WING_FOLD = { elev = 70, sweep = 22, twist = -28, elbow = -10, wrist = 80, fan = 0.92, curl = 0, fold2 = 0 }
-- 展翼：向两侧大幅张开（威慑 / 晾翅），参考图正视的外张姿态再展开一档
M.WING_DISPLAY = { elev = 40, sweep = 6, twist = -16, elbow = -6, wrist = 46, fan = 0.95, curl = -2 }
-- 参考图三视图姿态（比对用）
M.WING_REF = { elev = 64, sweep = 24, twist = -34, elbow = -10, wrist = 100, fan = 0.62, curl = 0 }
M.WING_SPREAD = { elev = 4, sweep = -2, twist = 0, elbow = 0, wrist = 0, fan = 1.0, curl = 0 }

function M.LerpWing(a, b, t)
    local out = {}
    for _, k in ipairs({ "elev", "sweep", "twist", "elbow", "wrist", "fan", "curl", "curlStep", "tip", "fold2" }) do
        local x, y = a[k] or 0, b[k] or 0
        if k == "fan" then x, y = a[k] or 1, b[k] or 1 end
        out[k] = x + (y - x) * t
    end
    return out
end

-- ---------------------------------------------------------------- 颈 / 头
-- 颈部弯曲按权重分配到 4 节颈椎，形成连续弧线
local NECK_W = { 0.16, 0.24, 0.28, 0.32 }
-- n = { pitch（+ 低头）, yaw（+ 向右看）, roll, headPitch, headYaw, jaw（张嘴角度）, curve（S 形：下段后仰上段前探） }
function M.Neck(pose, n)
    local pitch, yaw, roll, curve = n.pitch or 0, n.yaw or 0, n.roll or 0, n.curve or 0
    for i = 1, 4 do
        local w = NECK_W[i]
        local c = (i <= 2) and -curve or curve
        Pose.Set(pose, "neck" .. i, pitch * w + c * 0.5, yaw * w, roll * w)
    end
    Pose.Set(pose, "head", n.headPitch or 0, n.headYaw or 0, n.headRoll or 0)
    Pose.Set(pose, "jaw", n.jaw or 0, 0, 0)
end

-- ---------------------------------------------------------------- 尾
-- 波沿尾链传播：每节相位延迟 lag，幅度从根到尖递增
-- 原静止尾形越靠近尾尖越平；飞行时先抵消这段上翘，再逐节向下放松。
-- 对应原骨架的段方向约 -36/-30/-23/-17/-12/-9/-3/0 度，
-- 叠加后约为 -12/-17/-23/-30/-37/-45/-51/-57 度（向尾尖逐渐下垂）。
local TAIL_DROOP = { 24, -11, -13, -13, -12, -11, -12, -9 }
-- High speed: extend along the airflow without lifting the tip above the root.
local TAIL_STREAM = { 26, -5, -6, -5, -4, -2, -5, -2 }
-- t = { yaw（+ 向右）, pitch（+ 上抬）, waveAmp, wavePhase, lag, liftAmp, curl, droop（0..1） }
function M.Tail(pose, t)
    for i = 1, 8 do
        local f = (i - 1) / 7
        local ph = (t.wavePhase or 0) - (t.lag or 0.55) * (i - 1)
        local amp = (t.waveAmp or 0) * (0.35 + 0.65 * f)
        local yaw = (t.yaw or 0) / 8 + amp * math.sin(ph)
        local lift = (t.liftAmp or 0) * (0.3 + 0.7 * f) * math.sin(ph * 0.5 + 1.3)
        local pitch = (t.pitch or 0) / 8 + lift + (t.curl or 0) * f * 0.25
        local stream = type(t.stream) == "table" and (t.stream[i] or 0) or (t.stream or 0)
        pitch = pitch + (t.droop or 0) * (TAIL_DROOP[i] * (1-stream) + TAIL_STREAM[i] * stream)
        Pose.Set(pose, "tail" .. i, pitch, yaw, 0)
    end
end

return M
