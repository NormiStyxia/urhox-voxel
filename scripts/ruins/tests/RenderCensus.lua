-- 只由 -validate-test 加载：渲染开销普查。固定南门机位，逐项开关，
-- 统计批次/三角形（4 帧平均）与相对首个基线的差值。不截图。
local V = _G["V"]
local game
local stepIndex, wait = 0, 0
local base = nil

local steps = {
    { name = "settle", fn = function() end },
    { name = "current", fn = function() end },
    { name = "noShadows", fn = function() game.sun.castShadows = false end, undo = function() game.sun.castShadows = true end },
    { name = "noGrass", fn = function()
        local T = require("ruins.RuinsTerrain")
        if T.grass then T.grass.enabled = false end
        if T.flowers then T.flowers.enabled = false end
    end, undo = function()
        local T = require("ruins.RuinsTerrain")
        if T.grass then T.grass.enabled = true end
        if T.flowers then T.flowers.enabled = true end
    end },
    { name = "grass55", fn = function()
        local T = require("ruins.RuinsTerrain")
        if T.grass then T.grass.viewDistance = 55 end
    end, undo = function()
        local T = require("ruins.RuinsTerrain")
        if T.grass then T.grass.viewDistance = 48 end
    end },
    { name = "current2", fn = function() end },
    { name = "far", fn = function() game.farCam = true end, undo = function() game.farCam = false end },
}

function Census_PostUpdate(eventType, eventData)
    Ruins_HandlePostUpdate(eventType, eventData)
    local cn = game.nomiCtl:CameraNode()
    if game.farCam then
        cn.worldPosition = Vector3(300, 60, -300)
        cn:LookAt(Vector3(0, 0, 0), Vector3.UP)
    else
        cn.worldPosition = Vector3(4, 8.3, -74)
        cn:LookAt(Vector3(0, 7.1, -40), Vector3.UP)
    end
    if wait > 0 then
        wait = wait - 1
        if wait == 0 then
            local s = steps[stepIndex]
            s.b, s.p, s.k = (s.b or 0) + renderer:GetNumBatches(), (s.p or 0) + renderer:GetNumPrimitives(), (s.k or 0) + 1
            if s.k < 4 then wait = 1; return end
            local b, p = s.b / s.k, s.p / s.k
            if not base then base = { b = b, p = p } end
            print(string.format("Census: step %-10s batches=%6.0f (%+6.0f) primitives=%8.0f (%+8.0f)", s.name, b, b - base.b, p, p - base.p))
            if s.undo then s.undo() end
        end
        return
    end
    stepIndex = stepIndex + 1
    local s = steps[stepIndex]
    if not s then return end
    s.fn()
    wait = 30
end

V.atFrame(4, function()
    game = _G["RUINS"]
    local Settings = require("ruins.GameSettings")
    Settings.Set("quality", "high")
    Settings.Set("volumetric", false)
    game.dayNight.lockHour = 12
    game.dayNight:SetHour(12)
    game.nomiCtl.node:SetDeepEnabled(false)
    SubscribeToEvent("PostUpdate", "Census_PostUpdate")
end)
