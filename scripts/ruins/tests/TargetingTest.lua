-- 使用真实体素世界验证准星、遮挡和时钟选择，不用 mock 命中结果。
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
    local ray = Ray(Vector3(300.5,5.5,298),Vector3.FORWARD)
    local aim = nomi:AimRay(ray,10)
    V.assert(aim.hit and aim.object==object and aim.breakable,"实心可操作物件正确锁定")
    game.sigils:Update(0,aim,Vector3.ZERO,nomi:CameraNode(),game.caster,1,true)
    V.assert(game.sigils.target.node.enabled,"时之物件显示选择时钟")
    local edgeAim=nomi:AimRay(Ray(Vector3(299.96,5.5,298),Vector3.FORWARD),10)
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
