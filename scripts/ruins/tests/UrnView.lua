-- 基于标准3D场景脚手架的受控验收入口；复用正式遗迹，不改生产入口。
local game=require("ruins.RuinsScene")
local Settings=require("ruins.GameSettings")
local SceneQuality=require("ruins.SceneQuality")
function Start()
    Settings.Load()
    game.Start()
    SceneQuality.Attach(game)
    local nomi=game.nomiCtl
    local urn=game.puzzles.objects.urn1 --[[@as TimeObject]]
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("PostUpdate")
    UnsubscribeFromEvent("SceneUpdate")
    game.world.updateEnabled=false
    local camera=nomi:CameraNode()
    camera.worldPosition=urn.center+Vector3(-3,1,-3.5)
    camera:LookAt(urn.center)
    nomi.cc:Teleport(urn.center+Vector3(-1.6,-1.1,-1.8))
    nomi.cc.enabled=false
    nomi.node.rotation=Quaternion(40,Vector3.UP)
    nomi.camPitch=12
    for i=1,60 do nomi:Animate(1/60,true) end
    local aim=nomi:Aim(20)
    assert(aim.object==urn,"正式瓮截图视角未命中")
    game.caster.charging,game.caster.charge=true,.5
    game.sigils:Update(0,aim,nomi:HandPos(),camera,game.caster,1,true)
    local HUD=require("ruins.RuinsHUD")
    HUD.SetTarget("时之瓮 · 完整",urn)
    HUD.UpdateSlots({},.5)
    game.dayNight:SetHour(15.3)
    game.dayNight:Update(.1)
    print("UrnView: selected="..urn.id.." hit="..tostring(aim.pos).." clock="..tostring(game.sigils.target.node.worldPosition))
end
function Stop() game.Stop(); Settings.Stop() end
