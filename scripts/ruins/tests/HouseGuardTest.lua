-- 只由 -validate-test 加载：家园上层露台门与楼梯平台护栏的碰撞检查（世界坐标 = 家园 720,6,0 + 局部）。
local V = _G["V"]
V.atFrame(4, function()
    local game = _G["RUINS"]
    local Home = require("ruins.HomeIsland")
    local job = Home.BeginBuild(game.world, game.scene, game.dayNight)
    for _ = 1, 100000 do
        local done, err = job:Step()
        if done or err then break end
    end
    Home.SetHouseStage(3)
    require("ruins.RuinsTerrain").home = Home
end)
V.atFrame(8, function()
    local world = _G["RUINS"].world
    local HX, HB = 720, 6
    ---@param from Vector3
    ---@param dir Vector3
    local function hit(from, dir, len)
        local r = world:RaycastGridSingle(Ray(from, dir), len, 0xffffffff, nil)
        return r.hit and r.distance or nil
    end
    -- Corner landing (landA = 5.625): back edge z=16.875 and east edge x=0.975 local.
    V.assert(hit(Vector3(HX + .2, HB + 6.6, 16.2), Vector3(0, 0, 1), 1.5) ~= nil, "转角平台外侧（背面）有护栏")
    V.assert(hit(Vector3(HX + .2, HB + 6.6, 16.2), Vector3(1, 0, 0), 1.5) ~= nil, "转角平台外侧（东面）有护栏")
    -- Top landing (landB = 9.75): back edge and west edge.
    V.assert(hit(Vector3(HX - 8, HB + 10.75, 16.2), Vector3(0, 0, 1), 1.5) ~= nil, "顶部平台背面有护栏")
    V.assert(hit(Vector3(HX - 8, HB + 10.75, 16.2), Vector3(-1, 0, 0), 1.5) ~= nil, "顶部平台西侧有护栏")
    -- Terrace door: a ray at chest height from the terrace passes the wall line x=-7.
    local d = hit(Vector3(HX - 4, HB + 11.2, 11), Vector3(-1, 0, 0), 6)
    V.assert(d == nil or d > 3.4, "露台门洞可通行 dist=" .. tostring(d))
    local w = hit(Vector3(HX - 4, HB + 11.2, 9.8), Vector3(-1, 0, 0), 6)
    V.assert(w ~= nil and w < 3.2, "门洞旁仍是墙 dist=" .. tostring(w))
    print("HouseGuardTest: door dist " .. tostring(d) .. " wall dist " .. tostring(w))
end)
