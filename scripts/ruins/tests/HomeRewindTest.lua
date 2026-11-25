-- Runtime regression for interruptions, active collisions and pool-side rendering.
local V=_G.V
local home=require('ruins.HomeIsland')
local fixture

V.atFrame(8,function()
    local game=_G.RUINS
    local job=home.BeginBuild(game.world,game.scene,game.dayNight)
    while true do
        local done,err=job:Step()
        assert(not err,err)
        if done then break end
    end
    local ground=game.scene:GetChild('HomeHouse-ground-floor',true)
    local volume=ground:GetComponent('VoxelVolume')
    local original=volume.material
    local function step(seconds) home.Update(seconds,nil,game.dayNight) end
    V.assert(home.SetHouseStage(3),'direct 0 to 3')
    V.assert(volume.collisionMask~=0,'incoming wall collision enabled')
    step(.52)
    V.assert(ground.enabled and volume.material~=original,'ground floor partially assembled')
    V.assert(home.SetHouseStage(0),'reverse in flight')
    V.assert(volume.collisionMask==0,'outgoing wall collision disabled')
    V.assert(home.SetHouseStage(2),'retarget before next frame')
    step(2)
    V.assert(ground.enabled and volume.material==original,'completed wall restores original material')
    V.assert(home.SetHouseStage(0),'full downgrade')
    step(2)
    V.assert(not ground.enabled and volume.material==original,'fully dissolved wall')
    V.assert(not home.SetHouseStage(-1),'invalid selection rejected')
    home.SetHouseStage(1)
    step(2)
    home.SetHouseStage(2)
    step(.54)
    game.nomiCtl.node:SetDeepEnabled(false)
    game.dayNight.lockHour=16
    game.dayNight:SetHour(16)
    fixture={game=game,job=job}
end)

function HomeRewindTest_Camera()
    if not fixture then return end
    local cam=fixture.game.nomiCtl:CameraNode()
    cam.worldPosition=Vector3(home.x+2,home.base+3.4,-11)
    cam:LookAt(Vector3(home.x-8,home.base+5.7,9),Vector3.UP)
end

V.atFrame(9,function()
    SubscribeToEvent('PostUpdate','HomeRewindTest_Camera')
end)

V.atFrame(25,function()
    if fixture then
        home.SetHouseStage(3)
        home.Update(.44,nil,fixture.game.dayNight)
        fixture.job:Cancel()
        V.assert(not fixture.game.scene:GetChild('HomeHouseRewindFX',true),'teardown removes FX during transition')
        fixture=nil
    end
end)
