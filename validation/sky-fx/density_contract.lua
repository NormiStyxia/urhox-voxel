return function(scene,dn)
 local Clouds=require('ruins.SkyClouds')
 local original=cache.GetResource
 for _,mode in ipairs({'normal','missing_occupancy','missing','wrong_size','binding','shader'})do
  local calls=0
  cache.GetResource=function(s,k,p)
   calls=calls+1
   if mode=='missing' and p=='Textures/Sky/cloud_density.png' then return nil end
   if mode=='missing_occupancy' and p=='Textures/Sky/cloud_occupancy.png' then return nil end
   if mode=='shader' and k=='Material' then return nil end
   local result=original(s,k,p)
   if mode=='wrong_size' and p=='Textures/Sky/cloud_density.png' then result.width=1 end
   return result
  end
  local make=Material.new
  Material.new=function(...)
   local m=make(...)
   if mode=='binding' then m.SetSurfaceTexture=function()return false end end
   if mode=='shader' then m.SetSurfaceShader=function()return false end end
   return m
  end
  local c=Clouds.New(scene,24,true,true)
  if mode=='shader' then assert(c.unavailable and not c.root and not c.material)
  else
   assert(c.ready and not c.baking and c.bakeSlices==0 and not c.job)
   assert(c.batchCount==1 and c.triangleCount==1 and c.viewSteps==64 and c.lightSteps==1 and c.traversalSteps==96)
   local hasDensity=mode=='normal' or mode=='missing_occupancy'
   assert(c.fallback==not hasDensity)
   assert(c.material.params.use_volume==(hasDensity and 1 or 0))
   assert(c.material.params.use_occupancy==(mode=='normal' and 1 or 0))
   assert(c.material.params.diagnostic==0)
   local initial=calls
   for i=1,600 do c:Update(1/60,1,0,dn);c:StepBake() end
   assert(calls==initial and c.geometry[1].commits==1,'no per-frame resource lookup/upload')
   c:Update(0/0,0/0,math.huge,dn)
   assert(c.material.params.day==1 and c.material.params.dusk==0)
   assert(c.elapsed==c.elapsed and c.elapsed<3600)
  end
  c:Dispose();c:Dispose()
  assert(not c.texture and not c.occupancy and not c.scene and not c.ready)
  if c.material then assert(c.material.disposed and c.root.disposed) end
  Material.new=make
 end
 cache.GetResource=original
 local paths={}
 cache.GetResource=function(s,k,p)paths[p]=true;return original(s,k,p)end
 local low=Clouds.New(scene,4,true,false)
 assert(low.ready and low.viewSteps==16 and low.material.params.use_occupancy==0)
 assert(paths['Textures/Sky/cloud_density_low.png'] and not paths['Textures/Sky/cloud_density.png'] and not paths['Textures/Sky/cloud_occupancy.png'])
 assert(low.texture.width==2048 and low.texture.height==256)
 low:Dispose();cache.GetResource=original
 print('PASS first low tier loads only 1.5MiB RGB density, no large density or occupancy lookup; missing occupancy retains safe fixed integration')
 local c=Clouds.New(scene,0,false,false)
 local ticks=c.elapsed
 for i=1,600 do c:Update(.2,1,0,dn);c:StepBake() end
 assert(c.elapsed==ticks and not c.root and not c.material)
 print('PASS density lifecycle: immediate readiness; 1 commit; missing/binding analytic volume fallback; shader fail transparent; finite parameters; 600 disabled frames zero work')
end
