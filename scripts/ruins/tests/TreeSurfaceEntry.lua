-- 外壳提取回归入口：相邻色块不画内部面，六个朝向均保留。
local Mesh = require("ruins.TreeSurfaceMesh")
local Trees = require("ruins.HomeTrees")
local scene = Scene()
function Start()
    scene:CreateComponent("Octree")
    local zone = scene:CreateChild("Zone"):CreateComponent("Zone")
    zone.boundingBox = BoundingBox(Vector3(-100,-100,-100),Vector3(100,100,100))
    zone.ambientColor = Color(.7,.7,.7)
    local sun = scene:CreateChild("Sun")
    sun.rotation = Quaternion(35, -30, 0)
    local light = sun:CreateComponent("Light")
    light.lightType, light.brightness = LIGHT_DIRECTIONAL, 1.0
    local tree = Trees.Tree(scene,0,0,0,{h=9,r=4.5,trunk=.7,gold=true,lean=1.2,leanA=math.pi,seed=714})
    local material = cache:GetResource("Material", "Materials/HomeTreeVoxel.xml")
    ---@type TreeSurfaceGrid
    local grid = {size=1,cells={},order={}}
    for x=0,1 do
        local cell = {x=x,y=0,z=0,tone=1,ao=255}
        grid.cells[x..":0:0"]=cell
        grid.order[#grid.order+1]=cell
    end
    local fixture = scene:CreateChild("SurfaceFixture")
    fixture.position=Vector3(-5,1,-1)
    local quads, faces = Mesh.Build(grid,fixture,"Adjacent",{Color(.7,.35,.15)},material)
    _G["TREE_MESH_TEST"] = {scene=scene,tree=tree,quads=quads,faces=faces}
    local cameraNode = scene:CreateChild("Camera")
    cameraNode.position = Vector3(13,8,-17)
    cameraNode:LookAt(Vector3(0,5,0))
    local camera = cameraNode:CreateComponent("Camera")
    renderer:SetViewport(0,Viewport:new(scene,camera))
end
