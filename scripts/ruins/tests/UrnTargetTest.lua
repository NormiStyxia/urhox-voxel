-- 正式时之瓮现场回归：相机绕瓮 -> 可见实心壳；空心腹腔和前景建筑仍须正确遮挡。
-- 与独立全距离 Grid 复核比较，不能只以原生候选或相同的短距离证明无遮挡。
local V=_G["V"]
local TimeObject=require("ruins.TimeObject")
local function Describe(hit)
    if not hit.hit then return "miss" end
    local node=hit.volume:GetNode()
    return string.format("%s id=%d d=%.9f pos=%s",node and node.name or "nil",hit.volumeId,hit.distance,tostring(hit.position))
end
V.atFrame(8,function()
    local game=_G["RUINS"]
    local nomi,world=game.nomiCtl,game.world
    local saved=nomi.world
    local urns={game.puzzles.objects.urn1,game.puzzles.objects.urn2}
    local force={
        RaycastGridSingle=function(self,r,d,mask)
            local hit=VoxelRaycastResult:new()
            hit.hit,hit.volume,hit.volumeId=true,urns[1].whole,urns[1].whole.volumeId
            hit.distance,hit.position=0,r.origin
            return hit
        end,
        GetVolumeCount=function() return world:GetVolumeCount() end,
        GetVolume=function(self,i) return world:GetVolume(i) end
    }
    local visible,misses=0,0
    for _,urn in ipairs(urns) do
        print(string.format("UrnTargetTest: %s center=%s origin=%s dims=%s scale=%s",urn.id,tostring(urn.center),tostring(urn.origin),
            tostring(urn.whole:GetGrid():GetDimensions()),tostring(urn.whole:GetNode().worldScale)))
        for heading=0,355,5 do
            local a=math.rad(heading)
            for _,distance in ipairs({2,4,8}) do
                for _,height in ipairs({-.5,0,.5}) do
                    local target=urn.center+Vector3(0,height,0)
                    local origin=target+Vector3(math.sin(a)*distance,.6,math.cos(a)*distance)
                    local delta=target-origin
                    local ray=Ray(origin,delta:Normalized())
                    local native=world:RaycastGridSingle(ray,20,nomi.aimMask)
                    local checked=nomi:GridHit(ray,20)
                    local aim=nomi:AimRay(ray,20)
                    nomi.world=force
                    local exact=nomi:GridHit(ray,20)
                    nomi.world=saved
                    local expected=exact.hit and TimeObject.FindByVolume(exact.volume)==urn
                    if expected then visible=visible+1 end
                    local same=checked.hit==exact.hit and (not exact.hit or checked.volume==exact.volume)
                    if not same or (expected and aim.object~=urn) then
                        misses=misses+1
                        print(string.format("UrnTargetTest: MISMATCH urn=%s heading=%d range=%g h=%g origin=%s dir=%s native=%s checked=%s exact=%s object=%s",
                            urn.id,heading,distance,height,tostring(origin),tostring(ray.direction),Describe(native),Describe(checked),Describe(exact),aim.object and aim.object.id or "nil"))
                    end
                    V.assert(same,"正式瓮最近命中一致 "..urn.id.." angle="..heading.." range="..distance.." h="..height)
                    if expected then V.assert(aim.object==urn,"可见瓮面可锁定 "..urn.id.." angle="..heading.." range="..distance.." h="..height) end
                end
            end
        end
    end
    -- 镜头瞄准外壳而非包围中心：覆盖瓮腹棱角/金环/蓝纹各高度。
    local urn=urns[1]
    -- 模拟不同运行后端的首命中漏掉可见瓮，或报出包围盒空气中的普通障碍。
    -- 真实 Grid 不变：镜头 -> 空气 -> 瓮外壳；两种原生结果都必须得到同一目标。
    local falseBlock=world:CreateVolume(4,4,4,.125,urn.center+Vector3(0,0,-2))
    falseBlock.destructible=false
    world:FinalizeVolume(falseBlock)
    local faultMode=0
    nomi.world={
        RaycastGridSingle=function(self,r,d,mask)
            local hit=VoxelRaycastResult:new()
            if faultMode==1 then
                hit.hit,hit.volume,hit.volumeId=true,falseBlock,falseBlock.volumeId
                hit.distance,hit.position=1,(r.origin+r.direction) --[[@as Vector3]]
            end
            return hit
        end,
        GetVolumeCount=function() return world:GetVolumeCount() end,
        GetVolume=function(self,i) return world:GetVolume(i) end,
        SphereCast=function() return VoxelRaycastResult:new() end
    }
    for mode=0,1 do
        faultMode=mode
        local target=urn.center
        local r=Ray(target+Vector3(0,.5,-4),Vector3(0,-.5,4):Normalized())
        local aim=nomi:AimRay(r,20)
        V.assert(aim.object==urn,"原生漏报或空气障碍不清空可见瓮 mode="..mode)
    end
    nomi.world=saved
    local blockNode=falseBlock:GetNode()
    world:RemoveVolume(falseBlock); falseBlock:Dispose(); blockNode:Dispose()
    for heading=0,345,15 do
        local a=math.rad(heading)
        local facing=Vector3(math.sin(a),0,math.cos(a))
        local tangent=Vector3(math.cos(a),0,-math.sin(a))
        for _,height in ipairs({6.35,6.65,7.05,7.25,7.5,7.75,8.1,8.3}) do
            for _,offset in ipairs({-.75,-.5,-.25,0,.25,.5,.75}) do
                local target=Vector3(urn.center.x,height,urn.center.z)+tangent*offset
                local origin=Vector3(urn.center.x,7.9,urn.center.z)+facing*4
                local delta=target-origin
                local r=Ray(origin,delta:Normalized())
                local native=world:RaycastGridSingle(r,20,nomi.aimMask)
                local checked=nomi:GridHit(r,20)
                nomi.world=force
                local exact=nomi:GridHit(r,20)
                nomi.world=saved
                local same=checked.hit==exact.hit and (not exact.hit or checked.volume==exact.volume)
                if not same then
                    misses=misses+1
                    print(string.format("UrnTargetTest: SURFACE MISMATCH angle=%d h=%g offset=%g origin=%s dir=%s native=%s checked=%s exact=%s",
                        heading,height,offset,tostring(origin),tostring(r.direction),Describe(native),Describe(checked),Describe(exact)))
                end
                V.assert(same,"瓮外壳各表面命中一致 angle="..heading.." h="..height.." offset="..offset)
            end
        end
    end
    nomi.world=saved
    print(string.format("UrnTargetTest: visible=%d / 1296 misses=%d",visible,misses))
end)

-- 固定与截图相近的西侧瓮视角，先验证真实相机准星，再渲染目标钟面。
V.atFrame(120,function()
    local game=_G["RUINS"]
    local nomi=game.nomiCtl
    local urn=game.puzzles.objects.urn1
    UnsubscribeFromEvent("PostUpdate")
    UnsubscribeFromEvent("Update")
    local center=urn.center
    local position=center+Vector3(-3,1,-3.5)
    local camera=nomi:CameraNode()
    camera.worldPosition=position
    camera:LookAt(center)
    nomi.cc:Teleport(center+Vector3(-1.6,-1.1,-1.8))
    nomi.yaw,nomi.camYaw=40,40
    nomi.node.rotation=Quaternion(40,Vector3.UP)
    for i=1,60 do nomi:Animate(1/60,true) end
    local aim=nomi:Aim(20)
    V.assert(aim.object==urn,"截图类似视角的实际相机准星锁定瓮")
    game.caster.charging,game.caster.charge=true,.5
    game.sigils:Update(0,aim,nomi:HandPos(),camera,game.caster,1,true)
    V.assert(game.sigils.target.node.enabled,"选中钟面实际启用")
    print(string.format("UrnTargetTest: SCREEN camera=%s dir=%s target=%s clock=%s surfaceNormal=%s",tostring(position),tostring(camera.worldDirection),
        tostring(aim.pos),tostring(game.sigils.target.node.worldPosition),tostring(aim.normal)))
end)
