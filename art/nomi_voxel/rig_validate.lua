-- Run as a V test with dragon_main.lua. No windows or input simulation required.
local Ride = require("dragon.DragonRide")
local testScene
local B = require("game.BlockCharacter")
local Data = require("game.NomiVoxelData")
local function capture(label, n)
    for _, b in ipairs(Data.bones) do
        local node = n.bones[b.name]
        local parent = n.root.parent
        local o = parent:WorldToLocal(node:LocalToWorld(Vector3.ZERO))
        local x = parent:WorldToLocal(node:LocalToWorld(Vector3.RIGHT)) - o
        local y = parent:WorldToLocal(node:LocalToWorld(Vector3.UP)) - o
        local z = parent:WorldToLocal(node:LocalToWorld(Vector3.FORWARD)) - o
        print(string.format("NOMI_POSE|%s|%s|%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f",
            label,b.name,o.x,o.y,o.z,x.x,x.y,x.z,y.x,y.y,y.z,z.x,z.y,z.z))
    end
end
local function connections(n,label)
    for _,side in ipairs({"right","left"}) do
        local hip,knee=n.bones["leg_"..side],n.bones["shin_"..side]
        V.assert(knee.parent == hip,label..": knee parent")
        V.assert((hip.scale-Vector3.ONE):Length()<0.000001,label..": hip unit scale")
        V.assert((knee.scale-Vector3.ONE):Length()<0.000001,label..": knee unit scale")
        V.assert((hip:LocalToWorld(n.basePos["shin_"..side])-knee.worldPosition):Length()<0.000001,
            label..": shared knee pivot")
    end
end
V.atFrame(60,function()
    -- V scripts load their own Lua module cache: test the production class in an
    -- isolated scene, not a second uninitialised copy of DragonTest's singleton.
    testScene=Scene()
    local n=B.CreateVoxel(testScene:CreateChild("NomiRigTest"),Data,B.SLENDER)
    V.assert(n~=nil,"character created")
    V.assert(require("player").CycleBodyType==nil,"Q variant switch removed")
    V.assert(math.abs(n.basePos.root.y-.1386)<0.000001,"existing stature preserved")
    local cases={
        {"idle",0,true,false,0},{"walkA",2,true,false,math.pi*.5},
        {"runA",5,true,false,math.pi*.5},{"runB",5,true,false,math.pi*1.5},
        {"jump",0,false,false,0},{"crouch",0,true,true,0},
    }
    for _,c in ipairs(cases) do
        n.time,n.phase,n.gait,n.air,n.crouch=0,0,0,0,0
        for i=1,90 do n:Update(1/60,{moveSpeed=c[2],onGround=c[3],crouching=c[4]}) end
        n.phase=c[5]
        n:Update(0,{moveSpeed=c[2],onGround=c[3],crouching=c[4]})
        connections(n,c[1]);capture(c[1],n)
    end
    local saddle=testScene:CreateChild("TestSaddle")
    saddle.position=Vector3(0,3,0)
    local ride=Ride.New({nomi=n,nomiNode=n.root.parent,ctrl={params={walkSpeed=2}},rig={sockets={saddle=saddle}}})
    ride:SeatPose();ride:AttachToSaddle()
    local hipCenter=(n.bones.leg_right.worldPosition+n.bones.leg_left.worldPosition)*.5
    V.assert((hipCenter-saddle.worldPosition):Length()<.000001,"rider hips align with saddle")
    connections(n,"riding");capture("riding",n)
    for i=1,120 do n:Update(1/60,{moveSpeed=0,onGround=true}) end
    V.assert(math.abs(n.bones.shin_right.rotation:PitchAngle())<.01,"dismount resets knee")
    connections(n,"dismount")
    n:SetBone("leg_right",-60,0,0);n:SetBone("shin_right",90,0,0)
    connections(n,"bend90");capture("bend90",n)
    V.finish()
end)
