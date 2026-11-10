-- 体素巨龙动画自动检查（validate-test）：固定 1/60s 步长跑完整演示序列
local T = nil
local VARIANT = nil -- 型号：nil/"medium" = 中号，"small" / "large"（run_anim_check.sh 第一个参数）
local Ctrl = require("dragon.DragonAnimationController")
local DT = 1.0 / 60.0
local STEPS_PER_FRAME = 24
local TOTAL = 60 * 62

local ctrl, rig
local step = 0
local stats = {
    ikErrMax = 0, ikErrSum = 0, ikN = 0, drift = 0, driftFoot = "", boneErr = 0, boneName = "",
    flip = 0, flipInfo = "", pop = 0, popName = "", popState = "", groundPen = 0, minFlightY = 1e9,
    visited = {}, nanCount = 0, stanceSamples = 0,
}
local prevRot = {}
local printedT = false
local dbgN = 0
local stanceStart = {}
local restLen = {}

local function contactPoint(f)
    local c = f.chain
    local tip = c.nodes[#c.nodes]
    return tip:LocalToWorld(c.footOff)
end

local function setup()
    if VARIANT ~= nil and VARIANT ~= T.variant then T.SetVariant(VARIANT) end
    ctrl, rig = T.ctrl, T.rig
    print("[DragonCheck] variant " .. tostring(T.variant) .. " size " .. tostring(rig.size))
    T.externalDrive = true
    for name, node in pairs(rig.bones) do
        local pn = rig.parents[name]
        if pn ~= nil and name:sub(1, 2) ~= "wm" then
            local a, b = rig.pivots[pn], rig.pivots[name]
            restLen[name] = Vector3(b[1] - a[1], b[2] - a[2], b[3] - a[3]):Length()
        end
    end
    ctrl:StartDemo()
end

local function angleBetween(q1, q2)
    local d = math.abs(q1:DotProduct(q2))
    if d > 1 then d = 1 end
    return math.deg(2 * math.acos(d))
end

local function check()
    local st = ctrl.state
    stats.visited[st] = true
    local grounded = (not ctrl.loco.airborne) and ctrl.ikW > 0.995
    -- 足底：IK 误差与支撑相漂移
    for _, f in ipairs(ctrl.gait.feet) do
        local fw = f.front and ctrl.ikFront or 1.0
        if grounded and fw > 0.995 and not f.swing and ctrl.state ~= "LAND" then
            local p = contactPoint(f)
            local e = (p - f.planted):Length()
            if e > stats.ikErrMax then stats.ikErrMax = e; stats.ikErrInfo = f.key .. "@" .. st .. string.format("@%.2fs", ctrl.stateT) end
            stats.ikErrSum, stats.ikN = stats.ikErrSum + e, stats.ikN + 1
            if stanceStart[f.key] == nil then stanceStart[f.key] = p end
            local dd = (p - stanceStart[f.key]); dd.y = 0
            if dd:Length() > stats.drift then stats.drift = dd:Length(); stats.driftFoot = f.key .. "@" .. st end
            stats.groundPen = math.min(stats.groundPen, p.y)
            stats.stanceSamples = stats.stanceSamples + 1
        else
            stanceStart[f.key] = nil
        end
    end
    -- 骨长恒定
    for name, L in pairs(restLen) do
        local node = rig.bones[name]
        local d = (node.worldPosition - node.parent.worldPosition):Length()
        -- body 是姿态层（有位移），armU 带肩胛滑动（设计上允许平移）
        if name ~= "body" and name ~= "pelvis" and name:sub(1, 4) ~= "armU" and name:sub(1, 2) ~= "wi" then
            local e = math.abs(d - L)
            if e > stats.boneErr then stats.boneErr, stats.boneName = e, name end
        end
    end
    -- 反关节：后膝在髋-跗连线前方，前肘在后方（身体坐标）
    for _, side in ipairs({ "_R", "_L" }) do
        local pel = rig.bones.pelvis
        local hip, knee, hock = rig.bones["legU" .. side].worldPosition, rig.bones["legL" .. side].worldPosition, rig.bones["legM" .. side].worldPosition
        local fwd = pel.worldRotation * Vector3.FORWARD
        local mid = (hip + hock) * 0.5
        if grounded and (knee - mid):DotProduct(fwd) < -0.02 then stats.flip = stats.flip + 1; stats.flipInfo = "knee" .. side .. "@" .. st end
        local ch = rig.bones.chest
        local sh, el, wr = rig.bones["armU" .. side].worldPosition, rig.bones["armL" .. side].worldPosition, rig.bones["hand" .. side].worldPosition
        local fwd2 = ch.worldRotation * Vector3.FORWARD
        if grounded and ctrl.ikFront > 0.5 and (el - (sh + wr) * 0.5):DotProduct(fwd2) > 0.02 then stats.flip = stats.flip + 1; stats.flipInfo = "elbow" .. side .. "@" .. st end
    end
    -- 关节跳变（单步角度变化）
    for name, node in pairs(rig.bones) do
        local q = node.rotation
        if q:IsNaN() then stats.nanCount = stats.nanCount + 1 end
        local pq = prevRot[name]
        if pq ~= nil then
            local a = angleBetween(pq, q)
            stats.popBy = stats.popBy or {}
            if a > (stats.popBy[st] or 0) then
                stats.popBy[st] = a
                stats.popWho = stats.popWho or {}
                stats.popWho[st] = string.format("%s@%.2fs ikW=%.2f ikF=%.2f alt=%.2f", name, ctrl.stateT, ctrl.ikW, ctrl.ikFront, ctrl.loco.alt)
            end
            if a > stats.pop then stats.pop, stats.popName, stats.popState = a, name, st .. string.format("@%.2fs", ctrl.stateT) end
        end
        if false then
            dbgN = (dbgN or 0) + 1
            local f = nil
            for _, ff in ipairs(ctrl.gait.feet) do if ff.key == "FR" then f = ff end end
            print(string.format("[DragonCheck] JUMP %s %.1f st=%s t=%.2f swing=%s ft=%.2f lift=%.2f str=%.3f gphase=%.3f act=%s layers=%d",
                name, angleBetween(pq, q), st, ctrl.stateT, tostring(f.swing), f.t or -1, f.lift, ctrl.chains.F_R.stretch or -1,
                ctrl.gait.phase, tostring(ctrl.gait.active), #ctrl.layers))
            print(string.format("[DragonCheck] TK t=%.3f d=%.1f ikF=%.2f ikW=%.2f strF=%.3f alt=%.2f dy=%.2f", ctrl.stateT,
                angleBetween(pq, q), ctrl.ikFront, ctrl.ikW, ctrl.chains.F_L.stretch or -1, ctrl.loco.alt, rig.body.position.y))
        end
        prevRot[name] = q
    end
    if st ~= "TAKEOFF" and stats.visited.TAKEOFF then printedT = true end
    -- 左右翼对称：左翼局部旋转应等于右翼的镜像（身体侧倾在 body 层，不进翼关节）
    for name, node in pairs(rig.bones) do
        if name:sub(1, 1) == "w" and name:sub(-2) == "_R" then
            local l = rig.bones[name:sub(1, -3) .. "_L"]
            if l ~= nil then
                local qr = node.rotation
                local m = Quaternion(qr.w, qr.x, -qr.y, -qr.z)
                local a = angleBetween(m, l.rotation)
                if a > (stats.asym or 0) then stats.asym, stats.asymName = a, name .. "@" .. st end
            end
        end
    end
    if ctrl.loco.airborne and ctrl.loco.alt > 2 then
        for _, n in ipairs({ "foot_R", "foot_L", "hand_R", "hand_L", "tail8", "head" }) do
            stats.minFlightY = math.min(stats.minFlightY, rig.bones[n].worldPosition.y)
        end
    end
end

local reported = false
local report
function DragonCheck_PostUpdate()
    if ctrl == nil then
        T = DRAGON_TEST
        if T ~= nil and T.ctrl ~= nil then setup(); print("[DragonCheck] setup ok") end
        return
    end
    for _ = 1, STEPS_PER_FRAME do
        if step >= TOTAL then
            if not reported then reported = true; report() end
            return
        end
        ctrl:Update(DT)
        check()
        step = step + 1
    end
end
for n = 8, 590 do V.atFrame(n, DragonCheck_PostUpdate) end
print("[DragonCheck] loaded")

report = function()
    local vis = {}
    for _, s in ipairs(Ctrl.STATE_ORDER) do vis[#vis + 1] = s .. "=" .. tostring(stats.visited[s] == true) end
    print(string.format("[DragonCheck] steps=%d state=%s visited: %s", step, ctrl.state, table.concat(vis, " ")))
    print(string.format("[DragonCheck] IK err at " .. tostring(stats.ikErrInfo)))
    print(string.format("[DragonCheck] IK err max=%.3f mean=%.4f m (n=%d)  stance drift max=%.4f m (%s)  ground pen min=%.3f",
        stats.ikErrMax, stats.ikErrSum / math.max(1, stats.ikN), stats.ikN, stats.drift, stats.driftFoot, stats.groundPen))
    print(string.format("[DragonCheck] bone length err max=%.5f (%s)  flips=%d (%s)  max step rot=%.1f deg (%s @ %s)  nan=%d  minFlightY=%.2f",
        stats.boneErr, stats.boneName, stats.flip, stats.flipInfo, stats.pop, stats.popName, stats.popState, stats.nanCount, stats.minFlightY))
    for _, s in ipairs(Ctrl.STATE_ORDER) do
        if s ~= "TURN" then V.assert(stats.visited[s] == true, "visited " .. s) end
    end
    V.assert(stats.visited.TURN == true, "visited TURN")
    V.assert(ctrl.state == "IDLE" and not ctrl.loco.airborne, "demo ends grounded in IDLE")
    local k = rig.size or 1.0 -- 距离阈值按型号尺度
    V.assert(stats.ikErrMax < 0.06 * k, string.format("IK foot error < %.1fcm (%.3f)", 6 * k, stats.ikErrMax))
    V.assert(stats.drift < 0.03 * k, string.format("stance foot drift < %.1fcm (%.4f)", 3 * k, stats.drift))
    V.assert(stats.boneErr < 0.005 * k, string.format("bone lengths constant (%.5f %s)", stats.boneErr, stats.boneName))
    V.assert(stats.flip == 0, "no knee/elbow flips (" .. stats.flipInfo .. ")")
    V.assert(stats.nanCount == 0, "no NaN rotations")
    local per = {}
    for _, s2 in ipairs(Ctrl.STATE_ORDER) do
        local a = (stats.popBy or {})[s2] or 0
        per[#per + 1] = string.format("%s=%.1f(%s)", s2, a, tostring((stats.popWho or {})[s2]))
        V.assert(a < ((s2 == "TAKEOFF") and 16 or 12), string.format("max joint step rotation %s %.1f deg", s2, a))
    end
    print("[DragonCheck] max step rot per state: " .. table.concat(per, " "))
    print(string.format("[DragonCheck] wing L/R mirror max diff=%.3f deg (%s)", stats.asym or 0, tostring(stats.asymName)))
    V.assert((stats.asym or 0) < 0.5, string.format("wings symmetric (%.3f)", stats.asym or 0))
    V.assert(stats.groundPen > -0.05 * k, string.format("feet not below ground (%.3f)", stats.groundPen))
    V.finish()
end
