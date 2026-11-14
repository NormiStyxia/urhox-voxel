return function(scene,dn)
 local Clouds=require("ruins.SkyClouds")
 local resource,make=cache.GetResource,Material.new
 for _,mode in ipairs({"normal","missing","wrong_size","binding","shader"})do
  local lookups=0
  cache.GetResource=function(s,k,p)
   lookups=lookups+1
   assert(not p:find("density") and not p:find("occupancy"),"old runtime dependency")
   if mode=="missing" and p:find("sculpted") then return nil end
   local r=resource(s,k,p)
   if mode=="wrong_size" and p:find("sculpted") then r.width=1 end
   return r
  end
  Material.new=function(...)
   local m=make(...)
   if mode=="shader" then m.SetSurfaceShader=function()return false end end
   if mode=="binding" then m.SetSurfaceTexture=function()return false end end
   return m
  end
  local c=Clouds.New(scene,24,true,true)
  if mode=="normal" then
   assert(c.ready and c.triangleCount==194 and c.batchCount==1 and not c.baking)
   local initial=lookups
   for i=1,600 do c:Update(1/60,1,0,dn);c:StepBake();c:Follow(Vector3(0,i*50,0))end
   assert(c.root.position.y==30000 and c.geometry[1].commits==1 and lookups==initial)
   c:Update(0/0,0/0,math.huge,dn)
   assert(c.material.params.day==1 and c.material.params.dusk==0)
  else
   assert(c.unavailable and not c.ready and not c.root and not c.material and not c.texture)
   local initial=lookups
   for i=1,600 do c:Update(.2,1,0,dn);c:Follow(Vector3.ZERO)end
   assert(lookups==initial and c.elapsed==0,"failed resources must remain hidden without retry")
  end
  c:Dispose();c:Dispose();assert(not c.texture and not c.scene and not c.ready)
  Material.new=make
 end
 cache.GetResource=resource
 local paths={}
 cache.GetResource=function(s,k,p)paths[p]=true;return resource(s,k,p)end
 local low=Clouds.New(scene,4,true,true)
 assert(low.ready and low.triangleCount==34 and low.count==4)
 assert(paths["Textures/Sky/cloud_sculpted_atlas_low.png"] and not paths["Textures/Sky/cloud_sculpted_atlas.png"])
 low:Dispose()
 local calls=0;cache.GetResource=function(...)calls=calls+1;return resource(...)end
 local off=Clouds.New(scene,0,false,false)
 for i=1,600 do off:Update(.2,1,0,dn);off:Follow(Vector3.ZERO)end
 assert(calls==0 and off.elapsed==0 and not off.root)
 off:Dispose();cache.GetResource=resource
 print("PASS celestial lifecycle: 194/98/34 triangles, low small atlas only, no volume dependency, failure hidden/no retry, 600 off frames zero work, height 30000 without upload")
end
