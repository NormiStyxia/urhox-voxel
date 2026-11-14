-- 离线引擎 mock：验证生成数据和逻辑，不等价于引擎渲染/物理验收。
local mt={}; mt.__index=mt
function mt.__add(a,b) return Vector3(a.x+b.x,a.y+b.y,a.z+b.z) end
function mt.__sub(a,b) return Vector3(a.x-b.x,a.y-b.y,a.z-b.z) end
function mt.__mul(a,b) if type(a)=='number' then a,b=b,a end return Vector3(a.x*b,a.y*b,a.z*b) end
function mt:LengthSquared() return self.x^2+self.y^2+self.z^2 end
function mt:Length() return math.sqrt(self:LengthSquared()) end
function mt:Normalized() local n=self:Length(); if n==0 then return Vector3(0,0,0) end return self*(1/n) end
function mt:CrossProduct(b) return Vector3(self.y*b.z-self.z*b.y,self.z*b.x-self.x*b.z,self.x*b.y-self.y*b.x) end
function mt:Lerp(b,k) return self+(b-self)*k end
Vector3=setmetatable({},{__call=function(_,x,y,z) return setmetatable({x=x,y=y,z=z},mt) end})
Vector3.UP=Vector3(0,1,0); Vector3.DOWN=Vector3(0,-1,0); Vector3.ZERO=Vector3(0,0,0)
Ray=function(origin,direction) return {origin=origin,direction=direction} end
Vector2=function(x,y) return {x=x,y=y} end
Color=function(r,g,b,a) return {r=r,g=g,b=b,a=a or 1} end
Variant=function(v) return v end
local noop=function() end
Material={new=function() return {SetSurfaceShader=function() return true end,SetSurfaceTexture=noop,SetShaderParameter=noop} end}
Texture2D={new=function() return {SetNumLevels=noop,SetData=noop,SetFilterMode=noop,SetAddressMode=noop} end}
Image={new=function() return {SetSize=function(self,w,h,c) self.width,self.height=w,h end,SetPixel=noop,SetPixelInt=noop} end}
package.loaded['ruins.RuinsPalette']={P={CLIFF_A=1,CLIFF_B=2,CLIFF_C=3,CLIFF_D=4}}
local T=require('ruins.RuinsTerrain')
local world={columns={},volumes={}}
function world:CreateVolume(nx,ny,nz,c,pos)
    local grid={PaintBox=noop}
    function grid:FillBox(x,y,z,x1,y1,z1)
        assert(x==x1 and z==z1 and y>=0 and y1<ny)
        local wx,wz=pos.x+(x+.5)*c,pos.z+(z+.5)*c
        assert(T.HasGround(wx,wz),'collision column in void')
        world.columns[wx..':'..wz]={lo=pos.y+y*c,hi=pos.y+(y1+1)*c}
    end
    local v={GetGrid=function() return grid end,RebuildGeometry=noop}
    self.volumes[#self.volumes+1]={nx=nx,ny=ny,nz=nz,c=c,pos=pos}
    return v
end
world.FinalizeVolume=noop
local scene={nodes={},maxVertices=0}
function scene:CreateChild(name)
    local node={position=Vector3.ZERO,name=name}; self.nodes[#self.nodes+1]=node
    function node:CreateComponent(kind)
        if kind=='CustomGeometry' then
            local g={n=0,BeginGeometry=noop,DefineNormal=noop,DefineTexCoord=noop,DefineColor=noop,SetMaterial=noop}
            function g:DefineVertex(v) assert(v.y==v.y); self.n=self.n+1 end
            function g:Commit() scene.maxVertices=math.max(scene.maxVertices,self.n) end
            return g
        elseif kind=='Terrain' then
            local t={GetHeight=function() return 6 end}; scene.source=t; return t
        elseif kind=='GrassField' then return {supported=false} end
    end
    node.RemoveComponent=noop
    return node
end
package.loaded['ruins.GrassTufts']={Build=function() return {} end}
T.Build(world,scene)
assert(scene.source.viewMask==0 and not scene.source.castShadows)
assert((scene.source.heightMap.width-1)%scene.source.patchSize==0)
assert((scene.source.heightMap.width-1)*scene.source.spacing.x==168)
assert(scene.maxVertices<65536,'Web mesh too large')
print('PASS collision generation: all filled columns inside island; no void columns')
print('COST collision chunks='..T.collisionStats.chunks..' allocated='..T.collisionStats.allocated..' solid='..T.collisionStats.solid)
print('COST mesh triangles='..T.meshStats.triangles..' chunks='..T.meshStats.chunks..' max vertices='..scene.maxVertices)
local function support(x,z)
    assert(T.HasGround(x,z),'missing support '..x..','..z)
    local cx=math.floor((x+84)/.5)*.5-84+.25
    local cz=math.floor((z+84)/.5)*.5-84+.25
    assert(world.columns[cx..':'..cz],'missing collision '..x..','..z)
end
for a=0,359 do
    local rad=math.rad(a)
    local main,inner,outer=T.Edges(rad)
    assert(inner-main>5.0,'chasm too narrow')
    for _,r in ipairs({(main+inner)/2,outer+1,84,100}) do
        local x,z=r*math.cos(rad),r*math.sin(rad)
        assert(not T.HasGround(x,z) and T.Height(x,z)==T.VOID_Y)
        assert(T.CollideHeight(x,z)==T.VOID_Y and T.GroundHeight(x,z)==nil)
        assert(T.GrassAt(x,z)==0)
    end
    support(51*math.cos(rad),51*math.sin(rad))
end
for x=-4,4,.5 do support(x,-38.25); support(x,-49.75); support(x,-64) end
for x=-12,12,.5 do for z=53,68,.5 do support(x,z) end end
for x=-38.5,-33.5,.5 do for z=-8.5,-3.5,.5 do support(x,z) end end
for i=0,3 do
    local a=math.pi/4+i*math.pi/2
    for t=0,359 do
        support(51*math.cos(a)+3.7*math.cos(math.rad(t)),51*math.sin(a)+3.7*math.sin(math.rad(t)))
    end
end
print('PASS routes: spawn / both bridgeheads / wall ring / north hall / west tower supported')
assert(T.IsSafeGround(0,6.1,-64)); assert(T.IsSafeGround(0,6,-52))
assert(not T.IsSafeGround(0,6,-44)); assert(not T.IsSafeGround(0,6,-39))
assert(not T.IsSafeGround(-36,11,-6)); assert(not T.IsSafeGround(0,6,-49.25))
print('PASS safety: spawn accepted; void / cliff / tower-top / fragments excluded')
-- 比较旧版实际分块分配量，使用同一个离线世界接口但不约束旧碰撞必须在新岛内。
local old=assert(loadfile('validation/island-void/terrain-before.lua'))()
local oldCollision
for i=1,20 do local name,value=debug.getupvalue(old.Build,i); if name=='BuildCollision' then oldCollision=value end end
local oldWorld={cells=0,chunks=0}
function oldWorld:CreateVolume(nx,ny,nz)
    self.cells=self.cells+nx*ny*nz; self.chunks=self.chunks+1
    return {GetGrid=function() return {FillBox=noop,PaintBox=noop} end,RebuildGeometry=noop}
end
oldWorld.FinalizeVolume=noop
oldCollision(oldWorld)
assert(T.collisionStats.allocated<=oldWorld.cells*1.2,'collision allocation regression')
assert(T.meshStats.triangles<=2*336*336,'shell triangle regression')
print('COST old allocated='..oldWorld.cells..' old chunks='..oldWorld.chunks..' ratio='..T.collisionStats.allocated/oldWorld.cells)

-- 角色真实模块 + 轻量引擎 mock：不运行引擎物理。
Quaternion=setmetatable({},{__call=function() return setmetatable({},{__mul=function(_,v) return v end}) end})
package.loaded['urhox-libs.Camera.ThirdPersonCamera']={}
package.loaded['game.BlockCharacter']={SLENDER={widen=Vector3(1,1,1)},CreateVoxel=function() return {bones={arm_right={CreateChild=function() return {} end}},Update=noop} end}
package.loaded['game.NomiVoxelData']={unit=.05}
package.loaded['ruins.TimeObject']={}
local cn={position=Vector3.ZERO}
ThirdPersonCamera={Create=function() return {SetMode=noop,Update=function(_,dt,target) cn.position=target.position+Vector3(0,2,-4) end,GetNode=function() return cn end} end}
local actorScene={CreateChild=function(_,name)
    local node={}
    node.CreateComponent=function()
        local cc={onGround=false,desiredVelocity=Vector3.ZERO}
        function cc:SetLinearVelocity(v) self.actual=v end
        function cc:Teleport(v) node.worldPosition=v end
        return cc
    end
    return node
end}
local actorWorld={RaycastSingle=function() return {hit=false} end}
local N=require('ruins.NomiController')
local actor=N.New(actorScene,actorWorld,Vector3(0,6.1,-64),0)
local restored=0; actor.onVoidReturn=function() restored=restored+1 end
actor.node.worldPosition=Vector3(0,-6,-44)
assert(actor:UpdateSafety(.016) and restored==1)
assert(actor:Position().z==-64 and actor.cc.actual:Length()==0)
assert(actor.camTarget.position.z==-64 and cn.position.z==-68)
actor.cc.onGround=true; actor.node.worldPosition=Vector3(0,6,-52)
actor:UpdateSafety(.41); assert(actor.safePos.z==-52)
actor.node.worldPosition=Vector3(0,6,-49.1); actor:UpdateSafety(3)
assert(actor.safePos.z==-52,'cliff overwrote checkpoint')
actor.node.worldPosition=Vector3(0,3,-44); assert(actor:UpdateSafety(3))
assert(actor.safePos.z==-52,'floating fragment overwrote checkpoint')
actor.node.worldPosition=Vector3(0,-6,-44); assert(actor:UpdateSafety(.02)); assert(actor:Position().z==-52)
actor.safePos=Vector3(0,6,-44); actor.node.worldPosition=Vector3(0,-30,-44)
assert(actor:UpdateSafety(.02) and actor:Position().z==-64,'invalid safe point did not use spawn')
print('PASS recovery: initial fallback / latest safe point / invalid checkpoint / velocity + camera snap')

local function Read(p) local f=assert(io.open(p));local s=f:read('*a');f:close();return s end
local puzzle=Read('scripts/ruins/RuinsPuzzles.lua')
local start=assert(puzzle:find('o.startScatter = function',1,true))
local finish=assert(puzzle:find('\n    local obj = Add',start,true))
local fn=puzzle:sub(start+#'o.startScatter = ',finish-1)
local scatter=assert(load('local shardIndex=0; return '..fn,'bridgeScatter','t',setmetatable({Terrain=T},{__index=_G})))()
local rng=require('ruins.Noise').Rng(11)
local outer,inner,anchors=0,0,0
for z=-49,-39,.5 do
    for nx=1,16,3 do
        local piece={restPos=Vector3(-2,4,z),nx=nx,ny=10,nz=12}
        local pos=scatter({size=.25},piece,rng)
        local center=pos+Vector3(nx*.125,1.25,1.5)
        if center.y>9 then anchors=anchors+1 else assert(center.y+Vector3(nx*.125,1.25,1.5):Length()<=3.31,'slabs create walking surface') end
        local bank=center.z<-44 and Vector3(0,7.65,-50.5) or Vector3(0,7.65,-37)
        assert((center-bank):Length()<15,'outside practical aiming distance')
        -- 直线到残块中心在越过岛唇时仍高于岛面，之后才向下俯射。
        local lip=center.z<-44 and -49 or -39.25
        local f=(lip-bank.z)/(center.z-bank.z)
        if center.y>9 then assert(bank.y+(center.y-bank.y)*f>6.05,'bank occludes rune anchor') end
        if center.z<-44 then outer=outer+1 else inner=inner+1 end
    end
end
assert(outer>0 and inner>0 and anchors==2)
print('PASS scatter: two high rune anchors reachable from both banks <15m; low shards cannot jump to shore (actual shards need Web)')

-- Scene 安全回调执行，确认不改变谜题进度，清除输入/充能/stream。
local source=Read('scripts/ruins/RuinsScene.lua')
local a=assert(source:find('nomi_.onVoidReturn=function(pos)',1,true))
local b=assert(source:find('\n\n    sleepBase.valid',a,true))
local callback=source:sub(a+#'nomi_.onVoidReturn=',b-1)
local harness='local TouchControls,caster_,drag,M=...; local voidInputBlocked=false; local f='..callback..'; return function(p) f(p); return voidInputBlocked end'
local cleaned,stopped=false,false
local caster={charging=true,charge=.9,Say=noop}
local host={ride={pos=Vector3.ZERO},stream={Stop=function(_,cancel) stopped=cancel end},progress=17}
local returned=assert(load(harness))( {Cancel=function() cleaned=true end},caster,{buttons=1},host)
assert(returned(Vector3(0,6,-52)) and cleaned and stopped and not caster.charging and caster.charge==0 and host.progress==17)
-- 骑龙/过渡在任何 Move/UpdateSafety 之前 early return，明确为代码路径验证。
local sceneUpdate=source:match('function Ruins_HandleSceneUpdate(.-)function Ruins_HandleUpdate')
assert(sceneUpdate:find('M.mounted or (M.ride ~= nil and M.ride.mode ~= "free") then return end',1,true))
print('PASS Scene cancellation callback; mounted/transition safety bypass (static path, not flight runtime)')

-- Dragon 地面查询无命中保持高度参考，不把参考面当落地证据。
local controller=Read('scripts/dragon/DragonAnimationController.lua')
local ga=assert(controller:find('function C:GroundHeight(x, z)',1,true))
local gb=assert(controller:find('\n-- ---------------------------------------------------------------- 姿态片段',ga,true))
local ground=assert(load('local C={}; '..controller:sub(ga,gb-1)..'; return C.GroundHeight'))()
local c={queryGround=function() return nil end,airFloor=6,groundRef=30}
assert(ground(c,0,-44)==6,'void increases flight floor')
local da=assert(controller:find('STATES.LAND = {',1,true))
local db=assert(controller:find('    pose = function',da,true))
local land=controller:sub(da,db-1)..'\n}\nreturn STATES.LAND'
local states=assert(load('local STATES={}; '..land))()
local flyer={loco={pos=Vector3(0,0,-44),airborne=true},canLand=function() return false end,SetState=function(self,s) self.state=s end}
states.logic(flyer,.016,1)
assert(flyer.state=='FLY' and flyer.loco.airborne)
print('PASS dragon: missing ground holds flight reference; LAND over void returns to FLY')
-- 执行真实桥面体素公式与真实分块算法，验证修复面连续和符脉残片配置。
local pa=assert(puzzle:find('local BRIDGE_D',1,true))
local pb=assert(puzzle:find('\nlocal function BuildBridge',pa,true))
local shapes={}
local brush={New=function(_,bounds)
    local b={bounds=bounds}
    function b:Shape(x0,y0,z0,x1,y1,z1,fn) shapes[#shapes+1]={x0,y0,z0,x1,y1,z1,fn=fn} end
    return b
end}
local palette=setmetatable({},{__index=function(_,k) return k end})
local env=setmetatable({Terrain=T,Brush=brush,P=palette,abs=math.abs,min=math.min,max=math.max,floor=math.floor,Hash3=require('ruins.Noise').Hash3,Build={DETAIL={column=.125},Marble=function() return 'MARBLE' end},Harvest=function(_,b) return b end},{__index=_G})
local bridgeBuild=assert(load(puzzle:sub(pa,pb-1)..'; return BridgeVoxels','bridgeShape','t',env))()
local bridge=bridgeBuild({})
local function MaterialAt(x,y,z)
    local m
    for _,sh in ipairs(shapes) do
        if x>=sh[1] and y>=sh[2] and z>=sh[3] and x<=sh[4] and y<=sh[5] and z<=sh[6] then
            m=sh.fn(x,y,z) or m
        end
    end
    return m
end
local vox={}
local bs=bridge.bounds.size
local origin=Vector3(table.unpack(bridge.bounds.min))
local dims={}
for i=1,3 do dims[i]=math.floor((bridge.bounds.max[i]-bridge.bounds.min[i])/bs+.5) end
for i=0,dims[1]-1 do for j=0,dims[2]-1 do for k=0,dims[3]-1 do
    local m=MaterialAt(origin.x+(i+.5)*bs,origin.y+(j+.5)*bs,origin.z+(k+.5)*bs)
    if m then vox[#vox+1]={i,j,k,m} end
end end end
local previous=6
for z=-49.6875,-38.3125,bs do
    local edge=math.min(z+49.75,-38.25-z)
    local height=edge<.5 and 6.125 or 6.25
    assert(math.abs(height-previous)<=.125,'new bridge entry too high'); previous=height
    for x=-1.5,1.5,bs do
        assert(MaterialAt(x,height-bs*.5,z),'hole in new bridge walkway')
        assert(not MaterialAt(x,height+bs*.5,z),'blocked walkway')
    end
end
assert(math.abs(previous-6)<=.125)
assert(T.HeightAt(0,-49.75)==6 and T.HeightAt(0,-38.25)==6)
local realTO=assert(loadfile('scripts/ruins/TimeObject.lua'))()
local methods
for i=1,30 do local key,v=debug.getupvalue(realTO.New,i); if key=='T' then methods=v end end
assert(methods)
local obj=setmetatable({seed=11,time=0,voxels=vox,dims=dims,size=bs,origin=origin,rot=Quaternion()}, {__index=methods})
local assignments,groups=obj:Partition(2,{dims[1]*.5,dims[2]*.5,dims[3]*.5})
local comps=obj:Components(assignments,groups)
scatter=assert(load('local shardIndex=0; return '..fn,'bridgeScatterActual','t',setmetatable({Terrain=T},{__index=_G})))()
rng=require('ruins.Noise').Rng(11*131+#comps)
local conserved=0
for i,ids in ipairs(comps) do
    local p=obj:MakePiece(ids,nil)
    local pos=scatter(obj,p,rng)
    local half=Vector3(p.nx*bs*.5,p.ny*bs*.5,p.nz*bs*.5)
    local center=pos+half
    if i<=2 then
        assert(center.y-half:Length()>=9.49,'rune anchor reachable by jumping')
        local bank=i==1 and Vector3(0,7.65,-50.5) or Vector3(0,7.65,-37)
        assert((center-bank):Length()<15,'new fine shard anchor too far')
        local lip=i==1 and -49 or -39.25
        local t=(lip-bank.z)/(center.z-bank.z)
        assert(bank.y+(center.y-bank.y)*t>6.05,'fine shard anchor occluded by lip')
    else assert(center.y+half:Length()<=3.31,'rubble above safe limit') end
    conserved=conserved+#ids
end
assert(conserved==#vox and #comps>=2)
print('PASS real bridge formula: continuous 3m walkway, .125 entry / .25 deck preserved; '..#vox..' voxels conserved across '..#comps..' shards')

-- 执行远端 StairGeometryTest 原版 Structure，明确不调用 Actual/物理步进。
local detail=assert(load('return '..Read('scripts/ruins/RuinsBuild.lua'):match('M.DETAIL = (%b{})')))()
package.loaded['ruins.RuinsBuild']={DETAIL=detail}
local stairTest=Read('scripts/ruins/tests/StairGeometryTest.lua')
local stop=assert(stairTest:find('---@param volume VoxelVolume',1,true))
assert(load(stairTest:sub(1,stop-1)..'\nStructure()','remoteStairStructure'))()
-- 实际阶梯形状采样：永久地形只到-1，踏面/扶墙由两个可见Volume独占。
local build=Read('scripts/ruins/RuinsBuild.lua')
local a=assert(build:find('local function BuildStairs(world)',1,true))
local b=assert(build:find('-- ---------------------------------------------------------------- 外城墙',a,true))
local stairBrush={New=function(_,bounds)
    local obj={bounds=bounds}
    function obj:Shape(x0,y0,z0,x1,y1,z1,fn) self.shape=fn end
    function obj:Finish() return self end
    return obj
end}
local st={}
local e=setmetatable({Terrain=T,Brush=stairBrush,M=st,Keep=function(v) return v end,abs=math.abs,min=math.min,max=math.max,
    floor=math.floor,Hash3=require('ruins.Noise').Hash3,P=palette,Marble=function() return 1 end,Stone=function() return 1 end},{__index=_G})
assert(load(build:sub(a,b-1)..'; BuildStairs({})','stairShapes','t',e))()
assert(#st.stairVolumes==2)
for i,sign in ipairs({-1,1}) do
    local sh=st.stairVolumes[i].shape
    for _,d in ipairs({20.375,20.875,21.875,31.875,32.875,33.375}) do
        for _,x in ipairs({-3.125,.125,3.125}) do
            local top=T.StairY(sign*d)
            assert(sh(x,top-.125,sign*d) and not sh(x,top+.125,sign*d))
            assert(T.CollideHeight(x,sign*d)<=-1 and not T.IsSafeGround(x,top,sign*d))
        end
    end
end
print('PASS remote stairs: original Structure + actual two-volume shape sampling; physics walking UNVERIFIED')
-- 精确瞄准 DDA 模块离线执行：空包围盒不能挡目标，前景实心墙不能被穿透。
function mt.__div(v,s) return v*(1/s) end
local q=setmetatable({},{__mul=function(_,v) return v end}); function q:Inverse() return self end
VoxelRaycastResult={new=function() return {hit=false,distance=0} end}
IntVector3=Vector3
package.loaded['ruins.TimeObject'].FindByVolume=function() return nil end
local solid=true
local grid={GetDimensions=function() return Vector3(8,4,12) end,
 IsSolid=function(_,x,y,z) return solid and z==7 end,GetVoxelMaterial=function() return 1 end}
local node={worldRotation=q,worldScale=Vector3(1,1,1),WorldToLocal=function(_,p) return p-Vector3(299.5,5,298) end}
local volume={voxelSize=.25,volumeId=1,collisionLayer=1,GetNode=function() return node end,
 GetGrid=function() return grid end,GetPaletteDomain=function() return 0 end}
actor.world={RaycastGridSingle=function(_,ray) return {hit=true,distance=0,position=ray.origin,volume=volume,volumeId=1} end,
 GetVolumeCount=function() return 1 end,GetVolume=function() return volume end}
local ray=Ray(Vector3(300.5,5.5,298),Vector3(0,0,1))
local hit=actor:GridHit(ray,10)
assert(hit.hit and math.abs(hit.distance-1.75)<1e-6 and hit.normal.z==-1)
solid=false; assert(not actor:GridHit(ray,10).hit)
solid=true
hit=actor:GridHit(Ray(Vector3(300.4,5.5,298),Vector3(.01,0,1):Normalized()),10)
assert(hit.hit and hit.normal.z==-1)
print('PASS remote aim GridHit/TraceVolume: empty-origin repair, real wall, empty grid, angled ray (mock Grid; engine queries UNVERIFIED)')
