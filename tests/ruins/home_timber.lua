-- Real house/brush generation with recorded voxel occupancy and isolated materials.
-- This does not compile SurfaceShader or render pixels; optional baseline is a saved Lua source.
package.path='scripts/?.lua;'..package.path
local V={};V.__index=V
Vector3=setmetatable({},{__call=function(_,x,y,z)return setmetatable({x=x,y=y,z=z},V)end})
function V.__add(a,b)return Vector3(a.x+b.x,a.y+b.y,a.z+b.z)end
Quaternion=function()return setmetatable({},{__mul=function(_,v)return v end})end
Vector4=function(x,y,z,w)return {x=x,y=y,z=z,w=w}end
Variant=function(v)return v end
local function material()
    local m={params={}}
    function m:SetSurfaceShader()return true end
    function m:SetSurfaceTexture(k,v)self[k]=v end
    function m:SetShaderParameter(k,v)self.params[k]=v end
    function m:Clone()
        local copy=material()
        for k,v in pairs(self.params)do copy.params[k]=v end
        copy.palette_tex=self.palette_tex
        return copy
    end
    return m
end
Material={new=material}
local home=require('ruins.HomeIsland')
local brush=require('ruins.VoxelBrush')
local function up(fn,key)
    for i=1,100 do local k,v=debug.getupvalue(fn,i);if k==key then return v end;if not k then break end end
    error('missing generator '..key)
end
local function read(path)local f=assert(io.open(path));local s=f:read('*a');f:close();return s end
local function fixture(owner)
    local world={volumes={},palette={}}
    function world:GetPaletteTexture()return self.palette end
    function world:CreateVolume(nx,ny,nz,s,pos)
        local v={nx=nx,ny=ny,nz=nz,s=s,pos=pos,cells={},count=0}
        local grid={}
        local function key(i,j,k)
            assert(i>=0 and j>=0 and k>=0 and i<nx and j<ny and k<nz,'out of volume')
            return (i*ny+j)*nz+k
        end
        function grid:SetSolid(i,j,k,solid)
            local id=key(i,j,k);local old=v.cells[id]
            if solid then if not old then v.count=v.count+1;v.cells[id]=true end
            elseif old then v.count=v.count-1;v.cells[id]=nil end
        end
        function grid:SetVoxelMaterial(i,j,k,id)assert(v.cells[key(i,j,k)]);v.cells[key(i,j,k)]=id end
        function grid:FillBox(i,j,k,ii,jj,kk,solid)
            for x=i,ii do for y=j,jj do for z=k,kk do self:SetSolid(x,y,z,solid) end end end
        end
        function grid:PaintBox(i,j,k,ii,jj,kk,id)
            for x=i,ii do for y=j,jj do for z=k,kk do if v.cells[key(x,y,z)]then self:SetVoxelMaterial(x,y,z,id)end end end end
        end
        function grid:GetSolidCount()return v.count end
        function grid:IsSolid(i,j,k)return v.cells[key(i,j,k)]~=nil end
        function v:GetGrid()return grid end
        function v:SetCollidable(value)self.collidable=value end
        function v:RebuildGeometry()end
        function v:At(x,y,z)
            local i,j,k=math.floor((owner.x+x-pos.x)/s),math.floor((owner.base+y-pos.y)/s),math.floor((owner.z+z-pos.z)/s)
            if i<0 or j<0 or k<0 or i>=nx or j>=ny or k>=nz then return end
            return self.cells[key(i,j,k)]
        end
        world.volumes[#world.volumes+1]=v
        return v
    end
    function world:FinalizeVolume(v)v.collidable=true end
    function world:RemoveVolume()error('unexpected empty house volume')end
    -- Execute the real material cache, including its shared size:masonry key.
    local env=setmetatable({M={},world_=world,Brush=brush,HomeIsland=owner,Terrain={WALL_R=51}},{__index=_G})
    assert(load(assert(read('scripts/ruins/RuinsScene.lua'):match('(local vmats = {}.-)    %-%- 法阵灯')),'real material cache','t',env))()
    up(owner.Build,'house')(world)
    return world,env.M.surfaceMaterials
end
local world,cache=fixture(home)
assert(#world.volumes==5,'wood fix must not add house volumes')
local main,j1,j2,loft=world.volumes[2],world.volumes[3],world.volumes[4],world.volumes[5]
assert(j1.material~=j2.material and j1.material~=cache['0.0625:plain'] and j2.material~=cache['0.0625:plain'])
assert(cache['0.0625:plain'].params.wood_center==nil,'joint centre leaked to shared material')
for i,pair in ipairs({{j1,-12.25},{j2,-7}})do
    local joint,x=pair[1],pair[2]
    local c=joint.material.params.wood_center
    assert(c.x==home.x+x and c.y==home.base+3.03125 and c.z==home.z+4 and c.w==1)
    assert(not joint.collidable and joint.collisionMask==0,'visual join changed collision')
    assert(joint.material.palette_tex==world.palette,'cloned material lost palette')
    assert(joint:At(x,3.03125,3.78125)==158,'tenon lost Z grain')
    assert(joint:At(x+.28125,3.03125,4)==150,'shoulder lost X grain')
    print('PASS joint',i,'private material centre',c.x,c.y,c.z,'X shoulder and Z tenon')
end
local second=j2.material.params.wood_center
j1.material:SetShaderParameter('wood_center',Vector4(1,2,3,1))
assert(j2.material.params.wood_center==second and cache['0.0625:plain'].params.wood_center==nil)
print('PASS changing one joint material leaves the other joint and shared cache untouched')
for _,d in ipairs({{-12.75,7,-5.25,12,4,3},{-11.875,8.125,-6.375,11.875,8.125,2.625}})do
    local x0,z0,x1,z1,y,h=table.unpack(d)
    for _,level in ipairs({y,y+h-.25})do
        assert(loft:At(x0-.0625,level+.0625,(z0+z1)/2)==159,('left side beam must run Z at %.4f %.4f %.4f; got %s'):format(x0-.0625,level+.0625,(z0+z1)/2,tostring(loft:At(x0-.0625,level+.0625,(z0+z1)/2))))
        assert(loft:At(x1+.0625,level+.0625,(z0+z1)/2)==159,'right side beam must run Z')
        local function xgrain(id)return id==150 or id==151 or id==152 end
        assert(xgrain(loft:At(x0+1.5,level+.0625,z0-.0625)),'front beam must run X')
        assert(xgrain(loft:At(x0+1.5,level+.0625,z1+.0625)),'back beam must run X')
        assert(xgrain(loft:At(x0-.0625,level+.0625,z1+.0625)),'corner ownership changed')
        for x=x0-.0625,x1+.0625,.125 do
            assert(xgrain(loft:At(x,level+.0625,z0-.0625)),'front post/roof overwrote X beam')
            assert(xgrain(loft:At(x,level+.0625,z1+.0625)),'back post/roof overwrote X beam')
        end
        for z=z0+.1875,z1-.1875,.125 do
            assert(loft:At(x0-.0625,level+.0625,z)==159,'left Z beam interrupted')
            assert(loft:At(x1+.0625,level+.0625,z)==159,'right Z beam interrupted')
        end
    end
end
assert(main:At(1.125,.375,5.125)==146,'anvil base palette/shape changed')
assert(main.material==cache['0.125:homeWindows'] and loft.material==main.material and home.housing==main.material)
assert(main.material.params.wood_center==nil,'private centre leaked into windows/house')
print('PASS both storeys, all four perimeter beam axes and unchanged anvil/window material binding')
local function localCell(v,key)
    local i,j,k=key//(v.ny*v.nz),(key//v.nz)%v.ny,key%v.nz
    return v.pos.x-home.x+(i+.5)*v.s,v.pos.y-home.base+(j+.5)*v.s,v.pos.z-home.z+(k+.5)*v.s
end
for k in pairs(main.cells)do
    local x,y,z=localCell(main,k)
    assert(not loft:At(x,y,z) and not world.volumes[1]:At(x,y,z),'main roof intersects loft or arch')
end
print('PASS each main-roof voxel has a single owner across house grids')
if TIMBER_BASELINE then
    local before=assert(load(read(TIMBER_BASELINE),'house before fix'))()
    local old=fixture(before)
    assert(#old.volumes==#world.volumes)
    for i,a in ipairs(old.volumes)do
        local b=world.volumes[i]
        assert(a.nx==b.nx and a.ny==b.ny and a.nz==b.nz and a.s==b.s)
        assert(a.pos.x==b.pos.x and a.pos.y==b.pos.y and a.pos.z==b.pos.z)
        assert(a.collidable==b.collidable and a.collisionMask==b.collisionMask)
        -- A removed duplicate still has to be solid in another structural grid or the ground.
        for key in pairs(a.cells)do if not b.cells[key] then
            local x,y,z=localCell(a,key)
            local supported=home.Ground(home.x+x,home.z+z) and home.base+y<home.Height(home.x+x,home.z+z)
            for _,v in ipairs(world.volumes)do
                if v.collidable and v:At(x,y,z) then supported=true;break end
            end
            assert(supported,'removed an exterior cell')
        end end
        for key in pairs(b.cells)do assert(a.cells[key],'added occupied cell')end
        print('PASS baseline occupancy/collision',i,b.count,'cells; no geometry/volume growth')
    end
end
print('PASS house timber offline regression (not Web rendering or GPU timing)')
