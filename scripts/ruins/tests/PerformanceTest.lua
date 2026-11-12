-- 仅由 -validate-test 加载；统计 Lua CPU 时间，不代表浏览器 GPU 帧率。
local V = _G["V"]
local totals, calls = {}, {}
local recording = false
local renderFrames, renderBatches, renderTriangles = 0, 0, 0
local drawCalls = {}
local function CountDraw(name)
    local draw = require("ui.PixelDraw")
    local original = draw[name]
    draw[name] = function(...)
        if recording then drawCalls[name] = (drawCalls[name] or 0) + 1 end
        return original(...)
    end
end
local function Watch(object, method, name)
    local original = object[method]
    object[method] = function(self, ...)
        if not recording then return original(self, ...) end
        local start = os.clock()
        local result = original(self, ...)
        totals[name] = (totals[name] or 0) + os.clock() - start
        calls[name] = (calls[name] or 0) + 1
        return result
    end
end
V.atFrame(5, function()
    local game = _G["RUINS"]
    V.assert(game ~= nil and game.ctrl ~= nil, "遗迹场景已经初始化")
    Watch(game.ctrl, "Update", "dragon.controller")
    Watch(game.rig, "UpdateMembranes", "dragon.membranes")
    Watch(game.breath, "Update", "dragon.breath")
    Watch(game.dragonWorld, "Update", "dragon.adapter")
    Watch(game.dayNight, "Update", "daynight")
    Watch(game.sigils, "Update", "sigils")
    CountDraw("TextWidth")
    CountDraw("NineSlice")
    SubscribeToEvent("EndRendering", function()
        if not recording then return end
        renderFrames = renderFrames + 1
        renderBatches = renderBatches + renderer:GetNumBatches()
        renderTriangles = renderTriangles + renderer:GetNumPrimitives()
    end)
    local puzzles = require("ruins.RuinsPuzzles")
    local oldUpdate, oldGate = puzzles.Update, puzzles.CheckGate
    puzzles.Update = function(dt)
        local start = os.clock()
        oldUpdate(dt)
        if recording then totals.puzzles = (totals.puzzles or 0) + os.clock() - start end
    end
    puzzles.CheckGate = function()
        local start = os.clock()
        oldGate()
        if recording then totals.gate = (totals.gate or 0) + os.clock() - start end
    end
end)
V.atFrame(20, function() recording = true end)
V.atFrame(110, function()
    recording = false
    local keys = {}
    for key in pairs(totals) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        print(string.format("RuinsPerf: %s %.4f ms/frame (%d calls, 90 frames)", key, totals[key] * 1000 / 90, calls[key] or 90))
    end
    if renderFrames > 0 then
        print(string.format("RuinsPerf: render %d frames, %.0f batches/frame, %.0f primitives/frame", renderFrames, renderBatches / renderFrames, renderTriangles / renderFrames))
        for name, count in pairs(drawCalls) do
            print(string.format("RuinsPerf: HUD %s %.1f calls/frame", name, count / renderFrames))
        end
    end
    V.assert(not _G["RUINS"].dragonAwake, "基线采样覆盖沉睡龙")
end)
