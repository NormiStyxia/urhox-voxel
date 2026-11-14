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
    nomi.world=saved
    print(string.format("UrnTargetTest: visible=%d / 1296 misses=%d",visible,misses))
end)
