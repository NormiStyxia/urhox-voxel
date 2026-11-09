-- ====================================================================
-- dragon_main.lua — 体素巨龙测试场景的独立入口
-- 运行：UrhoXRuntime dragon_main.lua -tapcode_dir=<项目根>
-- （main.lua 在 config.START_SCENE == "dragon" 时也会转到这里）
-- ====================================================================

local DragonTest = require("dragon.DragonTest")

function Start()
    DragonTest.Start()
end

function Stop()
    DragonTest.Stop()
end
