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
input={numTouches=0}
package.loaded['urhox-libs.Platform.PlatformUtils']={IsWebPlatform=function()return web end,IsMobilePlatform=function()return mobile end}
graphics={GetComputeShaderSupport=function()return compute end}
renderer={SetVolumetricFogFroxelEnabled=function(self,v)self.froxel=v end,SetVolumetricFogQuality=function(self,v)self.fogQuality=v end}
Material={new=function()return{Dispose=dispose,params={},SetShaderParameter=function(s,k,v)s.params[k]=v end,SetTechnique=function()end,SetTexture=function()end,SetSurfaceShader=function()return true end,SetSurfaceTexture=function(s,k,v)s.textureBinds=(s.textureBinds or 0)+1;s.textureName=k;return true end,Clone=function()return Material:new()end}end}
cache={GetResource=function(_,kind,path)local r=Material:new();if path=='Textures/Sky/cloud_sculpted_atlas.png' then r.width,r.height=2048,1024 elseif path=='Textures/Sky/cloud_sculpted_atlas_low.png' then r.width,r.height=1024,512 end;return r end}
Image=function()return{Dispose=dispose,SetSize=function()end,SetPixel=function()end}end
Texture2D={new=function()return{Dispose=dispose,SetData=function()end}end}
ParticleEffect={new=function()return{Dispose=dispose,frames={},SetNumColorFrames=function()end,AddColorTime=function(s,c,t)table.insert(s.frames,{color=c,time=t})end}end}
local function geometry()
 return {verts={},inView=true,BeginGeometry=function()end,DefineVertex=function(s,v)table.insert(s.verts,{x=v.x,y=v.y,z=v.z})end,
 DefineNormal=function(s,n)s.verts[#s.verts].normal=n end,
 DefineColor=function(s,c)s.verts[#s.verts].color={r=math.floor(c.r*255)/255,g=math.floor(c.g*255)/255,b=math.floor(c.b*255)/255,a=math.floor(c.a*255)/255}end,
 DefineTexCoord=function(s,uv)s.verts[#s.verts].uv=uv end,
 Commit=function(s)s.commits=(s.commits or 0)+1 end,SetMaterial=function(s,m)s.material=m end}
end
local function node(name)
 return {Dispose=dispose,Remove=dispose,CreateScriptObject=function()return{SubscribeToEvent=function()end,UnsubscribeFromAllEvents=function()end}end,name=name,children={},enabled=true,position=Vector3.ZERO,
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

local logger=require('ruins.DebugLog')
local probes={}
local registerProbe=logger.RegisterProbe
logger.RegisterProbe=function(k,f)probes[k]=f;registerProbe(k,f)end
local scene=node('Scene')
local dn=require('ruins.DayNight').New({scene=scene,zone={},sun={SetAttribute=function()end},sunNode=node('Sun'),zoneNode=node('Env'),hour=12})
local Quality=require('ruins.LightQuality')
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
settings.Set('quality','high')
local cancelled=atmosphere.clouds
for i=1,8 do atmosphere:Update(1/60,Vector3.ZERO,ground)end
assert(cancelled.ready and not cancelled.baking and cancelled.bakeSlices==0)
settings.Set('quality','medium')
assert(cancelled.root.disposed and cancelled.material.disposed and not cancelled.job and not cancelled.baking)
FinishCloud(atmosphere.clouds);assert(atmosphere.clouds.triangleCount==atmosphere.clouds.count*8+2)
settings.Set('quality','low');assert(atmosphere.clouds.horizonOnly)
print('PASS real settings replace an immediately ready high patch mesh, dispose it, build medium and release on low')
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
local oldUpper=atmosphere.clouds
atmosphere:SetFeature('clouds',false)
assert(oldUpper.root.disposed and not atmosphere.clouds and settings.Get('clouds')==false)
atmosphere:SetFeature('clouds',true)
atmosphere:SetFeature('lowClouds',false)
FinishCloud(atmosphere.clouds)
assert(atmosphere.clouds.count==16 and atmosphere.clouds.batchCount==1 and settings.Get('lowClouds')==false)
settings.Apply();assert(atmosphere.clouds.count==16,'resolved profile must retain explicit low-cloud override')
atmosphere:SetFeature('cloudShadow',false);assert(ground.params.cloud_shadow_strength==0)
atmosphere:SetFeature('clouds',true);atmosphere:SetFeature('lowClouds',true);atmosphere:SetFeature('cloudShadow',true)
assert(atmosphere.clouds.count==24)
local oldScatter={};dn.zone.volumetricFogScatteringColor=oldScatter;dn.sun.volumetricFogIntensity=.123
assert(not dn.zone.volumetricFogEnabled)
dn:SetHour(17)
assert(dn.zone.volumetricFogScatteringColor==oldScatter and dn.sun.volumetricFogIntensity==.123)
print('PASS cloud master/lower/shadow settings round-trip and release; disabled volume skips DayNight scattering writes')

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
 local params=atmosphere.clouds.material.params
 assert(params.day==params.day and params.day>=0 and params.day<=1)
 assert(params.dusk==params.dusk and params.dusk>=0 and params.dusk<=1)
 assert(params.sky_top.r==dn.sky.skyTopColor.r and params.sky_horizon.b==dn.sky.skyHorizonColor.b)
 for _,color in ipairs({params.sky_top,params.sky_horizon})do
  for _,value in ipairs({color.r,color.g,color.b})do assert(value==value and value>=0 and value<=1)end
 end
 assert(params.cloud_enabled==1 and params.use_volume==nil,'only the celestial atlas path is active')
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
atmosphere:SetQuality('off')
assert(settings.Get('quality')=='low' and atmosphere.clouds.count==4,'off alias delegates low while preserving explicit-on overrides')
settings.Set('clouds',nil);settings.Set('lightShafts',nil);settings.Set('floatingMotes',nil);settings.Set('volumetric',nil)
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
print('PASS off controls: advanced menu releases each feature; low explicit-on minimums 4/3/28; quality alias delegates settings without bypass')

oldCloud,oldShaft,oldMote=atmosphere.clouds,atmosphere.shafts,atmosphere.motes
atmosphere:Stop();atmosphere:Stop()
assert(oldCloud.root.disposed and oldShaft.node.disposed and oldMote.texture.disposed)
assert(not probes.skyfx and not atmosphere.active and not atmosphere.scene and not atmosphere.ground)
settings.Set('quality','low');settings.Set('quality','high');assert(not atmosphere.clouds)
settings.Stop()
print('PASS Stop idempotent, unregisters quality/probe, disposed effects never resurrect')
-- Optional dependency failure: fresh module load with GameSettings/DebugLog unavailable.
local oldRequire=require
require=function(name)if name=='ruins.GameSettings' or name=='ruins.DebugLog' then error('optional module absent')end return oldRequire(name)end
local Standalone=assert(loadfile('scripts/ruins/SkyAtmosphere.lua'))()
require=oldRequire
local standalone=Standalone.New(scene,dn)
assert(standalone.quality=='high' and standalone.clouds.count==24 and standalone.motes.count==80)
assert(not standalone.realFog,'Web has no real fog even without settings')
standalone:SetFeature('clouds',false);assert(standalone.clouds.count==8)
standalone:SetFeature('lowClouds',false);assert(not standalone.clouds)
standalone:SetQuality('off');assert(not standalone.active)
standalone:Stop()
print('PASS missing optional settings/log modules: safe standalone high defaults')

local resource=cache.GetResource
assert(loadfile('validation/sky-fx/skycards_contract.lua'))()(scene,dn,FinishCloud)

local projected=Standalone.New(scene,dn)
local groundA,groundB=Material:new(),Material:new()
local lookups=0
cache.GetResource=function(s,k,p)lookups=lookups+1;return resource(s,k,p)end
projected:Update(.2,Vector3.ZERO,groundA)
assert(lookups==1 and groundA.params.cloud_shadow_use_atlas==1 and groundA.textureName=='cloud_shadow_atlas')
for i=1,600 do projected:Update(1/60,Vector3.ZERO,groundA)end
assert(lookups==1 and groundA.textureBinds==1,'shadow must bind once, not every frame')
projected:Update(.2,Vector3.ZERO,groundB)
assert(lookups==2 and groundA.params.cloud_shadow_strength==0 and groundB.textureBinds==1)
projected:SetFeature('cloudShadow',false)
assert(groundB.params.cloud_shadow_strength==0 and groundB.params.cloud_shadow_use_atlas==0 and not projected.shadowGround)
for i=1,600 do projected:Update(1/60,Vector3.ZERO,groundB)end
assert(lookups==2,'disabled shadows must not load or bind textures')
projected:SetFeature('cloudShadow',true)
assert(lookups==3 and groundB.textureBinds==2 and groundB.params.cloud_shadow_use_atlas==1)
projected:Stop()
assert(groundB.params.cloud_shadow_strength==0 and groundB.params.cloud_shadow_use_atlas==0 and not projected.shadowGround)
cache.GetResource=resource

for _,failure in ipairs({'missing','binding'})do
 local s=Standalone.New(scene,dn)
 local target=Material:new()
 local attempts=0
 cache.GetResource=function(owner,kind,path)
  attempts=attempts+1
  if failure=='missing' and kind=='Texture2D' then return nil end
  return resource(owner,kind,path)
 end
 if failure=='binding' then target.SetSurfaceTexture=function()return false end end
 local savedPrint,savedFormat=print,string.format
 print=function()error('ungated shadow fallback log')end
 string.format=function()error('ungated shadow fallback formatting')end
 s:Update(.2,Vector3.ZERO,target)
 assert(target.params.cloud_shadow_use_atlas==0 and target.params.cloud_shadow_strength==.16)
 for i=1,600 do s:Update(1/60,Vector3.ZERO,target)end
 assert(attempts==1,'failed binding must not retry every frame')
 s:Stop()
 print,string.format=savedPrint,savedFormat
 cache.GetResource=resource
end
print('PASS same-atlas ground shadow: one binding per enable/ground; 600 frames no resource lookups; replacement/off/Stop clear old strength; missing/binding failure analytic fallback without retries/logging')
