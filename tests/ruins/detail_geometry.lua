-- 纯 Lua 5.4 回归：采样实际建筑生成器，检查门洞、分块接缝、尺寸预算；
-- 抽取树干生成器，检查共面合并、硬法线、绕序和方格对齐。非引擎渲染测试。
package.path = "scripts/?.lua;" .. package.path
local V = {}; V.__index = V
Vector3 = setmetatable({ UP = setmetatable({x=0,y=1,z=0}, V) }, { __call = function(_,x,y,z) return setmetatable({x=x,y=y,z=z},V) end })
function V.__add(a,b) return Vector3(a.x+b.x,a.y+b.y,a.z+b.z) end
function V.__sub(a,b) return Vector3(a.x-b.x,a.y-b.y,a.z-b.z) end
function V.__mul(a,b) if type(a)=="number" then a,b=b,a end return Vector3(a.x*b,a.y*b,a.z*b) end
Vector2 = function(x,y) return {x=x,y=y} end
Quaternion = function(yaw) return setmetatable({}, {__mul=function(_,v)
    local a=math.rad(yaw); return Vector3(v.x*math.cos(a)+v.z*math.sin(a),v.y,-v.x*math.sin(a)+v.z*math.cos(a))
end}) end
TRIANGLE_LIST = 0
local function up(fn, name)
    for i=1,100 do local k,v=debug.getupvalue(fn,i); if not k then break end; if k==name then return v end end
    error("missing upvalue "..name)
end
local Build = require("ruins.RuinsBuild")
local Brush = require("ruins.VoxelBrush")
local counts, allocations, occupied, wallCells = {}, {}, {}, {}
local phase
local world = {}
function world:CreateVolume(nx,ny,nz,s,pos,rot)
    local cells={}
    if phase=="wall" and s==.125 then wallCells[#wallCells+1]={pos=pos,rot=rot,cells=cells} end
    assert(nx<=255 and ny<=255 and nz<=255, "oversized volume")
    allocations[phase]=(allocations[phase] or 0)+nx*ny*nz
    local grid = {}
    function grid:SetSolid(i,j,k,solid)
        assert(i>=0 and i<nx and j>=0 and j<ny and k>=0 and k<nz)
        if solid then
            counts[phase]=(counts[phase] or 0)+1
            if phase=="wall" and s==0.125 then
                local p=pos+rot*Vector3((i+.5)*s,(j+.5)*s,(k+.5)*s)
                local x,y,z=p.x,p.y,p.z
                assert(not(math.abs(x)<2 and math.abs(math.abs(z)-51)<1 and y>6.25 and y<9), "gate blocked")
                if math.abs(y-7.0625)<.001 then cells[i..":"..k]=true end
            end
        end
    end
    function grid:SetVoxelMaterial() end
    function grid:FillBox() end
    function grid:PaintBox() end
    local volume={}
    function volume:GetSolidCount() return 1 end
    function volume:GetGrid() return grid end
    function volume:RebuildGeometry() end
    return volume
end
function world:FinalizeVolume() end
function world:FinalizeVolumeAsVisual() end
function world:FinalizeVolumeAsDynamic() end
for _, pair in ipairs({{"colonnade","BuildColonnade"},{"fallen","BuildFallenColumns"},{"wall","BuildOuterWall"},{"hall","BuildNorthHall"}}) do
    phase=pair[1]
    local t=os.clock()
    up(Build.Build,pair[2])(world)
    print(string.format("%s: cells=%d allocated=%d %.2fs",phase,counts[phase] or 0,allocations[phase],os.clock()-t))
end
-- Query actual rotated wall grids at their shared polygon vertices.
local function solid(x,z)
    for _,w in ipairs(wallCells) do
        local px,pz=x-w.pos.x,z-w.pos.z
        local ex,ez=w.rot*Vector3(1,0,0),w.rot*Vector3(0,0,1)
        local i=math.floor((px*ex.x+pz*ex.z)/.125)
        local k=math.floor((px*ez.x+pz*ez.z)/.125)
        if w.cells[i..":"..k] then return true end
    end
    return false
end
for seg=0,31 do
    if seg~=1 and seg~=8 and seg~=24 then
        local a=seg*math.pi/16
        for delta=-1,1 do
            assert(solid(math.cos(a+delta*.0005)*51,math.sin(a+delta*.0005)*51),"wall segment gap "..seg)
        end
    end
end
local Trees=require("ruins.RuinsTrees")
local NewWood=up(Trees.Tree,"NewWood")
local verts,normals={},{}
local geo={}
function geo:BeginGeometry() end
function geo:DefineVertex(v) verts[#verts+1]=v end
function geo:DefineNormal(v) normals[#normals+1]=v end
function geo:DefineTexCoord() end
function geo:Commit() end
function geo:SetMaterial() end
local parent={CreateChild=function() return {CreateComponent=function() return geo end} end}
local function checkMesh()
    assert(#verts%6==0)
    for i=1,#verts do
        for _,a in ipairs({"x","y","z"}) do assert(math.abs(verts[i][a]/.0625-math.floor(verts[i][a]/.0625+.5))<1e-8) end
        local n=normals[i]; assert(math.abs(n.x)+math.abs(n.y)+math.abs(n.z)==1)
    end
    for i=1,#verts,3 do
        local a,b,n=verts[i+1]-verts[i],verts[i+2]-verts[i],normals[i]
        assert((a.y*b.z-a.z*b.y)*n.x+(a.z*b.x-a.x*b.z)*n.y+(a.x*b.y-a.y*b.x)*n.z<0,"inverted/degenerate face")
    end
end
local wood=NewWood(parent)
wood:Path({Vector3(0,0,0),Vector3(0,2,0)},.25)
local cells=#wood.cells
wood:Path({Vector3(0,0,0),Vector3(0,2,0)},.25)
assert(#wood.cells==cells,"overlap not merged")
local straight=wood:Finish(); assert(straight<80,"chamfered trunk must merge coplanar cells")
checkMesh()
verts,normals={},{}
wood=NewWood(parent)
wood:Path({Vector3(0,0,0),Vector3(.1,2,0),Vector3(.4,5,.2),Vector3(.6,7,.3)},.45)
wood:Path({Vector3(.3,4,.1),Vector3(1.2,5,.3),Vector3(2.5,6,.5)},.14)
local quads=wood:Finish(); checkMesh()
assert(quads<10000,"tree mesh budget exceeded")
print(string.format("tree: %d quads / %d vertices; grid, merge, normals, winding PASS",quads,#verts))
print("detail geometry PASS (Lua mock; not Web rendering/physics)")
