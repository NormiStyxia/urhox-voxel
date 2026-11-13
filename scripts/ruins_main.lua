-- ====================================================================
-- ruins_main.lua — 时之遗迹入口（project.json 的 entry）
-- 运行：UrhoXRuntime ruins_main.lua -tapcode_dir=<项目根>
-- 巨龙动画测试场景仍可从 dragon_main.lua 进入。
-- ====================================================================

local RuinsScene = require("ruins.RuinsScene")
local Settings = require("ruins.GameSettings")
local SceneQuality = require("ruins.SceneQuality")

function Start()
    Settings.Load()
    RuinsScene.Start()
    SceneQuality.Attach(RuinsScene)
end

function Stop()
    Settings.Stop()
    RuinsScene.Stop()
end
