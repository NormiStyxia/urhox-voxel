-- 临时：吐息截图验证（验证后删除）
local frames, fired, got = 0, false, {}
local OUT = "/workspace/screenshots/"
local function Grab(name)
    local img = Image()
    if graphics:TakeScreenShot(img) then img:SavePNG(OUT..name..".png"); print("[BreathShot] saved "..name)
    else print("[BreathShot] FAILED "..name) end
end
local function Tick()
    frames = frames + 1
    local T = DRAGON_TEST
    if T == nil or T.ctrl == nil then return end
    local c = T.ctrl
    if frames == 3 then
        T.playMode = false; T.cam.follow = false; T.cam.target = Vector3(0, 2.0, 0)
        print("[BreathShot] platform="..tostring(GetPlatform()).." lowfx="..tostring(require("dragon.DragonBreath").LOW_FX))
    end
    if frames >= 6 then T.cam.yaw, T.cam.pitch, T.cam.dist = 150.0, 10.0, 12.0 end
    if not fired and frames >= 10 then
        fired = true
        local ok = T.breath:Trigger()
        print("[BreathShot] trigger="..tostring(ok).." state="..tostring(c.state))
    end
    if c.state == "BREATH" then
        local t = c.stateT or 0
        if got.a == nil and t > 1.6 then got.a = true; Grab("after_a") end
        if got.b == nil and t > 2.6 then got.b = true; Grab("after_b") end
    end
end
for n = 5, 300 do V.atFrame(n, Tick) end
report = function() print("[BreathShot] done"); V.finish() end
