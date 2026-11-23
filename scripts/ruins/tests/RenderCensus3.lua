-- 只由 -validate-test 加载：玩家视角（诺米可见）下的角色投影与遮挡剔除实验。
-- 第三人称机位跟随出生点诺米，正午。每步读 3 帧平均批次/三角形。
local V = _G["V"]
local game
local stepIndex, wait = 0, 0
local base
local nomiCasters = {}
local orig = {}

local function NomiDrawables(fn)
    for _, t in ipairs({ "CustomGeometry", "StaticModel", "AnimatedModel" }) do
        for _, c in ipairs(game.nomiCtl.node:GetComponents(t, true)) do fn(c --[[@as Drawable]]) end
    end
end

local steps = {
    { name = "baseline", fn = function()
        local n, cast = 0, 0
        NomiDrawables(function(d) n = n + 1; if d.castShadows then cast = cast + 1 end end)
        print(string.format("Census3: nomi drawables=%d casters=%d", n, cast))
        local hist = {}
        NomiDrawables(function(d)
            local r = d.worldBoundingBox.size:Length() * 0.5
            local key = r < 0.03 and "a<3cm" or r < 0.06 and "b<6cm" or r < 0.12 and "c<12cm" or r < 0.25 and "d<25cm" or "e>=25cm"
            local h = hist[key] or { n = 0, cast = 0, names = {} }
            h.n = h.n + 1
            if d.castShadows then h.cast = h.cast + 1 end
            if #h.names < 8 then h.names[#h.names + 1] = d.node.name end
            hist[key] = h
        end)
        for _, k in ipairs({ "a<3cm", "b<6cm", "c<12cm", "d<25cm", "e>=25cm" }) do
            local h = hist[k] or { n = 0, cast = 0, names = {} }
            print(string.format("Census3: nomi radius %-7s n=%3d cast=%3d e.g. %s", k, h.n, h.cast, table.concat(h.names, ",")))
        end
        print(string.format("Census3: occlusion maxTris=%d buffer=%d threshold=%.3f",
            renderer.maxOccluderTriangles, renderer.occlusionBufferSize, renderer.occluderSizeThreshold))
    end },
    { name = "nomiSmallNoShadow", fn = function()
        NomiDrawables(function(d)
            if d.castShadows and d.worldBoundingBox.size:Length() * 0.5 < 0.12 then nomiCasters[#nomiCasters + 1] = d; d.castShadows = false end
        end)
        print("Census3: small nomi casters disabled " .. #nomiCasters)
    end, undo = function() for _, d in ipairs(nomiCasters) do d.castShadows = true end end },
    { name = "occlusionOn", fn = function()
        orig.tris = renderer.maxOccluderTriangles
        renderer.maxOccluderTriangles = 5000
        local count = 0
        for _, child in ipairs(game.scene:GetChildren()) do
            if child.name == "VoxelVolume" then
                for _, c in ipairs(child:GetComponents("CustomGeometry", true)) do
                    local d = c --[[@as Drawable]]
                    if d.worldBoundingBox.size:Length() > 7 then d.occluder = true; count = count + 1 end
                end
            end
        end
        print("Census3: occluders enabled " .. count)
    end },
    { name = "occlusionOn2", fn = function() print("Census3: numOccluders " .. renderer:GetNumOccluders(false)) end },
}

function Census3_PostUpdate(eventType, eventData)
    Ruins_HandlePostUpdate(eventType, eventData)
    if wait > 0 then
        wait = wait - 1
        if wait == 0 then
            local s = steps[stepIndex]
            s.b, s.p, s.k = (s.b or 0) + renderer:GetNumBatches(), (s.p or 0) + renderer:GetNumPrimitives(), (s.k or 0) + 1
            if s.k < 3 then wait = 1; return end
            local b, p = s.b / s.k, s.p / s.k
            if not base then base = { b = b, p = p } end
            print(string.format("Census3: step %-16s batches=%6.0f (%+6.0f) primitives=%8.0f (%+8.0f)", s.name, b, b - base.b, p, p - base.p))
            if s.undo then s.undo() end
        end
        return
    end
    stepIndex = stepIndex + 1
    local s = steps[stepIndex]
    if not s then return end
    if s.fn then s.fn() end
    wait = stepIndex == 1 and 30 or 4
end

V.atFrame(4, function()
    game = _G["RUINS"]
    local Settings = require("ruins.GameSettings")
    Settings.Set("quality", "high")
    Settings.Set("volumetric", false)
    game.dayNight.lockHour = 12
    game.dayNight:SetHour(12)
    SubscribeToEvent("PostUpdate", "Census3_PostUpdate")
end)
