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
local function fixture(owner,empty)
    local world={volumes={},palette={},nextID=1}
    function world:GetPaletteTexture()return self.palette end
    function world:CreateVolume(nx,ny,nz,s,pos)
        local v={nx=nx,ny=ny,nz=nz,s=s,pos=pos,cells={},count=0,id=self.nextID}
        self.nextID=self.nextID+1
        v.node={enabled=true};v.collisionLayer=1;v.collisionMask=0xffffffff
        function v:GetNode()return self.node end
        function v:GetVolumeId()return self.id end
        function v:Dispose() assert(not self.disposed);self.disposed=true end
        function v.node:Dispose() assert(not self.disposed);self.disposed=true end
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
        function grid:GetVoxelMaterial(i,j,k)return v.cells[key(i,j,k)] or 0 end
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
    function world:GetVolumeCount()return #self.volumes end
    function world:GetVolume(i)return self.volumes[i+1] end
    function world:RemoveVolume(v)
        for i,current in ipairs(self.volumes) do
            if current==v then table.remove(self.volumes,i);return end
        end
        error('volume was already removed')
    end
    -- Execute the real material cache, including its shared size:masonry key.
    local env=setmetatable({M={},world_=world,Brush=brush,HomeIsland=owner,Terrain={WALL_R=51}},{__index=_G})
    assert(load(assert(read('scripts/ruins/RuinsScene.lua'):match('(local vmats = {}.-)    %-%- 法阵灯')),'real material cache','t',env))()
    if not empty then up(owner.Build,'house')(world) end
    return world,env.M.surfaceMaterials
end
local world,cache=fixture(home)
local houseEnd=#world.volumes
local pieces={}
for _,v in ipairs(world.volumes) do
    local key=(v.node.name or ''):match('^HomeHouse%-(.+)')
    if key then assert(not pieces[key]);pieces[key]=v end
end
local foundation,main,roof,ruin=pieces.foundation,pieces['ground-floor'],pieces['one-storey-roof'],pieces.ruin
local second,third=pieces.second,pieces.third
local P=require('ruins.RuinsPalette').P
assert(home.GetHouseStage()==0 and foundation.node.enabled and ruin.node.enabled and not main.node.enabled)
assert(foundation:At(-4.25,.625,4.25) and not main:At(-4.25,1.75,7.25) and not main:At(-8.5,2.5,9))
assert(main:At(-13.625,2.375,7.1875)==156 and main:At(-13.875,2.375,7.0625)==157)
assert(main:At(-15.8125,2.375,11)==156 and main:At(-12.25,2.375,12.8125)==156)
assert(main:At(-1.1875,2.375,11.625)==156 and roof:At(-10.875,6.4375,10)==P.HOME_CLAY_LIGHT)
assert(not ruin:At(-11.25,1,7.25) and ruin:At(-10,1.625,12.75)==P.HOME_ASHLAR)
assert(main:At(-6.375,2.0,4.375)==157 and main:At(-4.25,4.125,3.6875)==157)
assert(not home.SetHouseStage(-1) and not home.SetHouseStage(4) and not home.SetHouseStage(1.5))
for _,stage in ipairs({1,2,3,2,1,0,3}) do
    assert(home.SetHouseStage(stage));assert(home.GetHouseStage()==stage)
    local visible={foundation=true,ruin=stage==0,['ground-floor']=stage>=1,['one-storey-roof']=stage==1,
        second=stage>=2,secondRoof=stage==2,third=stage==3}
    for k,v in pairs(pieces) do
        assert(v.node.enabled==visible[k],k)
        assert(v.collisionMask==(visible[k] and 0xffffffff or 0) and v.collisionLayer==(visible[k] and 1 or 0),k)
    end
    assert(#world.volumes==houseEnd and foundation==pieces.foundation and main==pieces['ground-floor'] and second==pieces.second)
end
home.GetHouseOccupants=function() return Vector3(home.x-8,home.base+7,home.z+9),nil end
assert(not home.SetHouseStage(1) and home.GetHouseStage()==3,'do not remove the occupied upper floor')
home.GetHouseOccupants=function() return nil,{{base=Vector3(home.x-8,home.base+4,home.z+9),radius=2.2,height=4.4}} end
assert(not home.SetHouseStage(0),'do not close a structure through a dragon')
home.GetHouseOccupants=nil
assert(home.SetHouseStage(0) and not roof.node.enabled and not third.node.enabled)
local forge,lip=world.volumes[2],world.volumes[3]
assert(forge:At(1.125,.375,5.125)==146 and lip:At(1.21875,2.65625,7.03125)==197)
print('PASS seven persistent house groups; stages, jumps, downgrades, masks, isolated forge, hollow room, door, arched glass, gable, and occupied-floor/dragon veto')
local function localCell(v,key)
    local i,j,k=key//(v.ny*v.nz),(key//v.nz)%v.ny,key%v.nz
    return v.pos.x-home.x+(i+.5)*v.s,v.pos.y-home.base+(j+.5)*v.s,v.pos.z-home.z+(k+.5)*v.s
end
up(home.Build,'courtyard')(world)
local floor=world.volumes[houseEnd+1]
assert(floor:At(12,1.625,3)==P.HOME_PAVING and floor:At(4,1.625,3)==P.HOME_PAVING)
assert(not floor:At(3.375,1.625,3) and home.Height(home.x+3.375,home.z+3)==home.base+1.5)
assert(up(up(home.Build,'terrain'),'lawnMaterial')(3.375,3,1.5)==P.STONE_B,'outer stone shoulder belongs to RuinsGround')
local bankIndex=#world.volumes+1
up(home.Build,'banks')(world)
local bank=world.volumes[bankIndex]
assert(bank:At(4,2.375,2)==P.HOME_ASHLAR and bank:At(4,2.625,2)==P.HOME_PLINTH and bank:At(4,3.125,2)==P.HOME_COPING)
assert(#world.volumes==bankIndex+7,'three tall pond pillars and one shared short base/capital volume')
for i=bankIndex+1,#world.volumes do
    local trim=world.volumes[i]
    assert(trim.s==.0625 and not trim.collidable and trim.collisionMask==0)
    for k in pairs(trim.cells) do local x,y,z=localCell(trim,k);assert(not bank:At(x,y,z) and not floor:At(x,y,z),'overlapping pond trim') end
end
-- Every surviving capital must have local, collision-free trim at its actual snapped centre.
local function checkColumn(x,z,cap,footVisible)
    local foot,lip=false,false
    for _,v in ipairs(world.volumes) do
        local cx=v.pos.x-home.x+v.nx*v.s*.5
        local cz=v.pos.z-home.z+v.nz*v.s*.5
        if v.s==.0625 and math.abs(cx-x)<.26 and math.abs(cz-z)<.26 then
            assert(not v.collidable and v.collisionMask==0)
            for key,mat in pairs(v.cells) do
                local _,y=localCell(v,key)
                if y<cap-.57 then foot=true end
                if y>=cap-.5 and mat==P.HOME_COPING then lip=true end
                if foot and lip then break end
            end
        end
    end
    assert(lip and foot==footVisible,('missing or buried moulding at %.3f, %.3f'):format(x,z))
end
for _,i in ipairs({0,1,2,3,4,8,10,11}) do
    local a=i*math.pi/6
    checkColumn(12+8.3*math.cos(a),3+8.3*math.sin(a),i==1 and 4.5 or 3,true)
end
for _,p in ipairs({{4.875,7.125,4.5},{4.875,-1.125,3},{-18,-7,3},{-14,-13,1.75},{2,-8,2.25},{4,2,3.25},
    {-15.5,13.5,5.25},{-3.5,13.5,5.25},{-20.8,9,3.5},{-20,6,5.5},{2.5,11.5,6.25},{-1,15,4.75}}) do
    checkColumn(p[1],p[2],p[3],true)
end
checkColumn(-15.2,9,3.5,false) -- the permanent platform encloses this footing
print('PASS 21 distinct capitals and 20 exposed footings')
print('PASS courtyard/outer shoulder, solid coping, open mouth, 0.375 m arch lining and independent collision-free moulding')
-- Interrupt the real house generator between registrations, then rebuild in the same world.
local generator=up(home.Build,'house')
local retryWorld=fixture(home,true)
local foreign=retryWorld:CreateVolume(1,1,1,.25,Vector3(0,0,0))
local scene={CreateChild=function() return {Remove=function(self) self.removed=true end} end}
home.Stop()
home.Build=generator
local interrupted=home.BeginBuild(retryWorld,scene)
assert(not home.SetHouseStage(1),'pending build must reject stage changes before its first step')
local oldFoundation
for step=1,500 do
    local done,err=interrupted:Step();assert(not done and not err,err)
    local latest=retryWorld.volumes[#retryWorld.volumes]
    if latest.node.name=='HomeHouse-foundation' then oldFoundation=latest end
    if latest.node.name=='HomeHouse-ruin' then break end
end
assert(oldFoundation and retryWorld.volumes[#retryWorld.volumes].node.name=='HomeHouse-ruin')
assert(not home.SetHouseStage(2),'partially built structures must reject stage changes')
local interruptedVolumes={table.unpack(retryWorld.volumes,2)}
interrupted:Cancel();interrupted:Cancel()
assert(interrupted.root.removed and #retryWorld.volumes==1 and retryWorld.volumes[1]==foreign)
for _,v in ipairs(interruptedVolumes) do assert(v.disposed and v.node.disposed) end
local retry=home.BeginBuild(retryWorld,scene)
local steps=0
repeat
    local done,err=retry:Step();assert(not err,err);steps=steps+1;assert(steps<500)
until done
assert(home.GetHouseStage()==0)
local restored={}
for _,v in ipairs(retryWorld.volumes) do if v.node.name then restored[v.node.name]=v end end
assert(restored['HomeHouse-foundation']~=oldFoundation and restored['HomeHouse-ruin'].node.enabled)
home.GetHouseOccupants=function() return Vector3(home.x-4.25,home.base+.75,home.z+4.75) end
assert(home.SetHouseStage(3),'open porch passage is safe during restoration')
assert(home.SetHouseStage(3) and restored['HomeHouse-third'].node.enabled)
home.SetWindowLightingActive(false);home.SetWindowLightingActive(true)
assert(home.GetHouseStage()==3 and restored['HomeHouse-foundation'].node.enabled)
home.GetHouseOccupants=nil
retry:Cancel();assert(#retryWorld.volumes==1 and retryWorld.volumes[1]==foreign)
print(('PASS cancelled house build disposes its nodes/volumes; retry completes in %d steps and an occupied open passage permits restoration'):format(steps))
print('PASS house timber offline regression (not Web rendering or GPU timing)')
