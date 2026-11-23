-- 固定坑壁视角，只由渲染验证加载，不改变正式游戏流程。
local V = _G["V"]
V.atFrame(8, function()
    local game = _G["RUINS"]
    V.assert(game ~= nil, "遗迹场景已加载")
    if not game then return end
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("SceneUpdate")
    UnsubscribeFromEvent("PostUpdate")
    game.world.updateEnabled = false
    local camera = game.nomiCtl:CameraNode()
    camera.worldPosition = Vector3(10.5, 2.1, 12.0)
    camera:LookAt(Vector3(17.5, 2.8, 11.0))
    game.nomiCtl:Camera().fov = 62
    game.dayNight.lockHour = 15
    game.dayNight:SetHour(15)
    game.dayNight:Update(0.5)
    print("WallSurfaceViewTest: 固定中央坑壁视角")
end)
