package.path='scripts/?.lua;'..package.path
local vm={}
function vm:Normalized() local n=math.sqrt(self.x*self.x+self.y*self.y+self.z*self.z);return Vector3(self.x/n,self.y/n,self.z/n) end
Vector3=setmetatable({},{__call=function(_,x,y,z)return setmetatable({x=x or 0,y=y or 0,z=z or 0},{__index=vm})end})
Vector3.ZERO=Vector3(0,0,0);Vector3.UP=Vector3(0,1,0)
function Vector2(x,y)return{x=x,y=y}end
local cm={}
function cm:Lerp(b,t)return Color(self.r+(b.r-self.r)*t,self.g+(b.g-self.g)*t,self.b+(b.b-self.b)*t)end
function Color(r,g,b,a)return setmetatable({r=r,g=g,b=b,a=a or 1},{__index=cm})end
function Quaternion(angle,axis)return{angle=angle,axis=axis}end
function Variant(v)return v end
function CascadeParameters(...)return{...}end
TRIANGLE_LIST=1;TU_DIFFUSE=2;EMITTER_BOX=3;VOLUMETRIC_FOG_QUALITY_LOW=4
BLOOM_MODE_UE=5;BLOOM_MODE_LEGACY=6;TONEMAP_MODE_ACES=7;SKY_CAPTURE_MANUAL=8
local web,mobile,compute=false,false,true
local function dispose(s) s.disposed=true; if s.children then for _,c in ipairs(s.children)do dispose(c)end end end
function GetPlatform() return mobile and 'Android' or (web and 'Web' or 'Windows') end
input={numTouches=0,focus=true,minimized=false}
package.loaded['urhox-libs.Platform.PlatformUtils']={IsWebPlatform=function()return web end,IsMobilePlatform=function()return mobile end}
graphics={GetComputeShaderSupport=function()return compute end}
renderer={SetVolumetricFogFroxelEnabled=function(self,v)self.froxel=v end,SetVolumetricFogQuality=function(self,v)self.fogQuality=v end}
Material={new=function()return{Dispose=dispose,params={},SetShaderParameter=function(s,k,v)s.params[k]=v end,SetTechnique=function()end,SetTexture=function()end,SetSurfaceShader=function()return true end,SetSurfaceTexture=function(s,k,v)s.textureBinds=(s.textureBinds or 0)+1;s.textureName=k;return true end,Clone=function()return Material:new()end}end}
cache={GetResource=function(_,kind,path)local r=Material:new();if path=='Textures/Sky/cloud_sculpted_atlas.png' then r.width,r.height=2048,1024 elseif path=='Textures/Sky/cloud_sculpted_atlas_low.png' then r.width,r.height=1024,512 end;return r end}
function cache:GetResourceAsync(kind,path,callback) callback(self:GetResource(kind,path)) end
Image=function()return{Dispose=dispose,SetSize=function()end,SetPixel=function()end}end
Texture2D={new=function()return{Dispose=dispose,SetData=function()end}end}
ParticleEffect={new=function()return{Dispose=dispose,frames={},SetNumColorFrames=function()end,AddColorTime=function(s,c,t)table.insert(s.frames,{color=c,time=t})end}end}
local function geometry()
 return {verts={},inView=true,BeginGeometry=function()end,DefineVertex=function(s,v)table.insert(s.verts,{x=v.x,y=v.y,z=v.z})end,
 DefineNormal=function(s,n)s.verts[#s.verts].normal=n end,DefineColor=function(s,c)s.verts[#s.verts].color=c end,DefineTexCoord=function()end,
 Commit=function(s)s.commits=(s.commits or 0)+1 end,SetMaterial=function(s,m)s.material=m end}
end
local receivers={}
local function scriptObject()
 local r={events={}}
 function r:SubscribeToEvent(e,fn) self.events[e]=fn end
 function r:UnsubscribeFromAllEvents() self.events={} end
 receivers[#receivers+1]=r; return r
end
local function tick(dt,n)
 local data={GetFloat=function()return dt end}
 for i=1,n do
  local pending={}
  for _,r in ipairs(receivers)do if r.events.Update then pending[#pending+1]={r,r.events.Update} end end
  for _,pair in ipairs(pending)do pair[2](pair[1],nil,data)end
 end
end
local function node(name)
 return {Dispose=dispose,Remove=dispose,CreateScriptObject=scriptObject,name=name,children={},enabled=true,position=Vector3.ZERO,
 CreateChild=function(s,n)local c=node(n);table.insert(s.children,c);return c end,
 CreateComponent=function(s,k)
  if k=='CustomGeometry' then return geometry() end
  if k=='ParticleEmitter' then return{removed=0,RemoveAllParticles=function(e)e.removed=e.removed+1 end,ApplyEffect=function()end}end
  if k=='SkyLightCapture' then return{supported=true,capturing=false,requests=0,RequestCapture=function(c)c.requests=c.requests+1 end}end
  return{}
 end}
end

Node=function()return node('Standalone')end
local function FinishCloud(c)
 for i=1,1500 do if not c.baking then break end;c:StepBake()end
 assert(c.ready and not c.baking,'cloud bake did not finish')
 return c
end
local settings=require('ruins.GameSettings')
local registrations,executions={},{}
local originalRegister=settings.RegisterQuality
settings.RegisterQuality=function(name,fn)
 if not fn then return originalRegister(name,nil) end
 registrations[#registrations+1]=name
 return originalRegister(name,function(profile)executions[#executions+1]=name;return fn(profile)end)
end

local order={}
local registerQuality=settings.RegisterQuality
settings.RegisterQuality=function(name,fn)
 if not fn then return registerQuality(name,nil) end
 return registerQuality(name,function(p) order[#order+1]=name; return fn(p) end)
end
local logger=require('ruins.DebugLog')
local probes={}
local registerProbe=logger.RegisterProbe
logger.RegisterProbe=function(k,f)probes[k]=f;registerProbe(k,f)end
local scene=node('Scene')
local dn=require('ruins.DayNight').New({scene=scene,zone={},sun={SetAttribute=function()end},sunNode=node('Sun'),zoneNode=node('Env'),hour=12})
local Quality=require('ruins.LightQuality')
local standaloneCalls,configureCalls=0,0
local standaloneApply,configure=Quality.ApplyStandaloneScene,Quality.ConfigureScene
Quality.ApplyStandaloneScene=function(...)standaloneCalls=standaloneCalls+1;return standaloneApply(...)end
Quality.ConfigureScene=function(...)configureCalls=configureCalls+1;return configure(...)end
local Atmos=require('ruins.SkyAtmosphere')
settings.Load();settings.Set('quality','low');settings.Set('clouds',false)
local atmosphere=Atmos.New(scene,dn)
assert(not atmosphere.active and not atmosphere.clouds and not atmosphere.shafts and not atmosphere.motes)
assert(not dn.zone.volumetricFogEnabled and not renderer.froxel)
local clock=atmosphere.clock
for i=1,600 do atmosphere:Update(1/60,Vector3(0,6,0),nil)end
assert(atmosphere.clock==clock,'off path must not accumulate/update any atmosphere')
print('PASS real GameSettings: explicit clouds off + low creates no resources; 600 off frames no work')
settings.Set('clouds',nil)
settings.Set('quality','high')
assert(atmosphere.clouds.count==24 and atmosphere.shafts.count==8 and atmosphere.motes.count==80)
assert(atmosphere.realFog and dn.zone.volumetricFogViewDistance==90)
local triangles=0
FinishCloud(atmosphere.clouds)
for _,g in pairs(atmosphere.clouds.geometry) do
 triangles=triangles+#g.verts/3
 assert(not g.castShadows)
 for i=1,#g.verts,3 do
  local a,b,c=g.verts[i],g.verts[i+1],g.verts[i+2]
  local ux,uy,uz=b.x-a.x,b.y-a.y,b.z-a.z
  local vx,vy,vz=c.x-a.x,c.y-a.y,c.z-a.z
  local area=(uy*vz-uz*vy)*(a.normal.x+b.normal.x+c.normal.x)+(uz*vx-ux*vz)*(a.normal.y+b.normal.y+c.normal.y)+(ux*vy-uy*vx)*(a.normal.z+b.normal.z+c.normal.z)
  assert(area~=0 or (a.x==b.x and a.x==c.x and a.y==b.y and a.y==c.y and a.z==b.z and a.z==c.z)) -- only two deliberate zero-area bounds triangles
 end
end
assert(triangles==194 and atmosphere.clouds.batchCount==1 and atmosphere.clouds.shapeCount==8)
assert(#atmosphere.shafts.geometry.verts/3==32)
print('PASS high actual geometry: 24 celestial patches / 192 visible + 2 bounds triangles / 1 batch / 8 baked shapes; 8 shafts / 32 triangles; 80 motes')
local oldCloud,oldShaft,oldMote=atmosphere.clouds,atmosphere.shafts,atmosphere.motes
settings.Set('quality','medium')
assert(oldCloud.root.disposed and oldCloud.material.disposed)
assert(oldShaft.node.disposed and oldShaft.material.disposed)
assert(oldMote.node.disposed and oldMote.effect.disposed and oldMote.material.disposed and oldMote.texture.disposed)
assert(atmosphere.clouds.count==12 and atmosphere.shafts.count==3 and atmosphere.motes.count==28)
FinishCloud(atmosphere.clouds)
assert(atmosphere.clouds.triangleCount==atmosphere.clouds.count*8+2 and atmosphere.clouds.batchCount==1)
assert(atmosphere.realFog and dn.zone.volumetricFogViewDistance==60)
print('PASS medium budgets and high instances explicitly disposed, not just hidden')
local ground=Material:new()
atmosphere:Update(.2,Vector3(0,6,0),ground)
assert(ground.params.cloud_shadow_strength==.16)
assert(ground.params.cloud_shadow_use_atlas==1 and ground.textureName=='cloud_shadow_atlas' and ground.textureBinds==1)
local keep=atmosphere.clouds
settings.Apply()
assert(atmosphere.clouds==keep,'unchanged quality must not rebuild clouds')
assert(ground.textureBinds==1,'unchanged profile must not rebind atlas')
oldCloud,oldShaft,oldMote=atmosphere.clouds,atmosphere.shafts,atmosphere.motes
settings.Set('quality','low')
assert(oldCloud.root.disposed and oldShaft.node.disposed and oldMote.texture.disposed)
assert(not atmosphere.shafts and not atmosphere.motes and atmosphere.clouds and atmosphere.clouds.horizonOnly)
FinishCloud(atmosphere.clouds);assert(atmosphere.clouds.triangleCount==atmosphere.clouds.count*8+2 and atmosphere.clouds.batchCount==1)
assert(ground.params.cloud_shadow_strength==0 and not renderer.froxel)
print('PASS low releases detailed clouds/effects, keeps 4 horizon patches, stops shadow/froxel')
for _,platform in ipairs({'desktop','web','mobile','noCompute'})do
 web,mobile,compute=platform=='web',platform=='mobile',platform~='noCompute'
 for _,q in ipairs({'high','medium','low'})do
  settings.Set('quality',q)
  assert(atmosphere.realFog==(q~='low' and platform=='desktop'),platform..q)
 end
end
print('PASS platform matrix: Web/mobile/no-compute never enable real volume, including high overrides')
web,mobile,compute=true,false,true
settings.Set('quality','high')
for _,item in ipairs({{'clouds','clouds'},{'lightShafts','shafts'},{'floatingMotes','motes'}})do
 local previous=atmosphere[item[2]]
 settings.Set(item[1],false)
 assert(atmosphere[item[2]]==nil)
 assert((previous.root or previous.node).disposed)
 settings.Set(item[1],true)
 assert(atmosphere[item[2]]~=nil)
end
settings.Set('volumetric',false);assert(not atmosphere.realFog)
settings.Set('volumetric',true);assert(not atmosphere.realFog,'Web override still safe')
print('PASS individual settings hot-toggle release/recreate; Web full-volume override remains disabled')
for _,pair in ipairs({{'shafts','lightShafts','shafts'},{'motes','floatingMotes','motes'}})do
 atmosphere:SetFeature(pair[1],false); assert(settings.Get(pair[2])==false and atmosphere[pair[3]]==nil)
 atmosphere:SetFeature(pair[1],true); assert(settings.Get(pair[2])==true and atmosphere[pair[3]])
end
atmosphere:SetFeature('volumetric',false);assert(settings.Get('volumetric')==false and not atmosphere.realFog)
atmosphere:SetFeature('volumetric',true);assert(settings.Get('volumetric')==true and not atmosphere.realFog)
local oldUpper=atmosphere.clouds
atmosphere:SetFeature('clouds',false)
assert(oldUpper.root.disposed and atmosphere.clouds==nil and settings.Get('clouds')==false)
atmosphere:SetFeature('lowClouds',false);assert(not atmosphere.clouds)
atmosphere:SetFeature('cloudShadow',false);assert(ground.params.cloud_shadow_strength==0)
atmosphere:SetFeature('clouds',true)
FinishCloud(atmosphere.clouds)
assert(atmosphere.clouds.count==16 and atmosphere.clouds.batchCount==1)
assert(settings.Get('lowClouds')==false and settings.Get('cloudShadow')==false)
atmosphere:SetFeature('lowClouds',true);atmosphere:SetFeature('cloudShadow',true)
assert(atmosphere.clouds.count==24)
local oldScatter={};dn.zone.volumetricFogScatteringColor=oldScatter;dn.sun.volumetricFogIntensity=.123
assert(not dn.zone.volumetricFogEnabled)
dn:SetHour(17)
assert(dn.zone.volumetricFogScatteringColor==oldScatter and dn.sun.volumetricFogIntensity==.123)
print('PASS seven managed feature routes: master cloud / lower cloud / shadow persist in settings; no hidden override')

-- Exercise actual SceneQuality callbacks with only Terrain mocked, since no geometry is needed.
package.loaded['ruins.RuinsTerrain']={}
require('ruins.SceneQuality').Attach({sun=dn.sun,zone=dn.zone,dayNight=dn})
assert(registrations[1]=='skyfx')
for _,name in ipairs({'scene-shadows','scene-postfx','scene-grass','scene-skycapture'})do
 local found=false
 for i,k in ipairs(registrations)do if k==name then assert(i>1);found=true end end
 assert(found,'scene callback missing: '..name)
end
executions={};settings.Apply();assert(executions[1]=='skyfx')
for _,name in ipairs({'scene-shadows','scene-postfx','scene-grass','scene-skycapture'})do
 local found=false
 for i,k in ipairs(executions)do if k==name then assert(i>1);found=true end end
 assert(found)
end
print('PASS real registration/apply order: skyfx before every SceneQuality callback')

settings.Set('shadows','off');settings.Set('postFx','off')
order={}
atmosphere:SetQuality('medium')
assert(settings.Get('quality')=='medium' and atmosphere.quality=='medium')
assert(order[1]=='skyfx' and order[2]=='scene-skycapture' and order[3]=='scene-shadows' and order[4]=='scene-postfx')
assert(not dn.sun.castShadows and dn.zone.bloomWeight==0)
atmosphere:SetFeature('bloom',true);assert(settings.Get('postFx')=='full' and dn.zone.bloomUEIntensity>0)
atmosphere:SetFeature('bloom',false);assert(settings.Get('postFx')=='off' and dn.zone.bloomUEIntensity==0)
for _,key in ipairs({'clouds','lowClouds','cloudShadow','lightShafts','floatingMotes','volumetric','shadows','postFx'})do settings.Set(key,nil)end
atmosphere:SetQuality('auto');assert(settings.Get('quality')=='auto' and atmosphere.quality=='high')
tick(.05,250);assert(atmosphere.quality=='medium' and atmosphere.clouds.count==12)
tick(.05,250);assert(atmosphere.quality=='low' and atmosphere.clouds.horizonOnly)
atmosphere:SetQuality('high');assert(atmosphere.clouds.count==24)
atmosphere:SetQuality('off');assert(settings.Get('quality')=='low' and atmosphere.clouds.horizonOnly)
atmosphere:SetQuality('high')
settings.Set('shadows','off');settings.Set('postFx','off')
print('PASS managed quality high/medium/low/auto/off route, automatic disposal and sky-before-scene callback order')
local mapSize,pcf=renderer.shadowMapSize,renderer.shadowPCFSamples
atmosphere:SetFeature('motes',false);atmosphere:SetFeature('motes',true)
assert(not dn.sun.castShadows and renderer.shadowMapSize==mapSize and renderer.shadowPCFSamples==pcf)
assert(dn.zone.bloomUEIntensity==0 and dn.zone.bloomWeight==0)
settings.Set('quality','medium')
assert(not dn.sun.castShadows and dn.zone.bloomWeight==0)
print('PASS actual SceneQuality integration: atmosphere toggles preserve independent shadows/postfx overrides')
settings.Set('quality','high')
atmosphere:Update(.2,Vector3(0,6,0),ground)
local removed=atmosphere.motes.emitter.removed
atmosphere:Update(.2,Vector3(60,6,0),ground)
assert(atmosphere.motes.emitter.removed==removed+1)
for step=0,288 do
 dn:SetHour(step/12);atmosphere:Update(.2,Vector3(0,6,0),ground)
 assert(dn.sun.brightness>=.16-1e-9 and dn.sun.brightness<=2.2+1e-9)
 assert(dn.zone.fogColor.r==dn.sky.skyHorizonColor.r)
 assert(dn.sky.groundBottomColor.b<=.42+1e-9)
 if dn.elev<=.16 then assert(not atmosphere.shafts.node.enabled)end
end
print('PASS teleport recycles particles; 289 day/night samples preserve ground palette and horizon match')
local probeCalls=0
local oldProbe=atmosphere.Probe
atmosphere.Probe=function(s)probeCalls=probeCalls+1;return oldProbe(s)end
local oldPrint,oldFormat=print,string.format
print=function()error('unexpected debug print while disabled')end
string.format=function()error('unexpected debug formatting while disabled')end
settings.Set('quality','low');settings.Set('quality','high')
for i=1,600 do atmosphere:Update(1/60,Vector3(0,6,0),ground)end
assert(probeCalls==0 and not logger.enabled)
string.format,print=oldFormat,oldPrint
assert(probes.skyfx and probes.skyfx().motesMax==80 and probeCalls==1)
print('PASS disabled logging: no print/format/probe across quality switches and 600 frames; probe opt-in reports counts')
assert(not settings.Set('quality','off'),'off is an advanced toggle, not a global menu tier')
settings.Set('clouds',true)
atmosphere:SetQuality('off')
assert(settings.Get('quality')=='low' and atmosphere.clouds.count==4,'managed off alias preserves explicit menu overrides')
for _,key in ipairs({'clouds','lightShafts','floatingMotes','volumetric'})do settings.Set(key,nil)end
atmosphere:SetQuality('off')
assert(atmosphere.active and atmosphere.clouds.horizonOnly and not atmosphere.shafts and not atmosphere.motes)
FinishCloud(atmosphere.clouds)
local probe=atmosphere:Probe();assert(probe.active and not probe.volume and not probe.cloudShadow and probe.batches==1)
settings.Set('quality','low')
settings.Set('clouds',true);settings.Set('lightShafts',true);settings.Set('floatingMotes',true)
assert(atmosphere.clouds.count==4 and atmosphere.shafts.count==3 and atmosphere.motes.count==28)
settings.Set('clouds',false);settings.Set('lightShafts',false);settings.Set('floatingMotes',false);settings.Set('volumetric',false)
assert(not atmosphere.active and not atmosphere.clouds and not atmosphere.shafts and not atmosphere.motes)
settings.Set('clouds',nil);settings.Set('lightShafts',nil);settings.Set('floatingMotes',nil);settings.Set('volumetric',nil)
settings.Set('quality','high')
print('PASS off controls: advanced menu releases each feature; low explicit-on minimums 4/3/28; managed off aliases low and respects explicit overrides')

oldCloud,oldShaft,oldMote=atmosphere.clouds,atmosphere.shafts,atmosphere.motes
atmosphere:Stop();atmosphere:Stop()
assert(oldCloud.root.disposed and oldShaft.node.disposed and oldMote.texture.disposed)
assert(not probes.skyfx and not atmosphere.active and not atmosphere.scene and not atmosphere.ground)
settings.Set('quality','low');settings.Set('quality','high');assert(not atmosphere.clouds)
atmosphere:SetQuality('medium');atmosphere:SetFeature('clouds',false)
assert(settings.Get('quality')=='high' and settings.Get('clouds')==nil,'stopped APIs must not mutate settings')
settings.Stop()
print('PASS Stop idempotent, unregisters quality/probe, disposed effects never resurrect')
assert(standaloneCalls==0 and configureCalls==1,'managed switches must not write standalone shadow/bloom or repeat configuration')
-- Optional dependency failure: fresh module load with GameSettings/DebugLog unavailable.
local oldRequire=require
require=function(name)if name=='ruins.GameSettings' or name=='ruins.DebugLog' then error('optional module absent')end return oldRequire(name)end
local Standalone=assert(loadfile('scripts/ruins/SkyAtmosphere.lua'))()
require=oldRequire
local standalone=Standalone.New(scene,dn)
assert(standalone.quality=='high' and standalone.clouds.count==24 and standalone.motes.count==80)
assert(not standalone.realFog,'Web has no real fog even without settings')
assert(standaloneCalls>0 and configureCalls==2)
standalone:SetFeature('clouds',false);assert(standalone.clouds.count==8)
standalone:SetQuality('off');assert(not standalone.active)
standalone:SetQuality('high');standalone:SetFeature('clouds',true);assert(standalone.clouds.count==24)
standalone:Stop()
print('PASS missing optional settings/log modules: safe standalone high defaults')
