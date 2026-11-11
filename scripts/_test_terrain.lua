local Pal = require("ruins.RuinsPalette")
local Terrain = require("ruins.RuinsTerrain")
local Build = require("ruins.RuinsBuild")
local SkyUtils = require("urhox-libs.Rendering.SkyUtils")
local CAMS = {
    { Vector3(0, 55, -95), Vector3(0, 6, 0) },
    { Vector3(-18, 12, -34), Vector3(4, 8, 10) },
    { Vector3(45, 30, 40), Vector3(0, 6, 0) },
}
function Start()
    local ok, e = pcall(Start2)
    print("START " .. tostring(ok) .. " " .. tostring(e))
end
function Start2()
    local scene = Scene()
    scene:CreateComponent("Octree")
    local world = scene:CreateComponent("VoxelPhysicsWorld")
    Pal.Setup(world)
    local lg = scene:CreateChild("LightGroup")
    lg:LoadXML(cache:GetResource("XMLFile", "LightGroup/TownDay.xml"):GetRoot())
    SkyUtils.CreateGradientSky(scene, { zenith = Color(0.10, 0.28, 0.66), horizon = Color(0.447, 0.638, 1.0), skyExp = 0.5 })
    Terrain.Build(world)
    Build.Build(world)
    local mat = Material:new()
    mat:SetSurfaceShader("Shaders/BLGL/VoxelPalettePBR.shader")
    mat:SetSurfaceTexture("palette_tex", world:GetPaletteTexture())
    for i = 0, world:GetVolumeCount() - 1 do world:GetVolume(i).material = mat end
    local z = lg:GetComponent("Zone"); z:SetFogStart(150); z:SetFogEnd(400); z:SetHeightFogEnable(false); z:SetVolumetricFogEnabled(false)
    local cam = scene:CreateChild("Cam")
    local c = cam:CreateComponent("Camera")
    c.farClip = 500
    local ci = CAMS[tonumber(CAM_INDEX or 1) or 1]
    cam.position = ci[1]
    cam:LookAt(ci[2])
    renderer:SetViewport(0, Viewport:new(scene, c))
    _G.keep = scene
end
