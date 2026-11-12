-- 仅测试入口：在加载场景前选择 Web 分支，不更改正式入口或引擎平台实现。
local PlatformUtils = require("urhox-libs.Platform.PlatformUtils")
PlatformUtils.IsWebPlatform = function() return true end
_G["POINTER_WEB_TEST"] = true
local Scene = require("ruins.RuinsScene")
function Start() Scene.Start() end
function Stop() Scene.Stop() end
