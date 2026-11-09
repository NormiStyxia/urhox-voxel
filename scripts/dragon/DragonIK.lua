-- ====================================================================
-- DragonIK.lua — 四肢解析 IK（两骨 + 末端节 + soft IK + 前肢肩胛滑动）。
--
-- 在腿链父节点（胸 / 骨盆）的局部空间里求解：
--   前肢：肩 → 肘 → 腕，腕下的手掌节保持贴地；肘尖朝后（猫科 / 蜥蜴式）
--   后肢：髋 → 膝 → 跗 → 踝，跖骨按给定朝向，膝朝前、跗朝后（趾行式）
-- 关节旋转通过「静止链平面 → 求解链平面」的整体对齐计算，保留弯曲平面，
-- 不会出现反关节或绕骨骼轴的乱转；骨段长度恒定（距离超限时钳制）。
-- ====================================================================

local M = {}

M.SCAPULA_MAX = 0.22

---@return Vector3
local function V(t) return Vector3(t[1], t[2], t[3]) end

-- 链平面坐标系：x = 第一节方向，y = 平面法线，z = x × y
local function Frame(d1, d2)
    local x = d1:Normalized()
    local n = d1:CrossProduct(d2)
    if n:LengthSquared() < 1e-8 then n = Vector3(1, 0, 0) end
    n = n:Normalized()
    local z = x:CrossProduct(n):Normalized()
    return Quaternion(x, n, z)
end

---构建腿链描述
---@param rig DragonRig
---@param names string[] 关节骨骼名（自根到末端，3 或 4 个）
---@param footRest number[] 静止时足底接地点（世界）
---@param bend string "back" 肘朝后 / "front" 膝朝前
function M.NewChain(rig, names, footRest, bend, side)
    local c = { names = names, nodes = {}, rest = {}, bend = bend, side = side }
    for i, n in ipairs(names) do
        c.nodes[i] = rig.bones[n]
        c.rest[i] = rig.pivots[n]
    end
    c.parent = c.nodes[1].parent
    c.rootRest = c.nodes[1].position
    local p = c.rest
    c.r1 = (V(p[2]) - V(p[1])) --[[@as Vector3]]
    c.r2 = (V(p[3]) - V(p[2])) --[[@as Vector3]]
    c.L1, c.L2 = c.r1:Length(), c.r2:Length()
    c.restFrame = Frame(c.r1, c.r2)
    if #names == 4 then
        c.r3 = (V(p[4]) - V(p[3])) --[[@as Vector3]]
        c.L3 = c.r3:Length()
        -- 踝（末端枢轴）→ 足底接地点
        c.footOff = V(footRest) - V(p[4])
    else
        c.footOff = V(footRest) - V(p[3])
    end
    -- 父节点局部空间下的足底静止点（= 世界静止坐标 - 父枢轴，静止旋转为单位）
    -- 静止足底点：root 局部 = 世界静止坐标（静止时 root 在原点）
    c.footRestRoot = V(footRest)
    return c
end

-- Soft IK：距离接近全长时按指数曲线软化，避免伸直瞬间关节角剧变（伸直奇异点）
M.SOFT = 0.07
local function SoftDist(dist, L)
    local soft = M.SOFT * L
    local ds = L - soft
    if dist <= ds then return dist end
    return ds + soft * (1.0 - math.exp(-(dist - ds) / soft))
end

-- 两骨解析解：返回中间关节位置
---@param a Vector3
---@param t Vector3
---@param pole Vector3
---@return Vector3, Vector3
local function SolveTwoBone(a, t, L1, L2, pole)
    local d = (t - a) --[[@as Vector3]]
    local dist = SoftDist(d:Length(), L1 + L2)
    local minD, maxD = math.abs(L1 - L2) + 0.02, (L1 + L2) * 0.998
    if dist < minD then dist = minD elseif dist > maxD then dist = maxD end
    local dn = (dist > 1e-6) and d:Normalized() or Vector3(0, -1, 0)
    local x = (L1 * L1 - L2 * L2 + dist * dist) / (2 * dist)
    local h = math.sqrt(math.max(0, L1 * L1 - x * x))
    local pp = (pole - dn * pole:DotProduct(dn)) --[[@as Vector3]]
    if pp:LengthSquared() < 1e-8 then pp = Vector3(0, 0, 1) end
    pp = pp:Normalized()
    return a + dn * x + pp * h, a + dn * dist
end

---求解一条腿
---@param c table NewChain 结果
---@param footWorld Vector3 足底目标（世界）
---@param groundRot Quaternion 足部在世界中的期望朝向（通常 = 身体偏航 * 足尖俯仰）
---@param metaPitch number 后肢跖骨额外后摆（度，摆动相抬脚用）
---@return Quaternion[] 各关节局部旋转
function M.Solve(c, footWorld, groundRot, metaPitch)
    local parent = c.parent
    local pInv = parent.worldRotation:Inverse()
    -- 父局部空间
    local foot = parent:WorldToLocal(footWorld)
    local footRot = pInv * groundRot
    local a = c.rootRest --[[@as Vector3]]
    local q = {}
    if c.L3 ~= nil then
        -- 后肢：踝 = 足底 - 足部朝向 * footOff；跗 = 踝 - 跖骨向量
        local ankle = (foot - footRot * c.footOff) --[[@as Vector3]]
        local meta = footRot * (Quaternion(-(metaPitch or 0), Vector3.RIGHT) * c.r3)
        local hock = (ankle - meta) --[[@as Vector3]]
        local pole = Vector3(c.side * 0.15, 0, 1) -- 膝朝前、略外
        local ha = (hock - a) --[[@as Vector3]]
        c.stretch = ha:Length() / (c.L1 + c.L2)
        local knee, hockC = SolveTwoBone(a, hock, c.L1, c.L2, pole)
        local d1, d2 = knee - a, hockC - knee
        local q1 = Frame(d1, d2) * c.restFrame:Inverse()
        local q2 = Quaternion(c.r2, (q1:Inverse() * d2) --[[@as Vector3]])
        local q12 = q1 * q2
        local m = ankle - hockC
        local q3 = Quaternion(c.r3, (q12:Inverse() * m) --[[@as Vector3]])
        local q4 = (q12 * q3):Inverse() * footRot
        q[1], q[2], q[3], q[4] = q1, q2, q3, q4
    else
        -- 前肢：腕 = 足底 - 手掌偏移
        local wrist = (foot - footRot * c.footOff) --[[@as Vector3]]
        -- 肩胛滑动：前肢静止时近乎伸直，迈步时肩关节随肩胛骨在胸廓上前后 / 下沉滑动
        -- （四足动物前肢没有锁骨，靠肩胛扩大步幅），最多 SCAPULA_MAX 米，保留 4% 弯曲
        local reachMax = (c.L1 + c.L2) * (1.0 - M.SOFT)
        local dv = (wrist - a) --[[@as Vector3]]
        local dist = dv:Length()
        if dist > reachMax then
            local slide = math.min(dist - reachMax, M.SCAPULA_MAX)
            a = a + dv * (slide / dist)
        end
        c.nodes[1].position = a
        local wa = (wrist - a) --[[@as Vector3]]
        c.stretch = wa:Length() / (c.L1 + c.L2)
        local pole = Vector3(c.side * 0.2, 0, -1) -- 肘朝后、略外
        local elbow, wristC = SolveTwoBone(a, wrist, c.L1, c.L2, pole)
        local d1, d2 = elbow - a, wristC - elbow
        local q1 = Frame(d1, d2) * c.restFrame:Inverse()
        local q2 = Quaternion(c.r2, (q1:Inverse() * d2) --[[@as Vector3]])
        local q3 = (q1 * q2):Inverse() * footRot
        q[1], q[2], q[3] = q1, q2, q3
    end
    return q
end

return M
