local frames, fired, got = 0, false, {}
local OUT = "/workspace/screenshots/"
local function Grab(n) local i=Image() if graphics:TakeScreenShot(i) then i:SavePNG(OUT..n..".png"); print("[BSim2] "..n) end end
local function Tick()
    frames = frames + 1
    local T = DRAGON_TEST
    if T == nil or T.ctrl == nil then return end
    local c = T.ctrl
    if frames == 3 then
        T.playMode=false; T.cam.follow=false; T.cam.target=Vector3(0,2.0,0)
        local z = T.zone
        z.tonemapMode = TONEMAP_MODE_ACES
        z.bloomMode = BLOOM_MODE_UE
        z.bloomUEThreshold = 1.2
        z.bloomUEIntensity = 0.45
        print("[BSim2] forced-lowfx sim: aces+th1.2+ueI0.45 lowfx="..tostring(require("dragon.DragonBreath").LOW_FX))
    end
    if frames >= 6 then T.cam.yaw,T.cam.pitch,T.cam.dist = 150.0,10.0,12.0 end
    if not fired and frames >= 10 then fired=true; print("[BSim2] trig="..tostring(T.breath:Trigger())) end
    if c.state == "BREATH" then
        local t=c.stateT or 0
        if got.a==nil and t>1.6 then got.a=true; Grab("f_a") end
        if got.b==nil and t>2.6 then got.b=true; Grab("f_b") end
    end
end
for n=5,300 do V.atFrame(n, Tick) end
report=function() print("[BSim2] done"); V.finish() end
