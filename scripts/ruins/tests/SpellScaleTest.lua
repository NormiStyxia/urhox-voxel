-- 同一施法姿态，比较近/中/远镜头下的真实投影尺度与世界挂点。
local V=_G["V"]
local FX=require("dragon.VoxelFX")
V.atFrame(8,function()
    local game=_G["RUINS"]
    local nomi=game.nomiCtl
    local oldPos=nomi:Position()
    nomi.cc:Teleport(Vector3(0,6.1,-58))
    nomi.camTarget.position=nomi:Position()
    nomi.camYaw,nomi.camPitch=0,0
    nomi.onGround,nomi.speed=true,0
    nomi:PrepareCast({hit=false,far=Vector3(0,7,-40)})
    local hand=nomi:HandPos()
    local oldCharge,oldCharging=game.caster.charge,game.caster.charging
    game.caster.charge,game.caster.charging=1,true
    local aim={hit=true,breakable=true,pos=Vector3(0,7.6,-51.75),normal=Vector3(0,0,-1)}
    local root=game.scene:CreateChild("SpellScaleRegression")
    local pool=FX.WorldMotes(root,"WorldMotes",4,"square",true,nomi:CameraNode())
    pool:Spawn({pos=hand,size=.06,life=100,colors={Color.WHITE}})
    pool:Update(0)
    local previousWidth=math.huge
    for _,mode in ipairs({"aim","normal","far"}) do
        for i=1,100 do nomi:UpdateCamera(1/60,mode,nomi.node) end
        game.sigils:Update(0,aim,hand,nomi:CameraNode(),game.caster,1,true)
        local clock=game.sigils.hand.node
        local camera=nomi:Camera()
        local right=nomi:CameraNode().worldRight
        local a=camera:WorldToScreenPoint(clock.worldPosition-right*clock.worldScale.x)
        local b=camera:WorldToScreenPoint(clock.worldPosition+right*clock.worldScale.x)
        local width=math.abs(b.x-a.x)*graphics:GetWidth()
        pool:Draw()
        print(string.format("SpellScaleTest: %s distance=%.3f hand=%s seal=%s radius=%.3f projectedWidth=%.2f quadVertices=%d",
            mode,(nomi:CameraNode().worldPosition-hand):Length(),tostring(hand),tostring(clock.worldPosition),clock.worldScale.x,width,
            pool.geometry:GetNumVertices(0)))
        V.assert(width<previousWidth,"法阵随实际相机距离缩小 mode="..mode)
        V.assert((clock.worldPosition-hand):Length()<.3,"法阵仍位于施法手附近而非屏幕/脸部")
        V.assert(pool.bb==nil and pool.geometry:GetNumVertices(0)==6,"施法粒子使用六个世界顶点而非公告板尺寸扩张")
        V.assert(clock.worldDirection:DotProduct((aim.pos-hand):Normalized())>.999,"镜头变化不改变法阵施法朝向")
        previousWidth=width
    end
    game.caster.charge,game.caster.charging=oldCharge,oldCharging
    nomi.cc:Teleport(oldPos); nomi.camTarget.position=oldPos
    root:Dispose()
end)
