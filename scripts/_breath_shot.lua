-- 临时：吐息过曝复现截图（validate-test 注入，验证后删除）
local MODE = "noexposure"
local VARIANT = nil
local VIEW = "side"
local frames, fired, got = 0, false, {}
local OUT = "/workspace/screenshots/"

local function Grab(name)
    local img = Image()
    if graphics:TakeScreenShot(img) then
        img:SavePNG(OUT .. name .. ".png")
        print("[BreathShot] saved " .. name)
    else
        print("[BreathShot] FAILED " .. name)
    end
end

local function SetupZone(T)
    local z = T.zone
    if z == nil then return end
    if MODE == "noexposure" then z:SetAttribute("Auto Exposure Enable", Variant(false))
    elseif MODE == "aces" then z.tonemapMode = TONEMAP_MODE_ACES
    elseif MODE == "bloomth" then z.bloomUEThreshold = 1.0
    elseif MODE == "nofog" then z:SetAttribute("Volumetric Fog Enabled", Variant(false)) end
    print(string.format("[BreathShot] mode=%s bloom=%s ueI=%.3f ueT=%.3f exp=%s",
        MODE, tostring(z.bloomMode), z.bloomUEIntensity or -9, z.bloomUEThreshold or -9, tostring(z.autoExposureEnabled)))
end

local function Tick()
    frames = frames + 1
    local T = DRAGON_TEST
    if T == nil or T.ctrl == nil then return end
    local c = T.ctrl
    if frames == 3 then
        if VARIANT ~= nil then T.SetVariant(VARIANT) end
        T.playMode = false
        T.cam.follow = false
        T.cam.target = Vector3(0, 2.0, 0)
    end
    if frames >= 6 and frames <= 60 then
        T.cam.yaw, T.cam.pitch, T.cam.dist = 150.0, 10.0, 12.0
    end
    if not fired and frames >= 10 then
        fired = true
        SetupZone(T)
        local ok = T.breath:Trigger()
        print("[BreathShot] trigger=" .. tostring(ok) .. " state=" .. tostring(c.state))
    end
    if c.state == "BREATH" then
        local t = c.stateT or 0
        if got.a == nil and t > 1.3 then got.a = true; Grab("v_" .. MODE .. "_a") end
        if got.b == nil and t > 2.2 then got.b = true; Grab("v_" .. MODE .. "_b") end
        if got.c == nil and t > 3.2 then got.c = true; Grab("v_" .. MODE .. "_c") end
    end
end

for n = 5, 300 do V.atFrame(n, Tick) end
print("[BreathShot] loaded mode=" .. MODE)
report = function() print("[BreathShot] done"); V.finish() end
