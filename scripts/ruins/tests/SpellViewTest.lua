-- 固定同一玩家/掌心与粒子，只切换镜头距离；必须实际渲染，不靠坐标断言验收。
local V=_G["V"]
local mode="aim"
for _,arg in ipairs(GetArguments()) do
    local value=arg:match("^%-spell%-view=(%a+)$")
    if value then mode=value end
end
V.atFrame(8,function()
    local g=_G["RUINS"]
    local n=g.nomiCtl
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("SceneUpdate")
    UnsubscribeFromEvent("PostUpdate")
    g.world.enabled=false
    n.cc:Teleport(Vector3(0,6.1,-58))
    n.camTarget.position=n:Position()
    n.camYaw,n.camPitch=0,0
    n.onGround,n.speed=true,0
    n:PrepareCast({hit=false,far=Vector3(0,7,-40)})
    for i=1,100 do n:UpdateCamera(1/60,mode,n.node) end
    g.dayNight.lockHour=12; g.dayNight:SetHour(12)
    g.caster.charging,g.caster.charge=true,1
    local hand=n:HandPos()
    local aim=n:Aim(60)
    g.sigils:Update(0,aim,hand,n:CameraNode(),g.caster,1,true)
    g.fx.motesB:Clear(); g.fx.motesG:Clear()
    g.fx.motesB:Spawn({pos=hand+Vector3(-.35,.15,0),size=.06,life=100,colors={Color(.4,.5,1)}})
    g.fx.motesG:Spawn({pos=hand+Vector3(.35,.15,0),size=.12,life=100,colors={Color(1,.77,.32)}})
    g.fx.motesB:Update(0); g.fx.motesG:Update(0)
    g.fx.motesB:Draw(); g.fx.motesG:Draw()
    local clock=g.sigils.hand.node
    local a=n:Camera():WorldToScreenPoint(clock.worldPosition-n:CameraNode().worldRight*clock.worldScale.x)
    local b=n:Camera():WorldToScreenPoint(clock.worldPosition+n:CameraNode().worldRight*clock.worldScale.x)
    print(string.format("SpellViewTest: mode=%s hand=%s seal=%s projectedDiameter=%.2fpx distance=%.2fm",
        mode,tostring(hand),tostring(clock.worldPosition),math.abs(b.x-a.x)*graphics:GetWidth(),
        (n:CameraNode().worldPosition-clock.worldPosition):Length()))
    V.assert(g.sigils.hand.node.enabled,"受控施法法阵启用")
    V.assert(g.fx.motesB:Count()==1 and g.fx.motesG:Count()==1,"两种实际施法粒子均参与截图")
end)
