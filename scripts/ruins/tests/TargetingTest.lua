-- 真实体素世界验证准星/遮挡；仅在故障注入用例中替换原生首命中，仍查真实 Grid。
local V = _G["V"]
local TimeObject = require("ruins.TimeObject")
V.atFrame(8, function()
    local game = _G["RUINS"]
    local world, nomi = game.world, game.nomiCtl
    local base = world:GetVolumeCount()
    local voxels = {}
    for x = 0, 3 do for y = 0, 3 do for z = 0, 3 do
        voxels[#voxels + 1] = {x, y, z, 100}
    end end end
    local object = TimeObject.New({id="aim_regression",world=world,scene=game.scene,
        voxels=voxels,dims={4,4,4},size=.25,origin=Vector3(300,5,300)})
    -- 六面检测示意：相机 → 2m空气 → [1m实心盒]；±X / ±Y / ±Z 对称。
    -- 每面九个可见表面点；负向射线、边界点和旋转后的局部面必须同样可选。
    -- 空心/遮挡案例仍由下方测试保证：不能以放大包围盒或穿墙来补锁定。
    for _,entry in ipairs({
        {"+X",Vector3.RIGHT,Vector3.UP,Vector3.FORWARD},
        {"-X",-Vector3.RIGHT,Vector3.UP,Vector3.FORWARD},
        {"+Y",Vector3.UP,Vector3.RIGHT,Vector3.FORWARD},
        {"-Y",-Vector3.UP,Vector3.RIGHT,Vector3.FORWARD},
        {"+Z",Vector3.FORWARD,Vector3.RIGHT,Vector3.UP},
        {"-Z",-Vector3.FORWARD,Vector3.RIGHT,Vector3.UP},
    }) do
        local face,normal,u,v=entry[1],entry[2],entry[3],entry[4]
        for _,a in ipairs({-.375,0,.375}) do for _,b in ipairs({-.375,0,.375}) do
            local point=object.origin+Vector3(.5,.5,.5)+normal*.5+u*a+v*b
            local faceRay=Ray(point+normal*2,-normal)
            local native=world:RaycastGridSingle(faceRay,10,nomi.aimMask)
            local selected=nomi:AimRay(faceRay,10)
            if selected.object~=object then
                print(string.format("TargetingTest: FACE MISS %s offsets=%.3f,%.3f native=%s id=%d distance=%.4f selected=%s",
                    face,a,b,tostring(native.hit),native.volumeId,native.distance,tostring(selected.volumeId)))
            end
            V.assert(selected.object==object,"同一实心物件六面均可锁定 "..face.." "..a..","..b)
        end end
    end
    -- 擦过上/右/后边界进入：微小法向分量仍须跨入合法格，不能 floor 成 dims。
    local shallowMisses=0
    for _,entry in ipairs({
        {Vector3.RIGHT,Vector3.UP},{-Vector3.RIGHT,Vector3.UP},
        {Vector3.UP,Vector3.FORWARD},{-Vector3.UP,Vector3.FORWARD},
        {Vector3.FORWARD,Vector3.RIGHT},{-Vector3.FORWARD,Vector3.RIGHT}
    }) do
        for _,slope in ipairs({.01,.003,.001}) do
            local normal=(entry[1]*slope+entry[2]):Normalized()
            local point=object.center+entry[1]*.5
            local r=Ray(point+normal*3,-normal)
            local native=world:RaycastGridSingle(r,10,nomi.aimMask)
            local selected=nomi:GridHit(r,10)
            V.assert(native.hit and native.volume==object.whole,"浅角测试射线确实命中物件 slope="..slope.." face="..tostring(entry[1]))
            if native.hit and native.volume==object.whole then
                local same=selected.hit and selected.volume==object.whole
                if not same then
                    shallowMisses=shallowMisses+1
                    print(string.format("TargetingTest: SHALLOW MISS slope=%g origin=%s dir=%s native=%.9f checked=%s",
                        slope,tostring(r.origin),tostring(r.direction),native.distance,tostring(selected.hit)))
                end
                V.assert(same,"微小法向分量入格不丢失原生正确命中 slope="..slope.." face="..tostring(entry[1]))
            end
        end
    end
    print("TargetingTest: shallow misses="..shallowMisses)
    -- 双轴棱/三轴角同时入射，包含混合正负方向；纯外侧擦过不能被夹回网格。
    for x=-1,1 do for y=-1,1 do for z=-1,1 do
        if x~=0 or y~=0 or z~=0 then
            local direction=Vector3(x,y,z):Normalized()
            local r=Ray(object.center+direction*3,-direction)
            local hit=nomi:GridHit(r,10)
            if not hit.hit or hit.volume~=object.whole then
                local native=world:RaycastGridSingle(r,10,nomi.aimMask)
                print(string.format("TargetingTest: CORNER MISS %d,%d,%d origin=%s dir=%s native=%s d=%.9f checked=%s",x,y,z,tostring(r.origin),tostring(r.direction),tostring(native.hit),native.distance,tostring(hit.hit)))
            end
            V.assert(hit.hit and hit.volume==object.whole,"棱角同时入射正确取格 "..x..","..y..","..z)
        end
    end end end
    for _,r in ipairs({
        Ray(Vector3(301.001,5.5,298),Vector3.FORWARD),
        Ray(Vector3(300.5,6.001,298),Vector3.FORWARD),
        Ray(Vector3(298,5.5,301.001),Vector3.RIGHT)
    }) do
        local hit=nomi:GridHit(r,2.5)
        V.assert(not hit.hit,"外侧平行擦过不产生实心命中")
    end
    -- 原生查询的端点约定与 DDA 分开：在下方强制逐格复核路径测试闭区间。
    -- 按正式悬石/碑的体素列取最外层实心格，在隔离区复用原始形状。
    -- 相机 → 空气 → 外露格；六个局部面都没有别的体积挡在前面。
    -- 不规则形状、旋转和远距离要分开核对原生命中与二次 Grid 校验。
    ---@param source TimeObject
    local function CheckShape(source, yaw, distance)
        local clone=TimeObject.New({id="face_"..source.id,world=world,scene=game.scene,
            voxels=source.voxels,dims=source.dims,size=source.size,
            origin=Vector3(300,100,300),yaw=yaw})
        local columns={}
        for axis=1,3 do
            local u,v=axis%3+1,(axis+1)%3+1
            local groups={}
            for _,cell in ipairs(source.voxels) do
                local key=cell[u]..","..cell[v]
                local column=groups[key]
                if column==nil then
                    column={lo=cell,hi=cell}
                    groups[key]=column
                else
                    if cell[axis]<column.lo[axis] then column.lo=cell end
                    if cell[axis]>column.hi[axis] then column.hi=cell end
                end
            end
            local keys={}
            for key in pairs(groups) do keys[#keys+1]=key end
            table.sort(keys)
            -- 每轴最多 24 列，明确抽样；原始六面方块仍全覆盖九个点。
            local stride=math.max(1,math.ceil(#keys/24))
            for k=1,#keys,stride do
                for _,sign in ipairs({-1,1}) do
                    ---@type number[]
                    local cell=sign<0 and groups[keys[k]].lo or groups[keys[k]].hi
                    local localNormal=Vector3(axis==1 and sign or 0,axis==2 and sign or 0,axis==3 and sign or 0)
                    local point=clone.origin+clone.rot*(Vector3(cell[1]+.5,cell[2]+.5,cell[3]+.5)*clone.size+localNormal*(clone.size*.5))
                    local normal=clone.rot*localNormal
                    local tangent=clone.rot*Vector3(u==1 and .37 or (v==1 and -.23 or 0),u==2 and .37 or (v==2 and -.23 or 0),u==3 and .37 or (v==3 and -.23 or 0))
                    columns[#columns+1]={point=point,normal=(normal+tangent):Normalized(),axis=axis,sign=sign}
                end
            end
        end
        local misses=0
        for _,column in ipairs(columns) do
            local point=column.point --[[@as Vector3]]
            local normal=column.normal --[[@as Vector3]]
            local faceRay=Ray(point+normal*distance,-normal)
            local native=world:RaycastGridSingle(faceRay,60,nomi.aimMask)
            local selected=nomi:AimRay(faceRay,60)
            if selected.object~=clone then
                misses=misses+1
                print(string.format("TargetingTest: SHAPE MISS %s yaw=%g axis=%d sign=%d origin=%s dir=%s native=%s id=%d d=%.9f checked=%s d=%s voxel=%s",
                    source.id,yaw,column.axis,column.sign,tostring(faceRay.origin),tostring(faceRay.direction),
                    tostring(native.hit),native.volumeId,native.distance,tostring(selected.hit),tostring(selected.distance),tostring(native.voxel)))
            end
            V.assert(selected.object==clone,"正式形状六面可选 "..source.id.." yaw="..yaw.." axis="..column.axis.." sign="..column.sign)
        end
        print(string.format("TargetingTest: shape=%s yaw=%g range=%g samples=%d misses=%d",source.id,yaw,distance,#columns,misses))
        clone:RemoveWhole()
    end
    for _,yaw in ipairs({0,37,90,180,270}) do CheckShape(object,yaw,3) end
    local puzzles=game.puzzles
    for _,source in ipairs({puzzles.boulder,puzzles.objects.stele1}) do
        if source~=nil then
            for _,yaw in ipairs({source.yaw,37,180}) do
                CheckShape(source,yaw,3)
                CheckShape(source,yaw,45)
            end
        end
    end
    -- 正式塔台现场：绕悬石水平/俯仰扫视，同时独立遍历当前实心格核对。
    -- 实心塔壁遮挡就保留塔壁，不将「面上不可见」当成锁定失败。
    local actualWorld=nomi.world
    local forceGrid={
        RaycastGridSingle=function(self,r,d,mask)
            local hit=VoxelRaycastResult:new()
            hit.hit,hit.volume,hit.volumeId=true,object.whole,object.whole.volumeId
            hit.distance,hit.position=0,r.origin
            return hit
        end,
        GetVolumeCount=function() return world:GetVolumeCount() end,
        GetVolume=function(self,i) return world:GetVolume(i) end
    }
    nomi.world=forceGrid
    local endpoint=nomi:GridHit(Ray(Vector3(300.5,5.5,298),Vector3.FORWARD),2)
    V.assert(endpoint.hit and endpoint.volume==object.whole and math.abs(endpoint.distance-2)<1e-6,
        "逐格复核距离上限恰好触及实心表面")
    -- 起点在内部格面上：只检查前进侧，不选身后仅接触的实心格。
    object.whole:GetGrid():Clear()
    object.whole:GetGrid():FillBox(0,0,0,1,3,3,true)
    local backward=nomi:GridHit(Ray(Vector3(300.5,5.5,300.5),-Vector3.RIGHT),.4)
    local forward=nomi:GridHit(Ray(Vector3(300.5,5.5,300.5),Vector3.RIGHT),.4)
    V.assert(backward.hit and backward.voxel.x==1,"内部整数格面负向归前一实心格")
    V.assert(not forward.hit,"内部整数格面正向不误选身后实心格")
    object.whole:GetGrid():FillBox(0,0,0,3,3,3,true)
    nomi.world=actualWorld
    local visibleCount,mismatch=0,0
    for heading=0,330,30 do for _,height in ipairs({-3,0,3}) do
        local angle=math.rad(heading)
        local center=puzzles.boulder.center
        local origin=center+Vector3(math.sin(angle)*10,height,math.cos(angle)*10)
        for _,offset in ipairs({Vector3.ZERO,Vector3(0,.5,0),Vector3(0,-.5,0)}) do
            local delta=center+offset-origin
            local r=Ray(origin,delta:Normalized())
            local native=world:RaycastGridSingle(r,30,nomi.aimMask)
            local selected=nomi:GridHit(r,30)
            nomi.world=forceGrid
            local exact=nomi:GridHit(r,30)
            nomi.world=actualWorld
            if exact.hit and TimeObject.FindByVolume(exact.volume)==puzzles.boulder then visibleCount=visibleCount+1 end
            local same=selected.hit==exact.hit and (not exact.hit or selected.volume==exact.volume)
            if not same then
                mismatch=mismatch+1
                print(string.format("TargetingTest: LIVE MISMATCH heading=%d h=%g origin=%s dir=%s native=%s id=%d d=%.6f selected=%s id=%d d=%.6f exact=%s id=%d d=%.6f",
                    heading,height,tostring(origin),tostring(r.direction),tostring(native.hit),native.volumeId,native.distance,
                    tostring(selected.hit),selected.volumeId,selected.distance,tostring(exact.hit),exact.volumeId,exact.distance))
            end
            V.assert(same,"正式悬石多角度命中与独立实心格一致 "..heading.." h="..height)
        end
    end end
    print(string.format("TargetingTest: live boulder visible=%d / 108 mismatches=%d",visibleCount,mismatch))
    local ray = Ray(Vector3(300.5,5.5,298),Vector3.FORWARD)
    local aim = nomi:AimRay(ray,10)
    V.assert(aim.hit and aim.object==object and aim.breakable,"实心可操作物件正确锁定")
    game.sigils:Update(0,aim,Vector3.ZERO,nomi:CameraNode(),game.caster,1,true)
    V.assert(game.sigils.target.node.enabled,"时之物件显示选择时钟")
    local edgeRay=Ray(Vector3(299.96,5.5,298),Vector3.FORWARD)
    local edgeAim=nomi:AimRay(edgeRay,10)
    local edgeNear=world:SphereCast(Sphere(edgeRay.origin,.12),edgeRay.direction,10,nomi.aimMask)
    if edgeNear.hit then
        local delta=edgeNear.position-edgeRay.origin
        local visibleRay=Ray(edgeRay.origin,delta:Normalized())
        local native=world:RaycastGridSingle(visibleRay,delta:Length()+.08,nomi.aimMask)
        local checked=nomi:GridHit(visibleRay,delta:Length()+.08)
        print(string.format("TargetingTest: edge native=%s %.5f checked=%s %.5f near=%s dir=%s",
            tostring(native.hit),native.distance,tostring(checked.hit),checked.distance,tostring(edgeNear.position),tostring(visibleRay.direction)))
    end
    V.assert(edgeAim.object==object and edgeAim.assisted,"准星轻微擦边可辅助锁定无遮挡物件")

    -- 前景动态碰撞凸包的空隙不能挡掉后方可见的实心体素。
    local gap=world:CreateVolume(8,4,4,.25,Vector3(299.5,5,298.8))
    gap:GetGrid():FillBox(0,0,0,0,3,3,true)
    gap:GetGrid():FillBox(7,0,0,7,3,3,true)
    gap.destructible=true
    world:FinalizeVolumeAsDynamic(gap); gap:RebuildGeometry()
    aim=nomi:AimRay(ray,10)
    V.assert(aim.object==object,"动态碰撞凸包空隙不抢走可见目标")
    local gapNode=gap:GetNode()
    world:RemoveVolume(gap); gap:Dispose(); gapNode:Dispose()

    local camNode = nomi:CameraNode()
    local oldPos, oldRot = camNode.worldPosition, camNode.worldRotation
    camNode.worldPosition = Vector3(300.5,5.5,299.7)
    camNode:LookAt(Vector3(300.5,5.5,301))
    aim = nomi:Aim(10)
    V.assert(aim.object==object,"相机与角色之间的近物件不会被跳过")
    camNode.worldPosition,camNode.worldRotation=oldPos,oldRot

    -- 复现网页错误形状：相机在空格，原生首命中误报包围体积 distance=0。
    -- 修复必须继续检查这个体积的实心墙，不能直接忽略它穿墙选物件。
    local hollow=world:CreateVolume(8,4,12,.25,Vector3(299.5,5,298))
    hollow.destructible=false
    hollow:GetGrid():FillBox(0,0,7,7,3,7,true)
    world:FinalizeVolume(hollow); hollow:RebuildGeometry()
    local realWorld=nomi.world
    nomi.world={
        RaycastGridSingle=function(self,r,d,mask)
            local falseHit=VoxelRaycastResult:new()
            falseHit.hit,falseHit.volume,falseHit.volumeId=true,hollow,hollow.volumeId
            falseHit.position,falseHit.distance=r.origin,0
            return falseHit
        end,
        RaycastGrid=function(self,r,d,mask) return world:RaycastGrid(r,d,mask) end,
        GetVolumeCount=function() return world:GetVolumeCount() end,
        GetVolume=function(self,i) return world:GetVolume(i) end,
        SphereCast=function(self,s,dir,d,mask) return world:SphereCast(s,dir,d,mask) end
    }
    aim=nomi:AimRay(ray,10)
    V.assert(aim.volume==hollow and math.abs(aim.distance-1.75)<.001,"零距离误报修复后仍命中同一体积前方实心墙")
    V.assert(aim.normal.z<-.99,"逐格校验保留正确墙面法线")
    hollow:GetGrid():Clear(); hollow:RebuildGeometry()
    aim=nomi:AimRay(ray,10)
    V.assert(aim.object==object and aim.distance>1.9,"空气包围盒不再阻止后方真实物件锁定")
    hollow:GetGrid():FillBox(0,0,7,7,3,7,true); hollow:RebuildGeometry()
    local angled=nomi:AimRay(Ray(Vector3(300.4,5.5,298),Vector3(.01,0,1):Normalized()),10)
    V.assert(angled.volume==hollow,"斜射同一空块内的实心墙不穿透")
    nomi.world=realWorld
    local hollowNode=hollow:GetNode()
    world:RemoveVolume(hollow); hollow:Dispose(); hollowNode:Dispose()

    -- 墙在目标前方：中心线与容错线都不允许穿墙。
    local wall = world:CreateVolume(12,12,2,.25,Vector3(299,4,299))
    wall:GetGrid():FillBox(0,0,0,11,11,1,true)
    wall.destructible=false
    world:FinalizeVolume(wall)
    wall:RebuildGeometry()
    aim=nomi:AimRay(ray,10)
    V.assert(aim.hit and aim.volume==wall and aim.object==nil,"不可隔墙锁定时之物件")
    game.sigils:Update(0,aim,Vector3.ZERO,nomi:CameraNode(),game.caster,1,true)
    V.assert(not game.sigils.target.node.enabled,"墙遮挡时不显示目标时钟")
    local wallNode=wall:GetNode()
    world:RemoveVolume(wall); wall:Dispose(); wallNode:Dispose()

    local rubble = world:CreateVolume(4,4,4,.25,Vector3(300,5,299))
    rubble:GetGrid():FillBox(0,0,0,3,3,3,true)
    rubble.destructible=true
    world:FinalizeVolume(rubble)
    rubble:RebuildGeometry()
    aim=nomi:AimRay(ray,10)
    V.assert(aim.volume==rubble and aim.breakable and aim.object==nil,"普通可破坏体素正确识别")
    game.sigils:Update(0,aim,Vector3.ZERO,nomi:CameraNode(),game.caster,1,true)
    V.assert(game.sigils.target.node.enabled,"普通可破坏物件也显示时钟")
    -- 技能执行不能通过附近碎块换目标；准星是碎石时绝不能回溯桥。
    local spells=require("ruins.TimeSpells")
    local rewindCalls,nearCalls=0,0
    local adjacent={canRewind=true,state="FROZEN",center=Vector3(300.5,5.5,300),title="邻近断桥",
        IsWhole=function() return false end,
        PieceCenters=function() return {Vector3(300.5,5.5,300)} end,
        Rewind=function() rewindCalls=rewindCalls+1; return true end}
    local ctx={world=world,fx={Burst=function() end,StartRewind=function() end},
        puzzles={FindNear=function() nearCalls=nearCalls+1; return adjacent end,
            FindByVolume=function() return adjacent end}}
    local ok=spells.BY_ID.rewind.cast(ctx,{hit=true,pos=Vector3(300.5,5.5,299),origin=Vector3(300.5,5.5,298),
        far=Vector3(300.5,5.5,308),volume=rubble})
    V.assert(not ok and rewindCalls==0 and nearCalls==0,"准星命中普通碎石时不换目标回溯附近断桥")
    local direct=spells.BY_ID.rewind.cast(ctx,{hit=true,pos=adjacent.center,object=adjacent})
    V.assert(direct and rewindCalls==1,"直接选中的时之物件仍可回溯")
    local rubbleNode=rubble:GetNode()
    world:RemoveVolume(rubble); rubble:Dispose(); rubbleNode:Dispose()

    V.assert(object:Shatter({level=1,point=object.center,power=0}),"生成真实碎块")
    object:Freeze(10)
    local piece=object.pieces[1]
    ---@type integer[]
    local ids=piece.ids
    local firstId=ids[1]
    local voxel=voxels[firstId]
    local center=piece.node.worldPosition+piece.node.worldRotation*Vector3(
        (voxel[1]-piece.minI+.5)*.25,(voxel[2]-piece.minJ+.5)*.25,(voxel[3]-piece.minK+.5)*.25)
    local pieceRay=Ray(center-Vector3(0,0,3),Vector3.FORWARD)
    aim=nomi:AimRay(pieceRay,10)
    V.assert(aim.object==object,"冻结碎块仍可锁定所属物件")
    object:Rewind()
    aim=nomi:AimRay(pieceRay,10)
    V.assert(aim.object==object,"无碰撞的回溯碎块仍可被准星识别")
    object:Reassemble()
    object:RemoveWhole()
    local live=0
    for i=0,world:GetVolumeCount()-1 do if world:GetVolume(i)~=nil then live=live+1 end end
    V.assert(live==base,"瞄准测试不留下存活体积")
    print("RuinsAimTest: real grid targeting and occlusion passed")
end)
