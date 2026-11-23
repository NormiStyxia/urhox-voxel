-- Real house/brush generation with recorded voxel occupancy and isolated materials.
-- Static world ports keep stage visibility, collision filters and volume identities observable.
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
        assert(math.max(nx,ny,nz)<=256,('engine voxel grid limit exceeded: %d x %d x %d'):format(nx,ny,nz))
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
        v.rebuilds=0
        function v:RebuildGeometry()self.rebuilds=self.rebuilds+1 end
        function v:At(x,y,z)
            local i,j,k=math.floor((owner.x+x-pos.x)/s),math.floor((owner.base+y-pos.y)/s),math.floor((owner.z+z-pos.z)/s)
            if i<0 or j<0 or k<0 or i>=nx or j>=ny or k>=nz then return end
            return self.cells[key(i,j,k)]
        end
        -- Island-local, half-open bounds. Faces touching the floor or lintel are allowed.
        function v:OccupiesBox(x0,y0,z0,x1,y1,z1)
            local function range(lo,hi,origin,n)
                return math.max(0,math.floor((lo-origin)/s)),math.min(n-1,math.ceil((hi-origin)/s)-1)
            end
            local i0,i1=range(x0,x1,pos.x-owner.x,nx)
            local j0,j1=range(y0,y1,pos.y-owner.base,ny)
            local k0,k1=range(z0,z1,pos.z-owner.z,nz)
            if i1<i0 or j1<j0 or k1<k0 then return false end
            for i=i0,i1 do for j=j0,j1 do for k=k0,k1 do
                if self.cells[key(i,j,k)] then return true end
            end end end
            return false
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
    if key and (key:match('^ground%-') or key=='foundation' or key=='ruin' or key=='one-storey-roof') then
        assert(not pieces[key],key);pieces[key]=v
    end
end
local foundation,main,roof,ruin=pieces.foundation,pieces['ground-floor'],pieces['one-storey-roof'],pieces.ruin
local P=require('ruins.RuinsPalette').P
local front=assert(pieces['ground-front'])
local bars=assert(pieces['ground-front-bars'])
local porch=assert(pieces['ground-porch-frame'])
local rails=assert(pieces['ground-porch-rails'])
assert(home.GetHouseStage()==0 and foundation.node.enabled and ruin.node.enabled and not main.node.enabled)
assert(foundation:At(-4.625,.6875,4.25) and not main:At(-8.5,2.5,9))
assert(front.s==.0625 and bars.s==.03125 and not bars.collidable)

-- Take a row through clear glass, between horizontal rails. Measure contiguous
-- timber runs in the plane ahead of the pane, from the actual occupied cells.
local windows={{x=-14.9375,width=.75,bars={1}}, {x=-12.875,width=1.375,bars={1,2,1}},
    {x=-9.625,width=1,bars={1,1}}}
for _,w in ipairs(windows) do
    local left=w.x-w.width/2
    local runs,glass,width={},0,0
    for i=0,w.width/bars.s-1 do
        local x=left+(i+.5)*bars.s
        if front:At(x,2.28125,7.28125)==156 then glass=glass+1 end
        assert(not main:At(x,2.28125,7.203125),'old front wall crosses the new glazing')
        local mat=bars:At(x,2.28125,7.203125)
        if mat then
            assert(mat==157 and not front:At(x,2.28125,7.203125),'glazing bar overlaps front wall')
            width=width+1
        elseif width>0 then runs[#runs+1]=width;width=0 end
    end
    if width>0 then runs[#runs+1]=width end
    assert(glass*bars.s==w.width-2*front.s,'incorrect recessed glass span at '..w.x)
    assert(table.concat(runs,',')==table.concat(w.bars,','),'incorrect glazing bar widths at '..w.x)
    assert(front:At(w.x-w.width/2-.09375,2.28125,6.90625)==P.HOME_COPING,'missing stone jamb')
end
assert(main:At(-15.8125,2.375,11)==156 and main:At(-12.25,2.375,12.8125)==156)
assert(main:At(-1.1875,2.375,11.625)==156 and roof:At(-10.875,6.3125,10)==P.HOME_CLAY_LIGHT)
for _,face in ipairs({'west','east','back'}) do
    local trim=assert(pieces['ground-'..face..'-bars'])
    assert(trim.s==bars.s and trim.count>0 and not trim.collidable,face)
end
for _,side in ipairs({'left','right'}) do
    local leaf=assert(pieces['ground-door-'..side])
    local materials={}
    for _,mat in pairs(leaf.cells) do materials[mat]=true end
    assert(leaf.s==.03125 and leaf.collidable and materials[156] and materials[150] and materials[P.GOLD_DARK],side)
    local hinge=side=='left' and -5.75 or -3.5
    local insideJamb=hinge+(side=='left' and .046875 or -.046875)
    assert(leaf:At(insideJamb,1.375,7.34375)==157,side..' jamb')
    assert(leaf:OccupiesBox(hinge-.5625,1,8,hinge+.5625,2.5,8.5),side..' door must extend into the room')
end
assert(not ruin:At(-11.25,1,7.25) and ruin:At(-10,1.625,12.75)==P.HOME_ASHLAR)
assert(porch.s==.0625 and rails.s==.0625 and porch.collidable and rails.collidable)
for _,x in ipairs({-6.375,-1.875}) do
    assert(porch:At(x+.03125,2,4.15625)==157,'missing porch post')
    assert(rails:OccupiesBox(x-.125,3,5.25,x+.125,3.3125,5.375),'missing longitudinal beam')
end
assert(porch:At(-4.125,4,3.84375)==157 and porch:At(-3.40625,3.78125,3.96875)==150,'missing king post or diagonal strut')
assert(not home.SetHouseStage(-1) and not home.SetHouseStage(4) and not home.SetHouseStage(1.5))

local stageRanges={foundation={0,3},ruin={0,0},['one-storey-roof']={1,1},second={2,3},secondRoof={2,2},third={3,3}}
local registered=up(home.SetHouseStage,'houseParts')
local groundCount=0
for _,part in ipairs(registered) do
    local key=part.node.name:match('^HomeHouse%-(.+)') or part.node.name
    if pieces[key] then assert(pieces[key]==part.volume,key) end
    local expected=stageRanges[key]
    if key:match('^ground%-') then
        expected={1,3};groundCount=groundCount+1
        assert(part.volume.collidable==(key:match('%-bars$')==nil),key..' collision type')
    end
    if expected then assert(part.first==expected[1] and part.last==expected[2],key..' stage range') end
end
local original={}
for i,v in ipairs(world.volumes) do original[i]={volume=v,rebuilds=v.rebuilds} end
local nextID=world.nextID
local function checkStage(stage)
    assert(home.SetHouseStage(stage));assert(home.GetHouseStage()==stage)
    for _,part in ipairs(registered) do
        local v=part.volume
        local visible=stage>=part.first and stage<=part.last
        assert(v.node.enabled==visible,v.node.name)
        assert(v.collisionMask==(visible and v.collidable and 0xffffffff or 0),v.node.name..' mask')
        assert(v.collisionLayer==(visible and 1 or 0),v.node.name..' layer')
    end
    assert(#world.volumes==houseEnd and world.nextID==nextID,'stage switching allocated volumes')
    for i,v in ipairs(world.volumes) do
        assert(v==original[i].volume and v.rebuilds==original[i].rebuilds,'stage switching replaced or rebuilt a volume')
        -- Sweep a full 1.125 m wide, 2.125 m high box from the porch into the room.
        if stage>=1 and v.node.enabled and v.collidable then
            assert(not v:OccupiesBox(-5.1875,.75,4,-4.0625,2.875,9.25),'door passage blocked by '..(v.node.name or 'scenery'))
        end
    end
end
for _,stage in ipairs({0,1,2,3,3,2,1,0,3}) do checkStage(stage) end
-- A full-width .03125 m brush used to clip the right-hand windows at cell 256.
-- Check the merged frame/transom at both jambs, after clipping against the solid roof.
local function detailAt(group,x,y,z)
    for _,part in ipairs(registered) do
        local name=part.node.name
        if name:find('HomeHouseDetail-'..group..'-',1,true)==1 and part.volume:At(x,y,z) then return true end
    end
    return false
end
for _,w in ipairs(require('ruins.HomeHouseUpper').Windows) do
    if w.nz==-1 then
        local y=w.y-w.height/2+math.floor(w.height*.56/.0625)*.0625
        for _,sign in ipairs({-1,1}) do
            assert(detailAt(w.group,w.x+sign*(w.width/2-.078125),y,w.z-.40625),'clipped upper window at '..w.x)
        end
    end
end
for _,group in ipairs({'secondRoof','third'}) do
    for _,z in ipairs({6.28125,13.71875}) do
        assert(detailAt(group,-16.46875,6.78125,z) and detailAt(group,-.53125,6.78125,z),'clipped fascia in '..group)
    end
end
print('PASS complete upper windows and fascia ends within the 256-cell axis limit')
home.GetHouseOccupants=function() return Vector3(home.x-8,home.base+7,home.z+9),nil end
assert(not home.SetHouseStage(1) and home.GetHouseStage()==3,'do not remove the occupied upper floor')
home.GetHouseOccupants=function() return nil,{{base=Vector3(home.x-8,home.base+4,home.z+9),radius=2.2,height=4.4}} end
assert(not home.SetHouseStage(0),'do not close a structure through a dragon')
home.GetHouseOccupants=nil
checkStage(0)
assert(not roof.node.enabled)
local forge,lip=world.volumes[2],world.volumes[3]
assert(forge:At(1.125,.375,5.125)==146 and lip:At(1.21875,2.65625,7.03125)==197)
print(('PASS %d persistent ground-floor parts across stages 1–3; measured panes, bars, door passage, truss, masks and instance reuse'):format(groundCount))
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
        if not v.node.name and v.s==.0625 and math.abs(cx-x)<.26 and math.abs(cz-z)<.26 then
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
local steps,stalled,lastID=0,0,retryWorld.nextID
repeat
    local done,err=retry:Step();assert(not err,err);steps=steps+1
    stalled=lastID==retryWorld.nextID and stalled+1 or 0
    assert(stalled<500,'house build stopped progressing within a single brush')
    lastID=retryWorld.nextID
until done
assert(home.GetHouseStage()==0)
local restored={}
for _,v in ipairs(retryWorld.volumes) do if v.node.name then restored[v.node.name]=v end end
assert(restored['HomeHouse-foundation']~=oldFoundation and restored['HomeHouse-ruin'].node.enabled)
home.GetHouseOccupants=function() return Vector3(home.x-4.25,home.base+.75,home.z+4.75) end
assert(home.SetHouseStage(3),'open porch passage is safe during restoration')
assert(home.SetHouseStage(3) and restored['HomeHouse-ground-door-left'].node.enabled)
home.SetWindowLightingActive(false);home.SetWindowLightingActive(true)
assert(home.GetHouseStage()==3 and restored['HomeHouse-foundation'].node.enabled)
home.GetHouseOccupants=nil
retry:Cancel();assert(#retryWorld.volumes==1 and retryWorld.volumes[1]==foreign)
print(('PASS cancelled house build disposes its nodes/volumes; retry completes in %d steps and an occupied open passage permits restoration'):format(steps))
print('PASS house timber offline regression (not Web rendering or GPU timing)')
