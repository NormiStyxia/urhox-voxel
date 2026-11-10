-- 临时截图入口（不随项目发布）：VARIANT / TARGET_T / VIEW 由 sed 替换
local VARIANT = "large"
local TARGET_T = 3.8
local VIEW = 4
local frame = 0
local cfg = { noUI = true, noInput = true }
cfg.setup = function(T)
    if VARIANT ~= T.variant then T.SetVariant(VARIANT) end
    T.SetPlayMode(false)
    T.showNomi = false
    T.externalDrive = true
    T.cam.follow = false
    local S = T.rig.size or 1.0
    if VIEW == 4 then
        -- 看落点：前方地面
        T.cam.yaw, T.cam.pitch, T.cam.dist = 180 + 100, 24, 13 * S
        T.cam.target = Vector3(0, 0.8 * S, -9.0 * S)
    elseif VIEW == 3 then
        -- 侧视：龙在原点面朝 -Z（偏航 180°），镜头在 +X 侧
        T.cam.yaw, T.cam.pitch, T.cam.dist = -90, 12, 20 * S
        T.cam.target = Vector3(0, 2.2 * S, -5.5 * S)
    elseif VIEW == 1 then
        T.cam.yaw, T.cam.pitch, T.cam.dist = 180 + 120, 14, 19 * S
        T.cam.target = Vector3(-1.5 * S, 2.0 * S, -5.0 * S)
    else
        T.cam.yaw, T.cam.pitch, T.cam.dist = 180 + 160, 10, 15 * S
        T.cam.target = Vector3(0, 3.0 * S, -2.5 * S)
    end
end
cfg.update = function(T, dt)
    frame = frame + 1
    local c = T.ctrl
    if frame == 3 then print("SHOT trigger", T.breath:Trigger()) end
    -- 固定 1/60s 步长同时推进控制器和龙息特效，直到 TARGET_T；之后冻结（只保留极小步长让画面稳定）
    local steps = 0
    if frame < 3 then steps = 1
    elseif c.state == "BREATH" and c.stateT < TARGET_T then
        -- 用真实帧时间推进（引擎粒子按场景时间走，必须同步，否则截图时粒子已经消散）
        steps = 1
    end
    for _ = 1, steps do
        local ok, err = pcall(function() c:Update(math.min(dt, 1 / 30)); T.breath:Update() end)
        if not ok then print("SHOT ERR " .. tostring(err)); break end
    end
    -- 镜头跟随：VIEW 4 对准落点，其余对准龙口与落点之间
    local b0 = T.breath
    if b0 ~= nil and b0.hitPos ~= nil and frame > 3 then
        local S = T.rig.size or 1.0
        local mouth = T.rig.sockets.mouth.worldPosition
        if VIEW == 4 then
            T.cam.target = b0.hitPos + Vector3(0, 0.8 * S, 0)
            T.cam.dist = 12 * S; T.cam.pitch = 26; T.cam.yaw = T.ctrl.loco.yaw + 115
        else
            T.cam.target = (mouth + b0.hitPos) * 0.5
        end
    end
    if frame % 20 == 0 then
        local b = T.breath
        local parts = {}
        for k, e in pairs(b.em) do parts[#parts + 1] = k .. "=" .. tostring(e.on) .. "/" .. tostring(e.rate) .. "/" .. tostring(e.node.enabled) .. "/" .. tostring(e.em.numParticles) end
        print("SHOT em " .. table.concat(parts, " ") .. " debris=" .. #b.debris.live .. " hidden=" .. tostring(b.hidden) .. " master=" .. b.master .. " root=" .. tostring(b.root.enabled))
    end
    if frame % 20 == 0 and b0.hitPos ~= nil then print("SHOT hit", b0.hitPos.x, b0.hitPos.y, b0.hitPos.z, "yaw", T.ctrl.loco.yaw, "tgt", T.cam.target.x, T.cam.target.y, T.cam.target.z) end
    if frame % 20 == 0 then print(string.format("SHOT frame %d state %s t=%.2f shake=%.2f motes=%d", frame, c.state, c.stateT, T.breath.shake, T.breath.motes:Count())) end
end
BREATH_SHOT_CFG = cfg
local DragonTest = require("dragon.DragonTest")
function Start() DragonTest.Start() end
function Stop() DragonTest.Stop() end
