-- ====================================================================
-- DayNight.lua — 昼夜 / 晨昏循环
--
-- ProceduralSky 画天空与太阳，SkyLightCapture 把天空实时捕获成环境光（漫反射 SH + 反射），
-- 本模块按"游戏时刻"驱动：太阳方向、太阳色温与亮度、天空四色、雾色（= 地平线色，无接缝）、
-- 体积雾散射色。夜里同一盏方向光转成冷色月光（低亮度、仍投影）。
--
-- 时间流速：白天 1 游戏小时 ≈ 120 秒；夜里 3 倍速（不让玩家在黑夜里待太久）。
-- 按住 T 快进（×30）。M.SetHour(h) 直接跳到某个时刻（测试 / 截图）。
-- ====================================================================

---@class DayNight
---@field zone Zone
---@field sun Light
---@field sunNode Node
---@field sky ProceduralSky
---@field capture SkyLightCapture
---@field hour number
---@field speed number
---@field fast boolean
---@field lockHour number|nil 非 nil 时时间固定在该时刻（调试面板「固定白天」）
---@field lastCapturedHour number|nil
---@field elev number|nil
---@field day number|nil
---@field dusk number|nil
---@field nightK number|nil
---@field captureElapsed number
---@field capturePending boolean
local M = {}
M.__index = M

local function Clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
local function SmoothStep(e0, e1, x)
    local t = Clamp((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)
end

-- sRGB 调色（拾色器里取的值）
local TOP_DAY, TOP_DUSK, TOP_NIGHT = Color(0.24, 0.44, 0.82), Color(0.30, 0.34, 0.62), Color(0.05, 0.08, 0.20)
local HOR_DAY, HOR_DUSK, HOR_NIGHT = Color(0.70, 0.80, 0.93), Color(1.00, 0.56, 0.30), Color(0.14, 0.18, 0.32)
local GND_DAY, GND_NIGHT = Color(0.42, 0.40, 0.33), Color(0.04, 0.05, 0.08)
local SUN_DAY, SUN_GOLD, SUN_RED = Color(1.0, 0.95, 0.86), Color(1.0, 0.72, 0.42), Color(1.0, 0.42, 0.22)
local MOON = Color(0.55, 0.68, 1.0)

---@param o table { scene, zone, zoneNode, sun(Light), sunNode, hour }
---@return DayNight
function M.New(o)
    local self = setmetatable({}, M) --[[@as DayNight]]
    self.zone = o.zone
    self.sun = o.sun
    self.sunNode = o.sunNode
    self.hour = o.hour or 12.0
    self.speed = 1.0 / 120.0 -- 游戏小时 / 秒
    self.fast = false
    self.captureElapsed, self.capturePending = 0, true
    -- 直射光逐帧移动；环境光捕获独立节流，不能让阴影跟着捕获间隔跳动。
    self.capture = o.zoneNode:CreateComponent("SkyLightCapture")
    self.capture.updateMode = SKY_CAPTURE_MANUAL
    self.capture.resolution = 64
    self.capture.timeSliced = true
    self.capture.minCaptureInterval = 0.5
    if self.capture.supported then
        self.zone.envTextureDiffIntensity = 0.7
        self.zone.envTextureSpecIntensity = 0.45
    else
        print("DayNight: SkyLightCapture not supported, keeping preset ambient")
    end
    local skyNode = o.scene:CreateChild("Sky")
    self.sky = skyNode:CreateComponent("ProceduralSky")
    self.sky.sunLight = self.sun
    self.sky.skyCurve = 0.18
    self.sky.groundCurve = 0.06
    self.sky.sunDiskSize = 1.6
    self.sky.sunCurve = 0.08
    self:Apply()
    print(string.format("DayNight: ready, hour %.1f, capture %s (manual, 64px, time-sliced)", self.hour, tostring(self.capture.supported)))
    return self
end

function M:SetHour(h)
    self.hour = h % 24
    self:Apply()
    self.capturePending = true
end

-- 当前时段名（HUD 用）
function M:PhaseName()
    local h = self.hour
    if h >= 5.0 and h < 7.0 then return "黎明" end
    if h >= 7.0 and h < 16.5 then return "白昼" end
    if h >= 16.5 and h < 19.2 then return "黄昏" end
    return "夜晚"
end

function M:ClockText()
    local h = self.hour
    return string.format("%s %02d:%02d", self:PhaseName(), math.floor(h), math.floor((h % 1) * 60))
end

function M:Update(dt)
    self.captureElapsed = self.captureElapsed + math.max(0, dt)
    if self.lockHour ~= nil then
        if math.abs(self.hour - self.lockHour) > 1e-4 then self:SetHour(self.lockHour) end
    else
        local h = self.hour
        local night = (h < 5.2 or h > 19.6)
        local rate = self.speed * (night and 3.0 or 1.0) * (self.fast and 30.0 or 1.0)
        self.hour = (h + dt * rate) % 24
        if self.hour ~= h then self:Apply() end
    end
    -- 捕获昂贵，太阳方向并不昂贵：常速仍约每 6 秒捕获，快进最多每 0.5 秒一次。
    -- 24 点跨日按环形距离判断；正在捕获时不排队，完成后只取最新天空。
    local distance = math.abs(self.hour - (self.lastCapturedHour or self.hour))
    distance = math.min(distance, 24 - distance)
    local capture = self.capture
    if capture.supported and not capture.capturing
        and (self.capturePending or distance >= 0.05)
        and (self.lastCapturedHour == nil or self.captureElapsed >= 0.5) then
        capture:RequestCapture()
        self.captureElapsed, self.capturePending = 0, false
        self.lastCapturedHour = self.hour
    end
end

function M:Apply()
    local h = self.hour
    -- 太阳：6 点东升（+X），12 点最高（偏南，柱廊投影落在龙庭里），18 点西落
    local ang = (h - 6.0) / 12.0 * math.pi
    local elev = math.sin(ang)                -- -1..1
    local sunDir = Vector3(-math.cos(ang), -math.max(-1, elev) * 0.85, 0.45):Normalized()
    local day = SmoothStep(-0.08, 0.30, elev)
    local dusk = math.exp(-((elev - 0.04) / 0.16) ^ 2)
    local nightK = 1.0 - SmoothStep(-0.22, -0.04, elev)
    self.elev, self.day, self.dusk, self.nightK = elev, day, dusk, nightK

    local horizon = HOR_NIGHT:Lerp(HOR_DAY, day):Lerp(HOR_DUSK, dusk * 0.85)
    local sky = self.sky
    sky.skyTopColor = TOP_NIGHT:Lerp(TOP_DAY, day):Lerp(TOP_DUSK, dusk * 0.4)
    sky.skyHorizonColor = horizon
    sky.groundHorizonColor = horizon
    sky.groundBottomColor = GND_NIGHT:Lerp(GND_DAY, day)
    sky.sunEnergy = 1.0 * (1 - nightK) + 0.15 * nightK

    local sun = self.sun
    if elev > -0.06 then
        -- 白天 / 晨昏：暖色太阳，地平线附近转金→橙红
        self.sunNode.direction = sunDir
        local warm = SUN_RED:Lerp(SUN_GOLD, SmoothStep(-0.02, 0.18, elev)):Lerp(SUN_DAY, SmoothStep(0.18, 0.55, elev))
        sun.color = warm
        sun.brightness = 2.3 * SmoothStep(-0.06, 0.12, elev) + 0.2
    else
        -- 夜：同一盏灯做月光（从西南高处照下）
        local m = (h + 12.0 - 6.0) / 12.0 * math.pi
        self.sunNode.direction = Vector3(-math.cos(m) * 0.7, -0.75, -0.45):Normalized()
        sun.color = MOON
        sun.brightness = 0.55 * SmoothStep(-0.06, -0.25, elev) + 0.1
    end
    -- 雾：颜色跟地平线；夜里雾更近一点，压住远山
    local zone = self.zone
    zone.fogColor = horizon
    zone.volumetricFogScatteringColor = Color(1, 1, 1):Lerp(Color(1.0, 0.72, 0.5), dusk * 0.7):Lerp(MOON, nightK * 0.8)
end

return M
