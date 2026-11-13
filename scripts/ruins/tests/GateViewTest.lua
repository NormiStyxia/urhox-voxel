-- 受控南门画面：冻结移动和昼夜，保持蓄力姿态；验证图用于检查准星与法阵位置。
local V=_G["V"]
V.atFrame(8,function()
    local g=_G["RUINS"]
    local n=g.nomiCtl
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("SceneUpdate")
    UnsubscribeFromEvent("PostUpdate")
    g.world.enabled=false
    n.cc:Teleport(Vector3(0,6.1,-55.5))
    n.camTarget.position=n:Position()
    n.yaw,n.camYaw,n.camPitch=0,0,0
    n.node.rotation=Quaternion(0,Vector3.UP)
    n.onGround,n.speed=true,0
    for i=1,90 do n:Animate(1/60,true); n:UpdateCamera(1/60,"aim",n.node) end
    g.dayNight.lockHour=12; g.dayNight:SetHour(12)
    g.caster.charging,g.caster.charge=true,.85
    local e=VariantMap(); e["TimeStep"]=0
    g.fake={[KEY_1]=true}
    Ruins_HandleUpdate("Update",e)
    local a=g.aim
    g.sigils:Update(0,a,n:HandPos(),n:CameraNode(),g.caster,1,true)
    print(string.format("GateViewTest: framebuffer=%dx%d dpr=%.2f origin=%s dir=%s hit=%s projected=%s hand=%s",
        graphics:GetWidth(),graphics:GetHeight(),graphics:GetDPR(),tostring(a.origin),tostring(a.dir),tostring(a.pos),
        tostring(a.hit and n:Camera():WorldToScreenPoint(a.pos) or Vector2.ZERO),tostring(n:HandPos())))
    V.assert(a.volume==g.puzzles.gateRubble and a.breakable,"受控南门相机实际命中碎石")
    V.assert(g.sigils.target.node.enabled,"受控南门目标时钟实际启用")
end)
