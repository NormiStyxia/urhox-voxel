local Pal = require("ruins.RuinsPalette")
local Terrain = require("ruins.RuinsTerrain")
local SkyUtils = require("urhox-libs.Rendering.SkyUtils")
function Start() local ok, e = pcall(Start2) print("START " .. tostring(ok) .. " " .. tostring(e)) end
function Start2()
    local scene = Scene()
    scene:CreateComponent("Octree")
    local world = scene:CreateComponent("VoxelPhysicsWorld")
    Pal.Setup(world)
    local lg = scene:CreateChild("LightGroup")
    lg:LoadXML(cache:GetResource("XMLFile", "LightGroup/TownDay.xml"):GetRoot())
    SkyUtils.CreateGradientSky(scene, { zenith = Color(0.10, 0.28, 0.66), horizon = Color(0.447, 0.638, 1.0), skyExp = 0.5 })
    print("A"); local okb, eb = pcall(Terrain.Build, world); print("B " .. tostring(okb) .. tostring(eb)); ApplyDebugMat(world)
    local z = lg:GetComponent("Zone"); z:SetFogStart(150); z:SetFogEnd(400); z:SetHeightFogEnable(false); z:SetVolumetricFogEnabled(false); print("ZONE " .. tostring(z))
    local cam = scene:CreateChild("Cam")
    local c = cam:CreateComponent("Camera")
    c.farClip = 500
    cam.position = Vector3(0, 30, -45)
    cam:LookAt(Vector3(0, 0, 0))
    renderer:SetViewport(0, Viewport:new(scene, c))
    _G.keep = scene
end
function ApplyDebugMat(world)
    local mat = Material:new()
    print("SS " .. tostring(mat:SetSurfaceShader("Shaders/BLGL/VoxelPalettePBR.shader")))
    mat:SetSurfaceTexture("palette_tex", world:GetPaletteTexture())
    for i = 0, world:GetVolumeCount() - 1 do world:GetVolume(i).material = mat end
end
