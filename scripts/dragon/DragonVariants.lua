-- ====================================================================
-- DragonVariants.lua — 三种型号的龙：小号幼龙 / 中号巨龙（原版）/ 大号古龙
--
-- 中号直接用 DragonSpec 原数据，不做任何形变。小号、大号在中号的静止姿态上做
-- 「分骨骼形变」后再体素化：
--   * 每根骨骼有一条主轴 a（躯干 = +Z，颈 / 尾 / 四肢 = 指向下一节），
--     len 沿主轴缩放（骨长），thick 垂直主轴缩放（粗细）；可选 rot 给静止姿态加弯折。
--   * 子骨骼枢轴 = 父骨骼新枢轴 + 父骨骼映射(原偏移)，关节始终连着；
--     体块按所属骨骼的映射搬运，半径按方向取缩放量，配色函数反算回中号坐标取色。
--   * 整体再乘尺度 S，最后把后足底落回地面，前肢整体上下微调到同一地面。
-- 翼按 S × wing.scale 整体等比缩放，翼膜后缘贴体点随腰部形变重算。
-- 标签运算（tags）在形变前、中号坐标里做：角 / 背刺 / 冠 / 爪等按锚点伸缩或删除。
-- ====================================================================

local Spec = require("dragon.DragonSpec")
local Sculpt = require("dragon.DragonSculpt")

local M = {}

M.ORDER = { "small", "medium", "large" }

local P = Spec.PAL
local BLUSH = 55 -- 小号专用腮红槽位（龙占 40–55，地面 60/61）
local IRIS = 56  -- 型号专用虹膜（大号自发光冰蓝 / 小号亮蓝）
local LINER = 57 -- 型号专用眼线 / 高光（大号深色眼线、小号第二高光）

-- ---------------------------------------------------------------- 3x3 / 向量
---@type number[]
local IDENT = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
local function MatMul(a, b)
    local r = {}
    for i = 0, 2 do
        for j = 1, 3 do
            r[i * 3 + j] = a[i * 3 + 1] * b[j] + a[i * 3 + 2] * b[3 + j] + a[i * 3 + 3] * b[6 + j]
        end
    end
    return r
end
local function MatVec(m, v)
    return { m[1] * v[1] + m[2] * v[2] + m[3] * v[3], m[4] * v[1] + m[5] * v[2] + m[6] * v[3],
        m[7] * v[1] + m[8] * v[2] + m[9] * v[3] }
end
local function Transpose(m) return { m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] } end
local function Add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
local function Sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function Mul(a, k) return { a[1] * k, a[2] * k, a[3] * k } end
local function Dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function Len(a) return math.sqrt(Dot(a, a)) end
local function Norm(a)
    local l = Len(a)
    if l < 1e-9 then return { 0, 0, 1 } end
    return { a[1] / l, a[2] / l, a[3] / l }
end
local function Cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
local function MirrorX(v) return { -v[1], v[2], v[3] } end

-- D = len·aaᵀ + thick·(I − aaᵀ)
local function ScaleMat(a, len, thick)
    local m = {}
    for i = 1, 3 do
        for j = 1, 3 do
            m[(i - 1) * 3 + j] = (len - thick) * a[i] * a[j] + ((i == j) and thick or 0)
        end
    end
    return m
end

local function Base(name)
    local s = name:sub(-2)
    if s == "_R" or s == "_L" then return name:sub(1, -3), s end
    return name, ""
end

-- 每根骨骼的主轴：指向这根子骨骼
local AXIS_CHILD = {
    neck1 = "neck2", neck2 = "neck3", neck3 = "neck4", neck4 = "head",
    armU = "armL", armL = "hand", legU = "legL", legL = "legM", legM = "foot",
    tail1 = "tail2", tail2 = "tail3", tail3 = "tail4", tail4 = "tail5", tail5 = "tail6", tail6 = "tail7", tail7 = "tail8",
}

-- 骨骼名 → 形变参数分组
local function Group(base)
    if base:match("^neck%d$") then return "neck" end
    if base:match("^tail%d$") and base ~= "tail8" then return "tail" end
    if base:match("^fd%d") then return "hand" end
    if base:match("^hd%d") then return "foot" end
    return nil
end

-- ---------------------------------------------------------------- 标签运算（中号坐标）
local POS_KEYS = { "c", "a", "b", "base", "anchor" }

-- 以 anchor 为中心伸缩：位置 ×kl，截面半径 ×kr；rot（度，仅锥体 / 鳍片）绕 anchor 转向，左侧自动镜像
local function ScaleAboutPrim(p, anchor, kl, kr, rot)
    local R = nil
    if rot ~= nil and (p.type == "cone" or p.type == "fin") then
        if anchor[1] < 0 then R = Sculpt.RotMatrix(rot[1], -rot[2], -rot[3]) else R = Sculpt.RotMatrix(rot[1], rot[2], rot[3]) end
    end
    for _, key in ipairs(POS_KEYS) do
        if type(p[key]) == "table" then
            local d = Mul(Sub(p[key], anchor), kl)
            if R ~= nil then d = MatVec(R, d) end
            p[key] = Add(anchor, d)
        end
    end
    if R ~= nil then
        if p.u then p.u = MatVec(R, p.u) end
        if p.v then p.v = MatVec(R, p.v) end
    end
    local t = p.type
    if t == "ellipsoid" then p.r = { p.r[1] * kl, p.r[2] * kl, p.r[3] * kl }
    elseif t == "cone" then p.r = { p.r[1] * kr, p.r[2] * kr }
    elseif t == "box" then p.h = { p.h[1] * kl, p.h[2] * kl, p.h[3] * kl }
    elseif t == "fin" then
        p.len, p.h = p.len * kl, p.h * kl
        if p.sweep then p.sweep = p.sweep * kl end
        p.thick = (p.thick or 0.12) * kr
    elseif t == "rhombus" then
        p.a, p.b, p.thick = p.a * kl, p.b * kl, p.thick * kr
    end
    if p.k then p.k = p.k * kr end
    if type(p.color) == "function" then
        local f = p.color
        local Rt = R and Transpose(R) or IDENT
        p.color = function(x, y, z, pr)
            local d = MatVec(Rt, { x - anchor[1], y - anchor[2], z - anchor[3] })
            return f(anchor[1] + d[1] / kl, anchor[2] + d[2] / kl, anchor[3] + d[3] / kl, pr)
        end
    end
    if p.mask then
        local f = p.mask
        local Rt = R and Transpose(R) or IDENT
        p.mask = function(x, y, z)
            local d = MatVec(Rt, { x - anchor[1], y - anchor[2], z - anchor[3] })
            return f(anchor[1] + d[1] / kl, anchor[2] + d[2] / kl, anchor[3] + d[3] / kl)
        end
    end
end

local function AnchorOf(p)
    if p.anchor then return p.anchor end
    if p.type == "cone" then return p.a end
    if p.type == "fin" then return p.base end
    return p.c
end

-- ---------------------------------------------------------------- 骨骼形变
-- 体块按所属骨骼映射 x' = NP + L·(x − P)
local function TransformPrim(p, b)
    local function F(x) return Add(b.NP, MatVec(b.L, Sub(x, b.P))) end
    local function Dl(v) return b.S * Len(MatVec(b.D, v)) end
    local t = p.type
    local Rold = p.m
    if Rold == nil and p.rot ~= nil then Rold = Sculpt.RotMatrix(p.rot[1], p.rot[2], p.rot[3]) end
    if t == "ellipsoid" or t == "box" then
        local R = Rold or IDENT
        local key = (t == "ellipsoid") and "r" or "h"
        local src, out = p[key], {}
        for i = 1, 3 do out[i] = src[i] * Dl({ R[i], R[3 + i], R[6 + i] }) end
        p[key] = out
        p.c = F(p.c)
        if b.rotated then p.m = MatMul(b.W, R) else p.m = Rold end
        p.rot = nil
        if p.round then p.round = p.round * b.S * math.min(b.len, b.thick) end
    elseif t == "cone" then
        local d = Norm(Sub(p.b, p.a))
        local ca = Dot(d, b.axis)
        local rs = b.S * math.sqrt(b.thick * b.thick + (b.len * b.len - b.thick * b.thick) * (1 - ca * ca) * 0.5)
        p.a, p.b = F(p.a), F(p.b)
        p.r = { p.r[1] * rs, p.r[2] * rs }
    elseif t == "fin" then
        local u = Norm(p.u)
        local v = p.v
        local vo = Norm(Sub(v, Mul(u, Dot(v, u))))
        local w = Cross(u, vo)
        local su, sv, sw = Dl(u), Dl(vo), Dl(w)
        p.base = F(p.base)
        p.u = MatVec(b.W, MatVec(b.D, u))
        p.v = MatVec(b.W, MatVec(b.D, v))
        p.len, p.h = p.len * su, p.h * sv
        p.sweep = (p.sweep or 0) * su
        p.thick = (p.thick or 0.12) * sw
    elseif t == "rhombus" then
        local u, v = Norm(p.u), Norm(p.v)
        local sa, sb, sw = Dl(u), Dl(v), Dl(Cross(u, v))
        p.c = F(p.c)
        p.u = Norm(MatVec(b.W, MatVec(b.D, u)))
        p.v = Norm(MatVec(b.W, MatVec(b.D, v)))
        p.a, p.b, p.thick = p.a * sa, p.b * sb, p.thick * sw
    end
    if p.k then p.k = p.k * b.S * 0.5 * (b.len + b.thick) end
    if p.anchor then p.anchor = F(p.anchor) end
    if type(p.color) == "function" then
        local f, NP, Li, P0 = p.color, b.NP, b.Linv, b.P
        p.color = function(x, y, z, pr)
            local o = MatVec(Li, { x - NP[1], y - NP[2], z - NP[3] })
            return f(P0[1] + o[1], P0[2] + o[2], P0[3] + o[3], pr)
        end
    end
    if p.mask then
        local f, NP, Li, P0 = p.mask, b.NP, b.Linv, b.P
        p.mask = function(x, y, z)
            local o = MatVec(Li, { x - NP[1], y - NP[2], z - NP[3] })
            return f(P0[1] + o[1], P0[2] + o[2], P0[3] + o[3])
        end
    end
end

-- ---------------------------------------------------------------- 可动趾爪（大号）
-- 把原来焊在手掌 / 足掌上的趾和爪拆成 fdN / fdNc（前）、hdN / hdNc（后）两节趾骨
local function ArticulateDigits(prims, bones, cfg)
    local keep = {}
    for _, p in ipairs(prims) do
        if p.tag ~= "digit" and p.tag ~= "claw" then keep[#keep + 1] = p end
    end
    local P_ = Spec.PAL
    for _, d in ipairs(Spec.DIGITS) do
        local pre = (d.limb == "F") and "fd" or "hd"
        local kd, kc, kr = cfg.digitLen or 1, cfg.clawLen or 1, cfg.digitRad or 1
        -- 趾间距放宽（spread），趾节加长；爪尖按 clawDrop 向下勾
        local dx = (d.a1[1] - d.cx) * ((cfg.spread or 1) - 1)
        local a1 = { d.a1[1] + dx, d.a1[2], d.a1[3] }
        local b1 = Add(a1, Mul(Sub(d.b1, d.a1), kd))
        local a2 = Add(b1, Sub(d.a2, d.b1))
        local cd = Sub(d.b2, d.a2)
        cd[2] = cd[2] - (cfg.clawDrop or 0)
        local b2 = Add(a2, Mul(cd, kc))
        for _, side in ipairs({ "_R", "_L" }) do
            local mx = (side == "_L") and MirrorX or function(v) return v end
            local parent = d.parent:sub(1, -3) .. side
            local n1, n2 = pre .. d.n .. side, pre .. d.n .. "c" .. side
            bones[#bones + 1] = { name = n1, parent = parent, pivot = mx(a1) }
            bones[#bones + 1] = { name = n2, parent = n1, pivot = mx(a2) }
            keep[#keep + 1] = { type = "cone", bone = n1, a = mx(a1), b = mx(b1), r = { d.r1[1] * kr, d.r1[2] * kr }, color = P_.BLUE_M }
            local cr = cfg.clawRad or 1
            keep[#keep + 1] = { type = "cone", bone = n2, a = mx(a2), b = mx(b2), r = { d.r2[1] * cr, d.r2[2] * cr }, color = P_.CLAW }
            -- 指节球：挂父骨骼，弯趾时遮住缝
            keep[#keep + 1] = { type = "ellipsoid", bone = parent, c = mx(a1), r = { d.r1[1] * kr, d.r1[1] * kr, d.r1[1] * kr },
                color = P_.BLUE_M, joint = true }
            keep[#keep + 1] = { type = "ellipsoid", bone = n1, c = mx(a2), r = { d.r1[2] * kr * 0.95, d.r1[2] * kr * 0.95, d.r1[2] * kr * 0.95 },
                color = P_.BLUE_M, joint = true }
        end
    end
    return keep
end

-- ---------------------------------------------------------------- 型号定义
-- bones：按骨骼基名或分组（neck / tail / hand / foot）给 { len, thick, rot }
-- tags：{ 标签 = false（删除）| { kl, kr } }
local DEFS = {}

DEFS.small = {
    id = "small", name = "小号 · 幼龙", size = 0.42,
    rideable = false, pet = true,
    voxel = { body = 0.04, head = 0.024, wing = 0.05 },
    wing = { scale = 0.66 },
    bones = {
        body = { len = 0.78, thick = 1.12 }, pelvis = { len = 0.78, thick = 1.14 },
        waist = { len = 0.72, thick = 1.16 }, chest = { len = 0.78, thick = 1.15 },
        neck = { len = 0.5, thick = 1.2 },
        head = { len = 1.38, thick = 1.72 }, jaw = { len = 1.38, thick = 1.72 },
        armU = { len = 0.66, thick = 1.3 }, armL = { len = 0.66, thick = 1.3 }, hand = { len = 1.28, thick = 1.28 },
        legU = { len = 0.66, thick = 1.3 }, legL = { len = 0.66, thick = 1.3 }, legM = { len = 0.66, thick = 1.3 },
        foot = { len = 1.28, thick = 1.28 },
        tail = { len = 0.72, thick = 1.15 }, tail8 = { len = 1.1, thick = 1.1 },
    },
    tags = {
        eye = false, pupil = false, eyelid = false, tooth = false, nostril = false, brow = false,
        horn = { 0.45, 0.85 }, spike = { 0.42, 0.8 }, crest = { 0.6, 0.9 }, cheek = { 0.8, 1.0 },
        claw = { 0.55, 0.9 }, tailblade = { 0.85, 1.0 },
    },
    -- 粉嫩一些的配色
    palette = {
        [P.BLUE_L] = { 0.60, 0.81, 1.00 }, [P.BLUE_M] = { 0.47, 0.69, 0.99 }, [P.BLUE_D] = { 0.42, 0.59, 0.92 },
        [P.BLUE_X] = { 0.36, 0.50, 0.86 }, [P.BLUE_P] = { 0.78, 0.90, 1.00 }, [P.BLUE_L2] = { 0.54, 0.76, 1.00 },
        [P.PUPIL] = { 0.025, 0.025, 0.03 }, [P.EYE] = { 0.22, 0.55, 1.00 }, [P.MOUTH] = { 0.85, 0.42, 0.52 },
        [BLUSH] = { 1.00, 0.62, 0.74 }, [IRIS] = { 0.55, 0.92, 1.00 }, [LINER] = { 1.0, 1.0, 1.0 },
    },
    -- 简单黑白眼不使用虹膜或高光自发光，切换型号时清掉大号留下的眼部自发光
    emissive = { [IRIS] = { 0, 0, 0, 0 }, [LINER] = { 0, 0, 0, 0 } },
    params = { walkSpeed = 0.85, flapHz = 1.4, flySpeed = 6.0, turnRate = 80, sprintSpeed = 11.0 },
    -- 额外体块（中号最终坐标，挂头骨，随头部一起形变）
    extra = function(add)
        -- 呆萌豆豆眼：小椭圆黑瞳为主，后侧留少量眼白；直接涂现有体素，不叠几何。
        local cy, cz, ry, rz = 4.46, 1.62, 0.075, 0.065
        local function EyeColor(x, y, z)
            local dy, dz = (y - cy) / ry, (z - cz) / rz
            if (dy / 0.85) ^ 2 + ((dz - 0.22) / 0.72) ^ 2 < 1 then return P.PUPIL end
            return LINER
        end
        add({ type = "box", bone = "head", c = { 0.25, cy, cz }, h = { 0.25, ry, rz }, color = EyeColor,
            mask = function(x, y, z)
                return x > 0.1 and ((y - cy) / ry) ^ 2 + ((z - cz) / rz) ^ 2 < 1
            end, paint = true, prio = 1.0 }, true)
        -- 腮红：眼睛后下方
        add({ type = "ellipsoid", bone = "head", c = { 0.4, 4.26, 1.5 }, r = { 0.14, 0.045, 0.08 }, color = BLUSH,
            mask = function(x) return x > 0.15 end, paint = true, prio = 0.4 }, true)
    end,
}

DEFS.large = {
    id = "large", name = "大号 · 古龙", size = 1.5,
    rideable = true, scapula = 1.5,
    flightNeckLift = { neck1 = -22, neck2 = -8, head = 30 },
    voxel = { body = 0.1, head = 0.068, wing = 0.12 },
    wing = { scale = 1.08 },
    digits = { digitLen = 1.9, clawLen = 1.9, digitRad = 1.0, clawRad = 0.8, clawDrop = 0.04, spread = 1.35 },
    bones = {
        body = { len = 1.1, thick = 1.08 }, pelvis = { len = 1.08, thick = 1.1 },
        waist = { len = 1.12, thick = 1.1 }, chest = { len = 1.06, thick = 1.2 },
        -- 颈部前倾、头部回正：怪物猎人古龙那种压低的头颈线条
        neck1 = { len = 0.9, thick = 1.16, rot = { 24, 0, 0 } }, neck2 = { len = 0.9, thick = 1.12, rot = { 10, 0, 0 } },
        neck3 = { len = 0.88, thick = 1.1, rot = { -4, 0, 0 } }, neck4 = { len = 0.88, thick = 1.1 },
        head = { len = 1.12, thick = 0.95, rot = { -30, 0, 0 } }, jaw = { len = 1.12, thick = 0.95 },
        armU = { len = 1.06, thick = 1.32 }, armL = { len = 1.04, thick = 1.3 }, hand = { len = 1.28, thick = 1.28 },
        legU = { len = 1.0, thick = 1.16 }, legL = { len = 1.0, thick = 1.14 }, legM = { len = 1.0, thick = 1.14 },
        foot = { len = 1.2, thick = 1.2 },
        tail = { len = 1.2, thick = 1.15 }, tail8 = { len = 1.3, thick = 1.3 },
    },
    tags = {
        horn = { 1.45, 1.15, rot = { -38, 0, 0 } }, spike = { 1.35, 1.1 }, crest = { 1.25, 1.05 }, cheek = { 1.15, 1.0 },
        tailblade = { 1.35, 1.1 }, tooth = { 1.3, 1.1 },
        -- 中号的方块小眼换成 extra 里的杏仁眼
        eye = false, pupil = false, eyelid = false,
    },
    -- 更深的钢蓝、象牙色爪，明暗对比更强
    palette = {
        [P.BLUE_L] = { 0.40, 0.62, 0.95 }, [P.BLUE_M] = { 0.25, 0.43, 0.82 }, [P.BLUE_D] = { 0.17, 0.27, 0.55 },
        [P.BLUE_X] = { 0.09, 0.13, 0.31 }, [P.BLUE_P] = { 0.62, 0.79, 0.98 }, [P.BLUE_L2] = { 0.33, 0.54, 0.90 },
        [P.CLAW] = { 0.94, 0.91, 0.83 }, [P.EYE] = { 0.30, 0.78, 1.00 },
        [P.PUPIL] = { 0.025, 0.025, 0.03 },
        [IRIS] = { 0.97, 0.98, 1.00 }, [LINER] = { 0.03, 0.04, 0.10 },
    },
    -- 眼白不再使用黄色自发光，黑瞳和眼线也不发光。
    emissive = { [IRIS] = { 0, 0, 0, 0 }, [LINER] = { 0, 0, 0, 0 } },
    params = { walkSpeed = 1.9, flapHz = 0.6, flySpeed = 9.5, turnRate = 42, sprintSpeed = 21.0 },
    extra = function(add)
        -- 杏仁眼（中号坐标、侧视 y-z 平面）：后眼角上挑，深色眼线包边，外侧眼白、内侧黑色长条。
        -- u = 沿 z 归一（+1 = 前眼角），v = 相对倾斜中线的高度；眼睑轮廓 |v| < (1 − u²)^0.75
        local cy, cz, rz, ry, tilt = 4.49, 1.7, 0.2, 0.1, 0.28
        local function UV(y, z)
            local u = (z - cz) / rz
            local v = (y - cy - tilt * (cz - z)) / ry
            local h = math.max(0, 1 - u * u) ^ 0.75
            return u, v, h
        end
        local function EyeMask(x, y, z)
            if x < 0.15 then return false end
            local u, v, h = UV(y, z)
            return math.abs(u) < 1 and math.abs(v) < h
        end
        local function EyeColor(x, y, z)
            local u, v, h = UV(y, z)
            -- 靠鼻梁的前侧长条为黑色，贯穿眼睛内区；外侧保留眼白。
            if u > 0.05 and math.abs(v) < 0.55 * h then return P.PUPIL end
            if math.abs(v) > 0.55 * h or math.abs(u) > 0.78 then return LINER end -- 眼线
            return IRIS
        end
        add({ type = "ellipsoid", bone = "head", c = { 0.26, cy, cz }, r = { 0.24, 0.17, 0.22 }, color = EyeColor,
            mask = EyeMask, paint = true, prio = 1.0 }, true)
        -- 压眼的眉骨：眼睛正上方一道最深色的骨棱，前低后高，和后掠的角连成一条线
        add({ type = "box", bone = "head", c = { 0.22, 4.625, 1.68 }, h = { 0.045, 0.02, 0.17 }, color = P.BLUE_X,
            rot = { -10, -14, 12 }, round = 0.015 }, true)
        -- 前臂肘后骨刺
        add({ type = "fin", bone = "armL_R", base = { 0.52, 0.98, 0.56 }, u = { 0, 1, 0 }, v = { 0, 0.25, -1 },
            len = 0.3, h = 0.34, color = P.BLUE_X, sweep = -0.1, thick = 0.13 })
        -- 肩甲
        add({ type = "ellipsoid", bone = "armU_R", c = { 0.66, 1.66, 0.92 }, r = { 0.16, 0.3, 0.3 }, color = P.BLUE_D, k = 0.08 })
    end,
}

-- ---------------------------------------------------------------- 构建
local cache = {}

local function Build(def)
    local S = def.size
    local prims, bones = Spec.ExpandRaw()

    -- 额外体块（_R 骨骼的自动镜像到 _L；mirror=true 的头部体块按 x 镜像一份）
    if def.extra then
        def.extra(function(p, mirror)
            prims[#prims + 1] = p
            local base, side = Base(p.bone)
            if side == "_R" then
                prims[#prims + 1] = Spec.MirrorPrim(p, base .. "_L")
            elseif mirror then
                prims[#prims + 1] = Spec.MirrorPrim(p, p.bone)
            end
        end)
    end
    if def.digits then prims = ArticulateDigits(prims, bones, def.digits) end

    -- 标签：删除 / 伸缩
    local kept = {}
    for _, p in ipairs(prims) do
        local op = p.tag and def.tags[p.tag]
        if op == false then
            -- 删除
        else
            if op then ScaleAboutPrim(p, AnchorOf(p), op[1], op[2], op.rot) end
            kept[#kept + 1] = p
        end
    end
    prims = kept

    -- 骨骼映射
    local Pv, parentOf, children = {}, {}, {}
    for _, b in ipairs(bones) do
        Pv[b.name], parentOf[b.name] = b.pivot, b.parent
    end
    ---@type table<string, table>
    local maps = {}
    for _, b in ipairs(bones) do
        local base, side = Base(b.name)
        local prm = def.bones[base] or def.bones[Group(base) or ""] or {}
        local len, thick = prm.len or 1, prm.thick or 1
        local axis = { 0, 0, 1 }
        local ch = AXIS_CHILD[base]
        if ch ~= nil and Pv[ch .. side] ~= nil then axis = Norm(Sub(Pv[ch .. side], b.pivot)) end
        ---@type number[]
        local R = IDENT
        if prm.rot then
            local r = prm.rot
            if side == "_L" then R = Sculpt.RotMatrix(r[1], -r[2], -r[3]) else R = Sculpt.RotMatrix(r[1], r[2], r[3]) end
        end
        local pm = b.parent and maps[b.parent] or nil
        local rotated = (prm.rot ~= nil) or (pm ~= nil and pm.rotated)
        ---@type number[]
        local W = IDENT
        if rotated then W = pm and MatMul(pm.W, R) or R end
        local D = ScaleMat(axis, len, thick)
        local L = MatMul(W, D)
        for i = 1, 9 do L[i] = L[i] * S end
        local Dinv = ScaleMat(axis, 1 / len, 1 / thick)
        local Linv = MatMul(Dinv, Transpose(W))
        for i = 1, 9 do Linv[i] = Linv[i] / S end
        local NP
        if pm == nil then NP = Mul(b.pivot, S) else NP = Add(pm.NP, MatVec(pm.L, Sub(b.pivot, pm.P))) end
        maps[b.name] = { P = b.pivot, NP = NP, L = L, Linv = Linv, W = W, D = D, S = S, len = len, thick = thick,
            axis = axis, rotated = rotated }
    end
    local function F(name, x)
        local m = maps[name]
        return Add(m.NP, MatVec(m.L, Sub(x, m.P)))
    end

    -- 落地：后足底回到 y=0；前肢整条链上下平移到同一地面
    local fr = Spec.footRest
    local yH = F("foot_R", fr.H)[2]
    local yF = F("hand_R", fr.F)[2] - yH
    local function InArm(name)
        local n = name
        while n ~= nil do
            local base = Base(n)
            if base == "armU" then return true end
            n = parentOf[n]
        end
        return false
    end
    for name, m in pairs(maps) do
        local dy = -yH - (InArm(name) and yF or 0)
        m.NP = { m.NP[1], m.NP[2] + dy, m.NP[3] }
    end

    for _, p in ipairs(prims) do TransformPrim(p, maps[p.bone]) end

    local outBones = {}
    for _, b in ipairs(bones) do
        outBones[#outBones + 1] = { name = b.name, parent = b.parent, pivot = maps[b.name].NP }
    end

    -- 翼：整体等比，翼根随胸、贴体点随腰
    local mw = Spec.WING
    local u = S * def.wing.scale
    local root = F("chest", mw.root)
    local flankW = F("waist", Add(mw.root, mw.flank))
    local fingers = {}
    for i, f in ipairs(mw.fingers) do fingers[i] = { a = f.a, L = f.L * u } end
    local wing = {
        root = root, elbow = Mul(mw.elbow, u), wrist = Mul(mw.wrist, u), fingers = fingers, joint = mw.joint,
        flank = Sub(flankW, root), scallop = mw.scallop, strips = mw.strips, bones = mw.bones, unit = u,
    }

    local spec = {
        id = def.id, name = def.name, size = S, rideable = def.rideable, pet = def.pet, digits = def.digits ~= nil,
        scapula = def.scapula, flightNeckLift = def.flightNeckLift,
        PAL = Spec.PAL, VOXEL_BODY = def.voxel.body, VOXEL_HEAD = def.voxel.head,
        VOXEL_WING = def.voxel.wing, WING = wing, FingerPoints = Spec.FingerPoints, params = def.params,
        membraneThick = Spec.membraneThick * math.max(0.5, math.min(1.3, u)),
    }
    spec.PALETTE = {}
    for k, v in pairs(Spec.PALETTE) do spec.PALETTE[k] = v end
    for k, v in pairs(def.palette or {}) do spec.PALETTE[k] = v end
    spec.EMISSIVE = {}
    for k, v in pairs(Spec.EMISSIVE) do spec.EMISSIVE[k] = v end
    for k, v in pairs(def.emissive or {}) do spec.EMISSIVE[k] = v end

    -- 足位
    local fF, fH = F("hand_R", fr.F), F("foot_R", fr.H)
    spec.footRest = { F = { fF[1], 0.0, fF[3] }, H = { fH[1], 0.0, fH[3] } }

    -- 挂点 / 命中区：偏移量按骨骼映射，翼上的按翼缩放
    local function MapOffset(bone, off)
        local m = maps[bone]
        if m == nil then return Mul(off, u) end
        return MatVec(m.L, off)
    end
    spec.SOCKETS = {}
    for _, s in ipairs(Spec.SOCKETS) do
        spec.SOCKETS[#spec.SOCKETS + 1] = { name = s.name, bone = s.bone, offset = MapOffset(s.bone, s.offset) }
    end
    spec.HIT_ZONES = {}
    for _, z in ipairs(Spec.HIT_ZONES) do
        local m = maps[z.bone]
        local k = m and (S * 0.5 * (m.len + m.thick)) or u
        spec.HIT_ZONES[#spec.HIT_ZONES + 1] = { name = z.name, bone = z.bone, offset = MapOffset(z.bone, z.offset), radius = z.radius * k }
    end

    function spec.Expand()
        local out = {}
        for i, p in ipairs(prims) do
            local q = {}
            for k, v in pairs(p) do q[k] = v end
            out[i] = Sculpt.Prepare(q)
        end
        return out, outBones
    end
    function spec.VoxelSizeOf(bone)
        local base = Base(bone)
        if base == "head" or base == "jaw" or base:match("^[fh]d%d") then return spec.VOXEL_HEAD end
        return spec.VOXEL_BODY
    end
    function spec.WingBonePrims() return Spec.WingBonePrims(spec.WING) end
    return spec
end

---@return table spec 型号规格（中号即 DragonSpec 本身）
function M.Get(id)
    if id == nil or id == "medium" or DEFS[id] == nil then return Spec end
    if cache[id] == nil then cache[id] = Build(DEFS[id]) end
    return cache[id]
end

function M.Name(id)
    if DEFS[id] then return DEFS[id].name end
    return Spec.name
end

return M
