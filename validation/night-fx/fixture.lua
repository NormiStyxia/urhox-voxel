function Vector4(x,y,z,w)return {x=x,y=y,z=z,w=w}end
package.path='scripts/?.lua;'..package.path
local vm={}
function vm:Lerp(b,t)return Vector3(self.x+(b.x-self.x)*t,self.y+(b.y-self.y)*t,self.z+(b.z-self.z)*t)end
function vm:Normalized() local n=math.sqrt(self.x*self.x+self.y*self.y+self.z*self.z);return Vector3(self.x/n,self.y/n,self.z/n) end
Vector3=setmetatable({},{__call=function(_,x,y,z)return setmetatable({x=x or 0,y=y or 0,z=z or 0},{__index=vm})end})
Vector3.ZERO=Vector3(0,0,0);Vector3.UP=Vector3(0,1,0)
Vector2=setmetatable({ZERO={x=0,y=0}},{__call=function(_,x,y)return{x=x,y=y}end})
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
function cache:GetResourceAsync(kind,path,callback) callback(self:GetResource(kind,path)) end
Image=function()return{Dispose=dispose,SetSize=function()end,SetPixel=function()end}end
Texture2D={new=function()return{Dispose=dispose,SetData=function()end}end}
ParticleEffect={new=function()return{Dispose=dispose,frames={},SetNumColorFrames=function()end,AddColorTime=function(s,c,t)table.insert(s.frames,{color=c,time=t})end}end}
local function geometry()
 return {verts={},inView=true,BeginGeometry=function(s)s.verts={}end,DefineVertex=function(s,v)table.insert(s.verts,{x=v.x,y=v.y,z=v.z})end,
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
