-- 独立光照回归入口，不需要创建完整遗迹场景。
local DayNight = require("ruins.DayNight")
local V = _G["V"] or { assert = function(ok, message) assert(ok, message) end }
---@type Scene?
local scene_ = nil
---@type DayNight?
local dayNight_ = nil

local function Fixture(hour)
    local capture = { supported = true, capturing = false, requests = 0 }
    function capture:RequestCapture() self.requests = self.requests + 1 end
    local state = { hour = hour, speed = 1 / 120, fast = false,
        captureElapsed = 0, capturePending = true, capture = capture, applied = 0 }
    function state:Apply() self.applied = self.applied + 1 end
    return setmetatable(state, DayNight) --[[@as DayNight]], capture, state
end

local function CheckLighting()
    local dn, capture, state = Fixture(16)
    for _ = 1, 600 do dn:Update(1 / 60) end
    V.assert(state.applied == 600, "太阳逐帧更新，不再每6秒跳转")
    V.assert(capture.requests == 2, "常速10秒只请求初始与一次环境捕获")
    dn.fast = true
    local count = capture.requests
    for _ = 1, 60 do dn:Update(1 / 60) end
    V.assert(capture.requests - count <= 2, "快进环境捕获不超过每秒2次")
    capture.capturing = true
    count = capture.requests
    for _ = 1, 180 do dn:Update(1 / 60) end
    V.assert(capture.requests == count, "正在捕获时不重复排队")
    capture.capturing = false
    dn:Update(1 / 60)
    V.assert(capture.requests == count + 1, "完成后取最新时刻，不补发历史捕获")

    local locked, lockedCapture, lockedState = Fixture(12)
    locked.lockHour = 12
    for _ = 1, 120 do locked:Update(1 / 60) end
    V.assert(lockedCapture.requests == 1 and lockedState.applied == 0,
        "固定白天只捕获一次，且不重复设置光照")
    locked:SetHour(16)
    locked.lockHour = 16
    locked:Update(1 / 60)
    V.assert(lockedCapture.requests == 2, "手动改时间在固定时刻下也能刷新环境光")
    lockedCapture.supported = false
    locked:SetHour(18)
    locked:Update(1 / 60)
    V.assert(lockedCapture.requests == 2, "不支持捕获的设备不发出请求")

    local midnight, midnightCapture = Fixture(23.99)
    midnight:Update(0)
    midnight:Update(0.6)
    V.assert(midnight.hour < 0.01 and midnightCapture.requests == 1,
        "跨24点的小幅变化不会被当成整日跳转")
    for _ = 1, 180 do midnight:Update(1 / 60) end
    V.assert(midnightCapture.requests >= 2, "跨日后环境捕获仍能按时间变化继续")

    local actual = dayNight_
    V.assert(actual ~= nil, "原生光照测试场景初始化成功")
    if actual == nil then return end
    actual:SetHour(16)
    local previous = actual.sunNode.direction
    local changed = 0
    local maxDistance = 0.0
    for _ = 1, 600 do
        actual:Update(1 / 60)
        local current = actual.sunNode.direction
        local distance = (current - previous):Length()
        if distance > 1e-7 then changed = changed + 1 end
        maxDistance = math.max(maxDistance, distance)
        previous = current
    end
    V.assert(changed == 600 and maxDistance < 0.001,
        "原生灯光方向连续移动，无6秒台阶式位移")
    V.assert(actual.capture.updateMode == SKY_CAPTURE_MANUAL
        and actual.capture.resolution == 64 and actual.capture.timeSliced,
        "环境捕获使用64像素、分帧、手动节流预算")
    print(string.format("DayNightTest: direction changed %d/600, max step %.7f", changed, maxDistance))
end

function Start()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    local env = scene_:CreateChild("Environment")
    local zone = env:CreateComponent("Zone")
    zone.boundingBox = BoundingBox(-100, 100)
    local sunNode = scene_:CreateChild("Sun")
    local sun = sunNode:CreateComponent("Light")
    sun.lightType = LIGHT_DIRECTIONAL
    dayNight_ = DayNight.New({ scene = scene_, zone = zone, zoneNode = env,
        sun = sun, sunNode = sunNode, hour = 16 })
    local camera = scene_:CreateChild("Camera"):CreateComponent("Camera")
    renderer:SetViewport(0, Viewport:new(scene_, camera))
    if V.atFrame then V.atFrame(5, CheckLighting) else CheckLighting() end
end
