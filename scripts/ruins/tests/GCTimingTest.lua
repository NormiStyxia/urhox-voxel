-- 仅由 -validate-test=ruins/tests/GCTimingTest.lua 加载，建议运行至少180帧。
-- 使用真实 Time 绑定和场景回调，覆盖启动、逐帧计时与 GC 开关。
local V = _G["V"]
local game = require("ruins.RuinsScene")
local audio = require("combat.CombatAudio")
local originalEnabled, originalDebug = game.gcEnabled, game.gcDebug

V.atFrame(5, function()
    V.assert(_G["RUINS"] == game and game.scene ~= nil and game.nomiCtl ~= nil,
        "遗迹初始化越过 StartSceneGC 并创建场景及角色")
    local ok, milliseconds = pcall(function() return Time:GetSystemTime() end)
    V.assert(ok and type(milliseconds) == "number", "真实静态 Time 绑定返回毫秒数")
    game.gcDebug = true
    Ruins_HandleGCBeginFrame()
    Ruins_HandleGCEndFrame()
    Ruins_HandleGCEndFrame() -- 重复结束事件不能重复执行增量步进。
end)

V.atFrame(20, function()
    game.SetGCEnabled(false)
    V.assert(not game.gcEnabled, "禁用场景 GC 调度")
    Ruins_HandleGCBeginFrame()
    Ruins_HandleGCEndFrame() -- 禁用仍会计时，但不做显式增量回收。
end)

V.atFrame(30, function()
    game.SetGCEnabled(true)
    V.assert(game.gcEnabled, "重新启用场景 GC 调度")
    Ruins_HandleGCBeginFrame()
    Ruins_HandleGCEndFrame()
end)

V.atFrame(175, function()
    V.assert(game.scene ~= nil and game.combat ~= nil, "持续帧更新后场景及战斗系统仍存活")
    local preloadProgress = assert(rawget(audio, "PreloadProgress"))
    local loaded, total = preloadProgress()
    V.assert(loaded == total and total == 38, "战斗音效在真实计时下完成逐帧预加载")
    game.gcDebug = originalDebug
    game.SetGCEnabled(originalEnabled)
    print("GCTimingTest: 完成真实 Time 绑定、帧事件、GC 开关及音效预加载回归")
end)
