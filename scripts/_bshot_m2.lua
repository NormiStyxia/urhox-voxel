-- 临时截图入口（不随项目发布）：VARIANT / TARGET_T / VIEW 由 sed 替换
local VARIANT = "medium"
local TARGET_T = 1.9
local VIEW = 1
local frame = 0
local cfg = { noUI = true, noInput = true }
cfg.setup = function(T)
    if VARIANT ~= T.variant then T.SetVariant(VARIANT) end
    T.SetPlayMode(false)
    T.showNomi = false
    T.externalDrive = true
    T.cam.follow = false
    local S = T.rig.size or 1.0
    if VIEW == 1 then
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
    elseif c.state == "BREATH" and c.stateT < TARGET_T then steps = 2 end
    for _ = 1, steps do
        c:Update(1 / 60)
        T.breath:Update()
    end
    if frame % 20 == 0 then print(string.format("SHOT frame %d state %s t=%.2f shake=%.2f motes=%d", frame, c.state, c.stateT, T.breath.shake, T.breath.motes:Count())) end
end
BREATH_SHOT_CFG = cfg
local DragonTest = require("dragon.DragonTest")
function Start() DragonTest.Start() end
function Stop() DragonTest.Stop() end
