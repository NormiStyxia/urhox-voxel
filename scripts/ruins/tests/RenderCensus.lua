-- 只由 -validate-test 加载：渲染开销普查。固定南门机位，逐项开关，
-- 统计批次/三角形（4 帧平均）与相对首个基线的差值。不截图。
local V = _G["V"]
local game
local stepIndex, wait = 0, 0
local base = nil

local function EachVoxel(fn)
    for _, child in ipairs(game.scene:GetChildren()) do
        if child.name == "VoxelVolume" then
            for _, c in ipairs(child:GetComponents("CustomGeometry", true)) do fn(c --[[@as Drawable]]) end
        end
    end
end
local function Histogram()
    local buckets = {}
    EachVoxel(function(d)
        local r = d.worldBoundingBox.size:Length() * 0.5
        local key = r < 0.6 and "a<0.6" or r < 1.5 and "b<1.5" or r < 3.5 and "c<3.5" or r < 8 and "d<8" or "e>=8"
        local b = buckets[key] or { n = 0, cast = 0 }
        b.n = b.n + 1
        if d.castShadows then b.cast = b.cast + 1 end
        buckets[key] = b
    end)
    for _, k in ipairs({ "a<0.6", "b<1.5", "c<3.5", "d<8", "e>=8" }) do
        local b = buckets[k] or { n = 0, cast = 0 }
        print(string.format("Census: radius %-6s drawables=%5d casting=%5d", k, b.n, b.cast))
    end
end
local saved = {}
local steps = {
    { name = "settle", fn = function() Histogram() end },
    { name = "current", fn = function() end },
    { name = "noShadows", fn = function() game.sun.castShadows = false end, undo = function() game.sun.castShadows = true end },
    { name = "mid35", fn = function()
        EachVoxel(function(d)
            local r = d.worldBoundingBox.size:Length() * 0.5
            saved[d] = d.shadowDistance
            if r < 8 then d.shadowDistance = math.max(25, r * 30) end
        end)
    end, undo = function() for d, v in pairs(saved) do d.shadowDistance = v end; saved = {} end },
    { name = "big90", fn = function()
        EachVoxel(function(d)
            saved[d] = d.shadowDistance
            if d.shadowDistance == 0 then d.shadowDistance = 90 end
        end)
    end, undo = function() for d, v in pairs(saved) do d.shadowDistance = v end; saved = {} end },
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
