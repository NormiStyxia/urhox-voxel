-- 独立真实物理回归入口，避免整张地图/家园/UI 的加载影响支撑测试。
local Puzzles = require("ruins.RuinsPuzzles")
local Palette = require("ruins.RuinsPalette")
local scene = Scene()
function Start()
    scene:CreateComponent("Octree")
    local world = scene:CreateComponent("VoxelPhysicsWorld")
    world.gravity = Vector3(0, -9.81, 0)
    world.stressBreakFactor = 200
    world.minFragmentVoxels = 4
    Palette.Setup(world)
    Puzzles.Build(world, scene)
    local camera = scene:CreateChild("TestCamera"):CreateComponent("Camera")
    renderer:SetViewport(0, Viewport:new(scene, camera))
    _G["RUINS"] = {scene = scene, world = world}
end
