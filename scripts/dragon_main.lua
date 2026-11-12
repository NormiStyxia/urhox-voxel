-- ====================================================================
-- dragon_main.lua — 体素巨龙测试场景的独立入口
-- 运行：UrhoXRuntime dragon_main.lua -tapcode_dir=<项目根>
-- 正式入口是 ruins_main.lua（时之遗迹）；本入口保留给巨龙动画调试
-- ====================================================================

local DragonTest = require("dragon.DragonTest")

function Start()
    DragonTest.Start()
end

function Stop()
    DragonTest.Stop()
end
