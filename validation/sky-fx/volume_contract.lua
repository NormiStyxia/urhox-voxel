-- Pure offline contract. Called with engine mocks from check.lua, never a Runtime entry.
return function(scene,dn,finish)
 local Clouds=require('ruins.SkyClouds')
 local resource=cache.GetResource
 local lookups=0
 cache.GetResource=function(s,k,p)lookups=lookups+1;assert(k~='Texture2D','3D sky clouds must not use atlas');return resource(s,k,p)end
 local c=Clouds.New(scene,24,true,true)
 assert(c.baking and not c.ready and not c.root.enabled and c.shapeCount==0 and next(c.geometry)==nil)
 local start=os.clock()
 local peak,frames,oldVertices,oldCommits=0,0,0,0
 while c.baking do
  assert(not c.root.enabled,'partial cloud upload exposed')
  local t=os.clock();c:StepBake();peak=math.max(peak,os.clock()-t);frames=frames+1
  local vertices,commits=0,0
  for _,g in pairs(c.geometry)do vertices=vertices+#g.verts;commits=commits+(g.commits or 0)end
  assert(vertices-oldVertices<=240,'unbounded per-frame upload')
  assert(commits-oldCommits<=1,'multiple commits in one slice')
  oldVertices,oldCommits=vertices,commits
  assert(frames<1500,'bake stalled')
 end
 assert(c.ready and c.root.enabled and frames>1 and c.triangleCount==8800 and c.batchCount==3 and c.count==24)
 print(string.format('PASS amortized high bake: %d slices, %.3fms total / %.3fms peak Lua mock slice (not Web timing)',frames,(os.clock()-start)*1000,peak*1000))
 local function Mesh(shape,flat)
  local vs,ids=shape.vertices,shape.indices
  local edges,balance={},{}
  local volume=0
  for _,v in ipairs(vs)do
   assert(v.x==v.x and v.y==v.y and v.z==v.z)
   assert(math.abs(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz-1)<1e-8)
   -- Concave surfaces need not face away from the origin.
   for _,color in ipairs({v.thickness,v.height,v.ao})do assert(color>=0 and color<=1)end
   assert(v.color and v.farColor)
  end
  for i=1,#ids,3 do
   local ia,ib,ic=ids[i],ids[i+1],ids[i+2]
   local a,b,d=vs[ia],vs[ib],vs[ic]
   local ux,uy,uz=b.x-a.x,b.y-a.y,b.z-a.z
   local vx,vy,vz=d.x-a.x,d.y-a.y,d.z-a.z
   local nx,ny,nz=uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx
   assert(nx*nx+ny*ny+nz*nz>1e-14,'degenerate face')
   assert(nx*(a.nx+b.nx+d.nx)+ny*(a.ny+b.ny+d.ny)+nz*(a.nz+b.nz+d.nz)>0,'inward face/gradient')
   volume=volume+(nx*a.x+ny*a.y+nz*a.z)/6
   for _,pair in ipairs({{ia,ib},{ib,ic},{ic,ia}})do
    local lo,hi=math.min(pair[1],pair[2]),math.max(pair[1],pair[2])
    local key=lo..':'..hi
    edges[key]=(edges[key] or 0)+1
    balance[key]=(balance[key] or 0)+(pair[1]==lo and 1 or -1)
   end
  end
  local e=0;for k,n in pairs(edges)do assert(n==2 and balance[k]==0,'nonmanifold/open edge');e=e+1 end
  assert(#vs-e+#ids/3==2 and volume>0,'not a closed genus-zero solid')
 end
 local fingerprints={}
 local bounds={}
 for index,shape in pairs(c.shapes)do
  if index<=6 then assert(#shape.indices/3>=800 and #shape.indices/3<=1200)
  else assert(#shape.indices/3==(index<=12 and 96 or 120)) end
  Mesh(shape,true)
  if index<=6 then
   assert(shape.lobeCount>=5 and shape.lobeCount<=10 and shape.name)
   local loX,hiX,loY,hiY=100,-100,100,-100
   local values={}
   for _,v in ipairs(shape.vertices)do
    values[#values+1]=string.format('%.5f,%.5f,%.5f',v.x,v.y,v.z)
    loX,hiX,loY,hiY=math.min(loX,v.x),math.max(hiX,v.x),math.min(loY,v.y),math.max(hiY,v.y)
   end
   bounds[index]={width=hiX-loX,height=hiY-loY}
   local key=table.concat(values,';');assert(not fingerprints[key],'duplicate cloud variant');fingerprints[key]=true
  end
 end
 assert(bounds[1].height/bounds[1].width>1.2,'tower collapsed to a bun')
 assert(bounds[2].width/bounds[2].height>3,'bank not long enough')
 assert(bounds[5].width/bounds[5].height>3,'stratocumulus not low enough')
 assert(bounds[6].width<bounds[2].width*.6,'fragments must be distinctly smaller')
 for _,g in pairs(c.geometry)do
  for _,v in ipairs(g.verts)do
   local n=v.normal;assert(math.abs(n.x*n.x+n.y*n.y+n.z*n.z-1)<1e-8)
   for _,value in pairs(v.color)do assert(value>=0 and value<=1)end
  end
 end
 local emitted=oldVertices
 -- Match native Vector3 property copy semantics (the general fixture uses Lua tables).
 for _,n in pairs(c.layers)do
  n.position=nil
  setmetatable(n,{__newindex=function(o,k,value)
   if k=='position' then rawset(o,'copiedPosition',{x=value.x,y=value.y,z=value.z}) else rawset(o,k,value)end
  end,__index=function(o,k)if k=='position' then return rawget(o,'copiedPosition')end end})
 end
 for i=1,600 do c:Update(1/60,.8,.1,dn);c:StepBake()end
 local unchanged=0;for _,g in pairs(c.geometry)do unchanged=unchanged+#g.verts;assert(g.commits==1)end
 assert(unchanged==emitted and c.bakeSlices==frames and c.layers[1].position.x~=c.layers[2].position.x)
 c:Dispose();c:Dispose();assert(c.root.disposed and c.material.disposed and not c.job and next(c.shapes)==nil)
 print('PASS 18 cached LOD shapes: watertight edges/Euler=2/positive volume/outward normals/colors; 600 ready frames no vertex or commit changes')
 local mid=finish(Clouds.New(scene,12,true,true));assert(mid.triangleCount==3920 and mid.batchCount==3);for _,shape in pairs(mid.shapes)do Mesh(shape,true)end
 local low=finish(Clouds.New(scene,4,true,false));assert(low.horizonOnly and low.triangleCount==384 and low.batchCount==1 and low.shapeCount==2 and not low.shapes[1])
 print(string.format('PASS medium %d slices / low %d slices, low has only two envelope shapes and one horizon batch',mid.bakeSlices,low.bakeSlices))
 mid:Dispose();low:Dispose()
 local zero=Clouds.New(scene,0,true,true)
 local off=Clouds.New(scene,24,false,false)
 local before=lookups
 for i=1,600 do zero:Update(1/60,1,0);zero:StepBake();off:Update(1/60,1,0);off:StepBake()end
 assert(lookups==before and zero.bakeSlices==0 and off.bakeSlices==0 and not zero.root and not off.root)
 zero:Dispose();off:Dispose()
 local pending=Clouds.New(scene,24,true,true);pending:StepBake();pending:Dispose()
 local sliced=pending.bakeSlices
 for i=1,600 do pending:StepBake()end
 assert(pending.bakeSlices==sliced and not pending.job and pending.root.disposed)
 cache.GetResource=resource

 local f=Clouds.New(scene,24,true,true)
 for i=1,400 do f:StepBake();if next(f.geometry) then break end end
 local abandoned=f.root
 f.job=coroutine.create(function()error('injected bake failure')end)
 local oldPrint,oldFormat=print,string.format
 print=function()error('disabled bake log printed')end
 string.format=function()error('disabled bake log formatted')end
 f:StepBake();assert(abandoned.disposed and f.fallback and not f.root.enabled)
 finish(f)
 assert(f.count==6 and f.triangleCount==288 and f.shapeCount==1)
 Mesh(f.shapes[1],false)
 f:Dispose()
 local fatal=Clouds.New(scene,12,true,true)
 fatal.job=coroutine.create(function()error('first failure')end);fatal:StepBake()
 local doomed=fatal.root
 fatal.job=coroutine.create(function()error('fallback failure')end);fatal:StepBake()
 assert(not fatal.baking and fatal.unavailable and doomed.disposed and not fatal.root and not fatal.job and not fatal.material)
 fatal:Dispose()
 print,string.format=oldPrint,oldFormat
 print('PASS medium<4k; zero/off/cancelled 600 frames no work; failed partial bake disposed then six sphere fallback; second failure safely hidden, logs gated')

 local constructor=Material.new
 cache.GetResource=function(s,k,p)if p=='Materials/RuinsCloud.xml' then return nil end;return resource(s,k,p)end
 local fromXML=finish(Clouds.New(scene,12,true,true));assert(not fromXML.shaderFallback);fromXML:Dispose()
 Material.new=function()local m=constructor();m.SetSurfaceShader=function()return false end;return m end
 local basic=finish(Clouds.New(scene,12,true,true));assert(basic.shaderFallback and basic.count==6 and basic.triangleCount==288)
 basic:Update(.2,.2,0,dn);assert(basic.material.params.MatDiffColor.r<1);basic:Dispose()
 Material.new=constructor;cache.GetResource=resource
 print('PASS missing XML recovers SurfaceShader; missing shader uses documented PBRNoTexture + shaded sphere fallback')
end
