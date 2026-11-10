-- 临时截图入口（不随项目发布）：VARIANT / TARGET_T / VIEW 由 sed 替换
local VARIANT = "large"
local TARGET_T = 3.3
local VIEW = 2
local frame = 0
local cfg = { noUI = true, noInput = true }
cfg.setup = function(T)
    for _, n in ipairs({"Techniques/DiffUnlitParticleAlpha.xml","Techniques/DiffUnlitAlpha.xml","Techniques/DiffAddAlpha.xml","Techniques/DiffAlpha.xml","Techniques/DiffVColUnlitAlpha.xml"}) do
        print("PROBE", n, cache:Exists(n))
    end
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
    if frame >= 3 and c.state == "BREATH" and c.stateT < TARGET_T then
        for _ = 1, 4 do if c.stateT < TARGET_T then c:Update(1 / 60) end end
    elseif frame < 3 then
        c:Update(1 / 60)
    end
    if frame % 20 == 0 then print(string.format("SHOT frame %d state %s t=%.2f aim=%.1f", frame, c.state, c.stateT, c.breathAim or 0)) end
end
BREATH_SHOT_CFG = cfg
local DragonTest = require("dragon.DragonTest")
function Start() DragonTest.Start() end
function Stop() DragonTest.Stop() end
