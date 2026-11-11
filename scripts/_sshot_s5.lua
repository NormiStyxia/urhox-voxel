-- 临时截图：龙外皮
local VARIANT = "small"
local YAW, PITCH, DIST, TY, TZ, SKIN = 145, 10, 16, 2.2, 0, true
SHOT_OUT = "_shot_s5.png"
local frame = 0
local cfg = { noUI = true, noInput = true }
cfg.setup = function(T)
    if VARIANT ~= T.variant then T.SetVariant(VARIANT) end
    T.SetPlayMode(false)
    T.showNomi = false
    T.cam.follow = false
    local S = T.rig.size or 1.0
    T.cam.yaw, T.cam.pitch, T.cam.dist = 180 + YAW, PITCH, DIST * S
    T.cam.target = Vector3(0, TY * S, TZ * S)
    if not SKIN then T.rig:SetSkinVisible(false) end
end
cfg.update = function(T, dt)
    frame = frame + 1
    local S = T.rig.size or 1.0
    T.cam.follow = false
    T.cam.yaw, T.cam.pitch, T.cam.dist = 180 + YAW, PITCH, DIST * S
    T.cam.target = Vector3(0, TY * S, TZ * S)
    if frame == 40 then
        local img = Image()
        graphics:TakeScreenShot(img)
        img:SavePNG(SHOT_OUT)
        print("SHOT saved", SHOT_OUT)
        engine:Exit()
    end
end
BREATH_SHOT_CFG = cfg
local DragonTest = require("dragon.DragonTest")
function Start() DragonTest.Start() end
function Stop() DragonTest.Stop() end
