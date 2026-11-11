-- 临时：吐息过曝复现截图（validate-test 注入，验证后删除）
local MODE = "info"
local VARIANT = nil
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

local function DumpInfo(T)
    local z = T.zone
    print(string.format("[BreathShot] platform=%s native=%s api=%s compute=%s",
        tostring(GetPlatform()), tostring(GetNativePlatform()),
        tostring(graphics:GetApiName()), tostring(graphics:GetComputeShaderSupport())))
    if z ~= nil then
        print(string.format("[BreathShot] zone bloomMode=%s ueI=%.3f ueT=%.3f plus=%.3f th=%.2f w=%.2f tonemap=%s exp=%s expPlus=%s minB=%.1f maxB=%.1f bias=%.1f force=%s",
            tostring(z.bloomMode), z.bloomUEIntensity or -9, z.bloomUEThreshold or -9,
            z.bloomPlusIntensity or -9, z.bloomThreshold or -9, z.bloomWeight or -9,
            tostring(z.tonemapMode), tostring(z.autoExposureEnabled), tostring(z.autoExposurePlusEnabled),
            z.autoExposureMinBrightness or -9, z.autoExposureMaxBrightness or -9,
            z.autoExposureBias or -9, tostring(z.autoExposureForceTarget)))
    end
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
        DumpInfo(T)
    end
    if frames >= 6 then T.cam.yaw, T.cam.pitch, T.cam.dist = 150.0, 10.0, 12.0 end
    if not fired and frames >= 10 then
        fired = true
        local ok = T.breath:Trigger()
        print("[BreathShot] trigger=" .. tostring(ok) .. " state=" .. tostring(c.state))
    end
    if c.state == "BREATH" then
        local t = c.stateT or 0
        if got.a == nil and t > 1.3 then got.a = true; Grab("v_" .. MODE .. "_a") end
        if got.b == nil and t > 2.2 then got.b = true; Grab("v_" .. MODE .. "_b") end
    end
end

for n = 5, 300 do V.atFrame(n, Tick) end
print("[BreathShot] loaded mode=" .. MODE)
report = function() print("[BreathShot] done"); V.finish() end
