-- ====================================================================
-- DragonGait.lua — 四足步态规划（世界空间落足点）
--
-- 四拍横向序列步态（蜥蜴 / 大型猫科的慢走）：左后 → 左前 → 右后 → 右前，
-- 相位差 0.25，支撑占空比 duty ≈ 0.7。
--   * 支撑相：足底钉在世界坐标不动（不滑步），身体从上方移过；
--   * 摆动相：抬脚 → 前摆 → 落地，落点 = 预测落地时刻的静止足位 + 半个支撑行程，
--     每帧重新预测，所以转向、变速时落点跟着调整；
--   * 步频随速度（和转身角速度）变化，步幅 = 速度 / 步频，二者联动；
--   * 速度为零时停步；若某只脚离理想位置太远（原地转身、被推动），自动补一步。
-- ====================================================================

local M = {}

-- 顺序：HL, FL, HR, FR
M.OFFSETS = { HL = 0.0, FL = 0.25, HR = 0.5, FR = 0.75 }

local function Smooth(t) return t * t * (3 - 2 * t) end

---@param feet table[] { key, chain, side }
---@param scale number|nil 型号尺度（中号 = 1）：补步阈值按它缩放
---@param leg number|nil 腿长比例（髋高 / 中号髋高）：抬脚高度按它缩放；步速按腿长归一，
---  步频 ∝ 腿长^-0.4（短腿迈得快，比动力相似的 -0.5 略缓，避免小号腿部动作过碎）。转身的步频不随体型变，保证每步转过的角度一致
function M.New(feet, scale, leg)
    scale = scale or 1.0
    leg = leg or scale
    local g = { feet = {}, phase = 0.0, duty = 0.66, freq = 0.0, active = false, stepHeight = 0.28 * leg, scale = scale,
        leg = leg, cadence = leg ^ -0.4 }
    for _, f in ipairs(feet) do
        g.feet[#g.feet + 1] = {
            key = f.key, chain = f.chain, side = f.side, front = f.key:sub(1, 1) == "F",
            offset = M.OFFSETS[f.key], restRoot = f.chain.footRestRoot,
            planted = nil, swing = false, t = 0, from = nil, pos = nil, lift = 0.0, inWindow = false,
        }
    end
    return g
end

local function RestWorld(foot, rootPos, yaw)
    return rootPos + Quaternion(yaw, Vector3.UP) * foot.restRoot
end

-- 所有脚落在当前 root 的静止足位
function M.Reset(g, rootPos, yaw, groundFn)
    for _, f in ipairs(g.feet) do
        local p = RestWorld(f, rootPos, yaw)
        p.y = groundFn(p.x, p.z)
        f.planted, f.pos, f.swing, f.lift, f.t = p, p, false, 0.0, 0.0
    end
end

---@param ctx table { pos, yaw, vel(Vector3), yawRate(度/秒), groundFn, speedScale }
function M.Update(g, dt, ctx)
    local v = ctx.vel
    local speed = math.sqrt(v.x * v.x + v.z * v.z)
    local sc, leg = g.scale or 1.0, g.leg or 1.0
    local wTurn = math.abs(math.rad(ctx.yawRate)) * 1.5
    local veff = math.max(speed, wTurn)
    -- 大型动物步频低、步幅大：1.6 m/s 时约 0.8 Hz、步幅约 2 m（中号）
    local fWalk = math.min(1.5, 0.42 + 0.24 * speed / leg) * (g.cadence or 1.0)
    local fTurn = math.min(1.5, 0.42 + 0.24 * wTurn) * math.max(1.0, g.cadence or 1.0)
    local freq = math.max(fWalk, fTurn) * (ctx.cadence or 1.0)
    g.freq = freq
    local duty = g.duty
    local swingDur = (1.0 - duty) / freq
    local stanceDur = duty / freq

    -- 离理想足位最远的那只脚
    local maxErr = 0.0
    for _, f in ipairs(g.feet) do
        if not f.swing then
            local r = RestWorld(f, ctx.pos, ctx.yaw)
            local dx, dz = f.planted.x - r.x, f.planted.z - r.z
            f.err = math.sqrt(dx * dx + dz * dz)
            maxErr = math.max(maxErr, f.err)
        end
    end
    local anySwing = false
    for _, f in ipairs(g.feet) do if f.swing then anySwing = true end end
    local moving = veff > 0.06
    g.active = moving or anySwing or maxErr > 0.22 * sc
    if g.active then g.phase = (g.phase + freq * dt) % 1.0 end

    for _, f in ipairs(g.feet) do
        local u = (g.phase - f.offset) % 1.0
        local inWindow = g.active and u < (1.0 - duty)
        if inWindow and not f.inWindow and not f.swing then
            -- 进入摆动窗口：移动中必迈步；静止时只修正偏差大的脚
            if moving or (f.err or 0) > 0.1 * sc then
                f.swing, f.t, f.from = true, 0.0, f.planted
                f.dur = swingDur
            end
        end
        f.inWindow = inWindow
        if f.swing then
            f.t = math.min(1.0, f.t + dt / f.dur)
            -- 预测落地：剩余摆动时间后的 root 位姿 + 半个支撑行程
            local tl = (1.0 - f.t) * f.dur
            local yawL = ctx.yaw + ctx.yawRate * (tl + stanceDur * 0.5)
            local posL = ctx.pos + v * (tl + stanceDur * 0.5)
            local target = RestWorld(f, posL, yawL)
            target.y = ctx.groundFn(target.x, target.z)
            local s = Smooth(f.t)
            local p = f.from:Lerp(target, s)
            local h = g.stepHeight * (0.7 + 0.3 * math.min(1.0, speed / (2.0 * math.sqrt(sc)))) * (f.front and 1.0 or 0.9)
            f.lift = math.sin(math.pi * f.t)
            p.y = p.y + h * f.lift
            f.pos = p
            if f.t >= 1.0 then
                f.swing, f.planted, f.pos, f.lift = false, target, target, 0.0
            end
        else
            f.pos = f.planted
            f.lift = 0.0
        end
    end
end

-- 步态带来的身体运动：重心下沉、向支撑侧侧倾
function M.BodyMotion(g)
    local drop, roll, pitch = 0.0, 0.0, 0.0
    for _, f in ipairs(g.feet) do
        drop = drop + f.lift
        roll = roll + f.lift * f.side
        pitch = pitch + f.lift * (f.front and 1 or -1)
    end
    return drop, roll, pitch
end

return M
