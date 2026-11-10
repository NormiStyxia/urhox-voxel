-- Smoke test for the restored rig; this does not validate knee seams.
local B = require("game.BlockCharacter")
local Data = require("game.NomiVoxelData")
local testScene
V.atFrame(60,function()
    testScene=Scene()
    local n=B.CreateVoxel(testScene:CreateChild("NomiRestoreTest"),Data,B.SLENDER)
    V.assert(n~=nil,"restored character created")
    V.assert(#Data.bones==16,"original 16-bone structure restored")
    V.assert(require("player").CycleBodyType==nil,"Q variant switch remains removed")
    V.assert(math.abs(n.basePos.root.y-.1386)<0.000001,"slender stature preserved")
    for _,b in ipairs(Data.bones) do
        V.assert(n.bones[b.name]~=nil,"bone loaded: "..b.name)
    end
    local cases={
        {"idle",0,true,false},{"walk",2,true,false},
        {"run",5,true,false},{"jump",0,false,false},{"crouch",0,true,true},
    }
    for _,c in ipairs(cases) do
        for i=1,90 do n:Update(1/60,{moveSpeed=c[2],onGround=c[3],crouching=c[4]}) end
        local p=n.bones.root.worldPosition
        V.assert(p.x==p.x and p.y==p.y and p.z==p.z,c[1]..": finite root position")
    end
    V.finish()
end)
