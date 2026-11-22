-- Exercise the real island generators and both grass backends using a Lua 5.4 geometry recorder.
package.path='scripts/?.lua;'..package.path
local function noop() end
local V={};V.__index=V
Vector3=setmetatable({},{__call=function(_,x,y,z) return setmetatable({x=x,y=y,z=z},V) end})
function V.__add(a,b) return Vector3(a.x+b.x,a.y+b.y,a.z+b.z) end
function V.__sub(a,b) return Vector3(a.x-b.x,a.y-b.y,a.z-b.z) end
function V.__mul(a,b) return Vector3(a.x*b,a.y*b,a.z*b) end
function V:LengthSquared() return self.x^2+self.y^2+self.z^2 end
function V:Normalized() return self*(1/math.sqrt(math.max(1e-18,self:LengthSquared()))) end
function V:CrossProduct(v) return Vector3(self.y*v.z-self.z*v.y,self.z*v.x-self.x*v.z,self.x*v.y-self.y*v.x) end
Vector3.UP=Vector3(0,1,0)
Vector2=function(x,y) return {x=x,y=y} end
Vector4,Color=function(...) return {...} end,function(...) return {...} end
Quaternion=function() return setmetatable({},{__mul=function(_,v) return v end}) end
Variant=function(v) return v end
GetPlatform=function() return 'Desktop' end
TRIANGLE_LIST,FILTER_NEAREST,GRASS_PLANT_FLOWER=0,0,1
local function up(fn,name)
    for i=1,100 do local k,v=debug.getupvalue(fn,i);if k==name then return v end end
    error('missing generator '..name)
end
local home=require('ruins.HomeIsland')
local terrain=require('ruins.RuinsTerrain')
local quality=require('ruins.SceneQuality')
local profiles=require('ruins.GameSettings').PROFILES
local function material()
    return {SetSurfaceShader=function()return true end,SetShaderParameter=noop,Clone=function()return material()end}
end
Material={new=material};cache={GetResource=function()return nil end}
local function image()
    return {SetSize=function(self,w,h) self.w,self.h,self.p=w,h,{} end,
        SetPixelInt=function(self,x,y,p) self.p[y*self.w+x]=p end}
end
Image={new=image}
Texture2D={new=function()return {SetNumLevels=noop,SetData=function(t,data)t.data=data end,
    SetFilterMode=function(t,mode)t.filter=mode end,SetAddressMode=noop} end}

local backend='native'
local bladeRoots=0
local function newNode(name)
    local node={name=name,children={},position=Vector3(0,0,0)}
    function node:CreateChild(n) local v=newNode(n);self.children[#self.children+1]=v;return v end
    function node:CreateComponent(kind)
        if kind=='Terrain' then return {} end
        if kind=='GrassField' then
            if backend=='missing' then return nil end
            return {supported=backend=='native',enabled=true,material=material(),
                SetInteractor=function(s,i,p,r) s.slot,s.pos,s.radius=i,p,r end}
        end
        local geo={BeginGeometry=noop,DefineNormal=noop,DefineColor=noop,Commit=noop,SetMaterial=noop}
        function geo:DefineVertex(v) self.last=v end
        function geo:DefineTexCoord(uv)
            if node.name=='Tufts' and uv.y==0 then
                local p=node.position+self.last
                assert(math.abs(p.y+.02-home.Height(p.x,p.z))<.0001,'tuft vertex outside its tread')
                bladeRoots=bladeRoots+1
            end
        end
        return geo
    end
    function node:RemoveComponent(c)c.removed=true end
    function node:Remove() self.removed=true end
    return node
end
local world={vols={},nextID=1}
function world:GetVolumeCount()return #self.vols end
function world:GetVolume(i)return self.vols[i+1] end
function world:RemoveVolume(v)
    for i,s in ipairs(self.vols) do if s==v then table.remove(self.vols,i);return end end
    error('deleted twice')
end
local phase,capHeights,counts='',{},{}
function world:CreateVolume(nx,ny,nz,s,pos)
    local id=self.nextID;self.nextID=id+1
    local v={id=id,phase=phase,s=s,pos=pos,n=nx*ny*nz,nx=nx,ny=ny,nz=nz}
    self.vols[#self.vols+1]=v
    assert(nx<=255 and ny<=255 and nz<=255)
    local grid={GetSolidCount=function(g)return g.used and 1 or 0 end,PaintBox=noop,SetVoxelMaterial=noop}
    function grid:SetSolid(i,j,k,solid) if solid then self.used=true end end
    function grid:FillBox(i,j,k,ii,jj,kk,solid)
        assert(i>=0 and j>=0 and k>=0 and ii<nx and jj<ny and kk<nz and j<=jj,'out-of-range grid fill')
        if solid then self.used=true end
        if phase=='terrain' and s==.25 and solid then
            local x,z=pos.x+(i+.5)*s,pos.z+(k+.5)*s
            local h=pos.y+(jj+1)*s
            assert(h==home.Height(x,z),'voxel/canopy height mismatch')
            capHeights[h]=true
        end
    end
    v.GetGrid=function() return grid end;v.GetVolumeId=function()return id end
    v.GetNode=function()return {Dispose=noop}end;v.Dispose=function()v.disposed=true end
    v.SetCollidable=function(_,value)v.collidable=value end;v.RebuildGeometry=noop
    return v
end
function world:FinalizeVolume(v)v.collidable=true end
local generators={terrain=up(home.Build,'terrain'),shore=up(home.Build,'shoreDetails'),banks=up(home.Build,'banks'),
    trees=up(home.Build,'trees'),meadow=up(home.Build,'meadow'),
    pillar=up(up(home.Build,'courtyard'),'entranceColumn'),join=up(up(home.Build,'house'),'porchJoint')}
local function focusedBuild(w,root)
    for _,key in ipairs({'terrain','banks','pillar','join','shore','trees','meadow'}) do
        phase=key
        if key=='pillar' then generators.pillar(w,4.875,7.125,2.75);generators.pillar(w,4.875,-1.125,1.25)
        elseif key=='join' then generators.join(w,-12.25);generators.join(w,-7)
        elseif key=='meadow' then generators.meadow(root)
        else generators[key](w,root) end
    end
end
local foreign=world:CreateVolume(1,1,1,.5,Vector3(0,0,0))
local function runJob()
    local job=home.BeginBuild(world,newNode('Scene'))
    local frames=0
    repeat
        local done,err=job:Step();assert(not err,err);frames=frames+1;assert(frames<130)
        counts[phase]=(counts[phase] or 0)+1
        if done then return job,frames end
    until false
end
home.Build=focusedBuild
local job,frames=runJob()
local trunkCount,detailCells,capCells,maxCap,shores,separate,stoneBodies=0,0,0,0,0,0,0
local trees={}
for _,n in ipairs(job.root.children) do if n.name=='Tree' then trees[#trees+1]=n end end
for _,v in ipairs(world.vols) do
    if v.phase=='trees' then
        trunkCount=trunkCount+1;local p=trees[trunkCount].position
        assert(home.Ground(p.x,p.z,1) and p.y==home.Height(p.x,p.z) and v.collidable and v.material)
        for _,dx in ipairs({-.6,0,.6}) do for _,dz in ipairs({-.6,0,.6}) do
            assert(home.Height(p.x+dx,p.z+dz)==p.y,'exposed root overhang')
        end end
        assert(p.x>=v.pos.x and p.x<v.pos.x+v.nx*v.s and p.z>=v.pos.z and p.z<v.pos.z+v.nz*v.s and p.y==v.pos.y)
    elseif v.phase=='pillar' or v.phase=='join' then
        detailCells=detailCells+v.n
        if v.s==.0625 then assert(v.collidable==false and v.collisionMask==0);separate=separate+1
        else assert(v.s==.125 and v.collidable);stoneBodies=stoneBodies+1 end
    elseif v.phase=='terrain' and v.s==.25 then capCells=capCells+v.n;maxCap=math.max(maxCap,v.n)
    elseif v.phase=='shore' and not v.collidable then shores=shores+1;assert(v.n<90000) end
end
assert(#trees==8 and trunkCount==#trees and shores==8)
assert(separate==4 and stoneBodies==2 and detailCells<20000 and maxCap<=51000)
for _,h in ipairs({.25,.5,.75,1,1.25,1.5,1.75}) do assert(capHeights[home.base+h]) end
assert(home.Safe(home.x+5,home.base+.1,home.z-12) and home.GrassAt(home.x+5,home.z-12)==0)
for _,p in ipairs({{-7,-5},{-11.75,-15},{-9,7},{1,6},{12,3},{12,-8},{4,0},{28,18}}) do
    assert(home.GrassAt(home.x+p[1],home.z+p[2])==0)
end
print(('PASS 8 rooted collidable trees, 8 shore sectors, 7 terrace rises; %d cap cells / %d max per chunk'):format(capCells,maxCap))
print(('PASS 2 structural entrance pillars and 4 visual trims/joints; %d added detail cells. %d focused build steps.'):format(detailCells,frames))
local field=home.field
local height,mask=field.terrain.heightMap,field.splat.data
assert(height.w==129 and mask.w==128 and field.splat.filter==FILTER_NEAREST and field.terrain.viewMask==0)
local planted,raised=0,0
for row=0,127 do for col=0,127 do
    local w=mask.p[row*128+col]>>24
    if w>0 then
        local h=height.p[row*129+col]/32+field.terrainNode.position.y
        assert(height.p[row*129+col+1]==height.p[row*129+col] and height.p[(row+1)*129+col]==height.p[row*129+col]
            and height.p[(row+1)*129+col+1]==height.p[row*129+col])
        for _,dx in ipairs({.125,.375}) do for _,dz in ipairs({.125,.375}) do
            local x,z=home.x-32+col*.5+dx,home.z+32-row*.5-dz
            assert(home.Height(x,z)==h,'native grass floats')
        end end
        planted=planted+1;if h>home.base then raised=raised+1 end
    end
end end
assert(raised>100 and planted>1000 and counts.meadow>=9)
terrain.home=home;terrain.grass={enabled=true,SetInteractor=field.grass.SetInteractor}
for _,p in ipairs({profiles.low,profiles.medium,profiles.high,{grassDensity=0,grassDistance=24},profiles.medium}) do
    quality.ApplyGrass(field,p)
    assert(field.grass.density==110*p.grassDensity and field.grass.viewDistance==p.grassDistance and field.grass.enabled==(p.grassDensity>0))
    assert(field.flowers.density==2.5*p.grassDensity and field.flowers.enabled==field.grass.enabled)
end
local pos=Vector3(home.x,home.base,2);terrain.SetInteractor(1,pos,2.2)
assert(terrain.grass.pos==pos and field.grass.pos==pos and field.flowers.radius==2.2)
job:Cancel();job:Cancel();assert(#world.vols==1 and world.vols[1]==foreign and job.root.removed and home.field==nil)
local done,err=job:Step();assert(not done and err)
print(('PASS native grass and flowers, %d planted mask texels (%d elevated), quality and world-space contact'):format(planted,raised))
home.Build=function(_,root)phase='meadow';generators.meadow(root)end
terrain.tufts={material=material()}
for _,mode in ipairs({'unsupported','missing'}) do
    backend=mode;bladeRoots=0;counts.meadow=0
    local fallbackJob=runJob();local tufts=home.field.tufts;local total=#tufts.tiles
    assert(tufts.material==terrain.tufts.material)
    assert(bladeRoots>5000 and counts.meadow>=6 and home.field.terrain==nil and not home.field.grass)
    for i,p in ipairs({profiles.high,profiles.medium,profiles.low,{grassDensity=0,grassDistance=24},profiles.high}) do
        quality.ApplyGrass(home.field,p)
        local enabled=0;for _,t in ipairs(tufts.tiles)do if t.node.enabled then enabled=enabled+1 end;assert(t.drawable.drawDistance==p.grassDistance) end
        assert(enabled==({total,math.ceil(total/2),math.ceil(total/4),0,total})[i])
    end
    fallbackJob:Cancel();assert(home.field==nil and fallbackJob.root.removed)
    print(('PASS %s fallback, %d tiles, %d sampled blade roots, %d steps; tier switch/teardown'):format(mode,total,bladeRoots,counts.meadow))
end
local interrupted=home.BeginBuild(world,newNode('Scene'))
for _=1,5 do local _,e=interrupted:Step();assert(not e,e)end
interrupted:Cancel();assert(not home.field and interrupted.root.removed and world.vols[1]==foreign)
terrain.home=nil;terrain.Stop();assert(terrain.grass==nil and terrain.flowers==nil)
print('PASS mid-build cancellation preserves foreign volumes, releases scene, and permits retry')
