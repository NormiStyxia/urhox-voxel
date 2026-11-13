-- 受控大阶梯视图，仅由 -validate-test 加载；冻结场景以检查衔接共面与HUD。
local V = _G["V"]
V.atFrame(8, function()
    local game = _G["RUINS"]
    local nomi = game.nomiCtl
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("SceneUpdate")
    UnsubscribeFromEvent("PostUpdate")
    game.world.updateEnabled = false
    nomi.cc:Teleport(Vector3(0, 2, 24.25))
    nomi.cc.enabled = false
    nomi.camTarget.position = nomi:Position()
    nomi.yaw, nomi.camYaw, nomi.camPitch = 0, 0, 12
    nomi.node.rotation = Quaternion(0, Vector3.UP)
    nomi.onGround, nomi.speed = true, 0
    for _ = 1, 90 do
        nomi:Animate(1 / 60, false)
        nomi:UpdateCamera(1 / 60, "normal", nomi.node)
    end
    game.dayNight.lockHour = 16
    game.dayNight:SetHour(16)
    game.dayNight:Update(0.5)
    local HUD = require("ruins.RuinsHUD")
    HUD.SetObjective("取得时之钥", "时之碑被封印了。西侧塔台顶上有「时之钥」：打碎悬石，趁碎块下落时按 E「冻结」，踩着碎块爬上塔台。")
    HUD.SetClock("白昼 16:00")
    HUD.SetHint("")
    HUD.SetTarget("")
    HUD.SetMessage("")
    V.assert(math.abs(nomi:Position().y - 2) < 0.01, "受控相机角色脚底与第四级台面一致")
    print("StairViewTest: 台阶受控位置 " .. tostring(nomi:Position()))
end)
