-- 南门实景回归：使用正式生成的堵门碎石与实际越肩相机，不用测试方块代替。
local V = _G["V"]
local function Name(volume)
    if volume==nil then return "none" end
    local node=volume:GetNode()
    return string.format("%s breakable=%s layer=%d",node and node.name or "no-node",tostring(volume.destructible),volume.collisionLayer)
end
V.atFrame(8,function()
    local game=_G["RUINS"]
    local nomi,world,puzzles=game.nomiCtl,game.world,game.puzzles
    local savedPos,savedYaw,savedPitch=nomi:Position(),nomi.camYaw,nomi.camPitch
    local gate=puzzles.gateRubble
    print("GateTargetTest: gate="..Name(gate))
    -- 先确认从外侧向碎石表面的世界射线和 Grid 查询一致。
    for _,y in ipairs({6.75,7.5,8.25}) do
        local ray=Ray(Vector3(.55,y,-57),Vector3.FORWARD)
        local aim=nomi:AimRay(ray,30)
        local body=world:RaycastSingle(ray,30)
        print(string.format("GateTargetTest: y=%.2f grid=%s body=%s pos=%s",y,Name(aim.volume),Name(body.volume),tostring(aim.pos)))
        V.assert(aim.volume==gate and aim.breakable,"南门实景直线命中堵门碎石，y="..y)
    end
    -- normal/aim 两种相机距离；近距离蓄力与从出生点走近均应对齐。
    for _,z in ipairs({-62,-58,-55.5}) do
        for _,mode in ipairs({"normal","aim"}) do
            nomi.cc:Teleport(Vector3(0,6.1,z))
            nomi.camTarget.position=nomi:Position()
            nomi.camYaw,nomi.camPitch=0,0
            for i=1,60 do nomi:UpdateCamera(1/60,mode,nomi.node) end
            local ray=nomi:Camera():GetScreenRay(.5,.5)
            local aim=nomi:Aim(60)
            print(string.format("GateTargetTest: z=%.2f mode=%s origin=%s dir=%s hit=%s pos=%s",
                z,mode,tostring(ray.origin),tostring(ray.direction),Name(aim.volume),tostring(aim.pos)))
            print(string.format("GateTargetTest: camera=%s forward=%s dot=%.4f projection=%s hand=%s characterForward=%s",
                tostring(nomi:CameraNode().worldPosition),tostring(nomi:CameraNode().worldDirection),
                ray.direction:DotProduct(nomi:CameraNode().worldDirection),
                tostring(nomi:Camera():WorldToScreenPoint(nomi:CameraNode().worldPosition+nomi:CameraNode().worldDirection*5)),
                tostring(nomi:HandPos()),tostring(nomi.node.worldDirection)))
            V.assert(aim.volume==gate and aim.breakable,"正式越肩准星锁定南门，z="..z.." mode="..mode)
            game.sigils:Update(0,aim,nomi:HandPos(),nomi:CameraNode(),game.caster,1,true)
            V.assert(game.sigils.target.node.enabled,"实景南门目标时钟显示")
        end
    end
    nomi.cc:Teleport(Vector3(0,6.1,-58))
    nomi.node.rotation=Quaternion(0,Vector3.UP)
    for _,pitch in ipairs({-30,0,30}) do
        nomi.camPitch=pitch
        for i=1,90 do nomi:Animate(1/60,true) end
        local arm=nomi.nomi.bones.arm_right
        local hand=nomi:HandPos()
        print(string.format("GateTargetTest: casting pitch=%.1f shoulder=%s hand=%s palmForward=%.4f",
            pitch,tostring(arm.worldPosition),tostring(hand),(hand-arm.worldPosition):DotProduct(nomi.node.worldDirection)))
        V.assert((hand-arm.worldPosition):DotProduct(nomi.node.worldDirection)>.2,"施法手在肩前而非背后 pitch="..pitch)
    end
    nomi.cc:Teleport(savedPos)
    nomi.camTarget.position=savedPos
    nomi.camYaw,nomi.camPitch=savedYaw,savedPitch
    nomi:UpdateCamera(0,"normal",nomi.node)

    local dn=game.dayNight
    local oldHour,oldFast,oldLock=dn.hour,dn.fast,dn.lockHour
    dn.fast,dn.lockHour=false,nil
    dn:SetHour(12)
    for i=1,120 do dn:Update(1) end
    V.assert(math.abs(dn.hour-13)<1e-6,"两分钟只流逝一游戏小时")
    for i=1,480 do dn:Update(1) end
    V.assert(math.abs(dn.hour-17)<1e-6 and dn.day>.5,"进入十分钟后仍有日光")
    dn.lockHour=12
    dn:Update(1)
    local locked=dn.hour
    dn:Update(30)
    V.assert(dn.hour==locked,"固定白天保持可用")
    dn.lockHour=nil; dn.fast=true; dn:SetHour(12); dn:Update(4)
    V.assert(math.abs(dn.hour-13)<1e-6,"T键快进仍为30倍速")
    dn.fast,dn.lockHour=oldFast,oldLock; dn:SetHour(oldHour)
end)
