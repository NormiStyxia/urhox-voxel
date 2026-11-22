"""Offline Lua entry/quality and material contracts; never starts UrhoX."""
from pathlib import Path
import os
import re
import xml.etree.ElementTree as ET
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
os.chdir(ROOT)

def character_runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
local support=dofile('tests/combat/core_support.lua')
local baseQuaternion=Quaternion
Quaternion=function(a,b,c,d)
 if type(b)=='table' then
  local h=math.rad(a)*.5
  return baseQuaternion(math.cos(h),b.x*math.sin(h),b.y*math.sin(h),b.z*math.sin(h))
 end
 return baseQuaternion(a,b,c,d)
end
Clamp=function(x,a,b)return math.max(a,math.min(b,x))end
Lerp=function(a,b,t)return a+(b-a)*t end
Vector2=function(x,y)return {x=x,y=y}end
TRIANGLE_LIST=0
MATERIAL={path='Materials/Nomi.xml',textures={}}
function MATERIAL:SetSurfaceTexture(name,texture)self.textures[name]=texture end
cache={GetResource=function(_,kind,path)
 if kind=='Material' then assert(path==MATERIAL.path);return MATERIAL end
 if kind=='Texture2D' then return {path=path} end
end}
local Node={}
Node.__index=function(self,key)
 if key=='worldRotation' then return self.parent and self.parent.worldRotation*self.rotation or self.rotation end
 if key=='worldPosition' then return self.parent and self.parent:LocalToWorld(self.position) or self.position end
 return Node[key]
end
function Node:LocalToWorld(p)return self.worldPosition+self.worldRotation*p end
function Node:WorldToLocal(p)
 local q=self.worldRotation
 return Quaternion(q.w,-q.x,-q.y,-q.z)*(p-self.worldPosition)
end
function Node:CreateChild(name)
 local n=setmetatable({name=name,parent=self,position=Vector3.ZERO,rotation=Quaternion(),scale=Vector3(1,1,1),children={}},Node)
 self.children[#self.children+1]=n;return n
end
function Node:GetChild(name)
 for _,n in ipairs(self.children)do if n.name==name then return n end end
end
GEOMETRY={}
function Node:CreateComponent(kind)
 if kind~='CustomGeometry' then return {} end
 local g={node=self,vertices={},normals={},uv={}}
 function g:BeginGeometry()end
 function g:DefineVertex(p)self.vertices[#self.vertices+1]=p end
 function g:DefineNormal(p)self.normals[#self.normals+1]=p end
 function g:DefineTexCoord(p)self.uv[#self.uv+1]=p end
 function g:Commit()self.committed=true end
 function g:SetMaterial(_,m)self.material=m end
 GEOMETRY[#GEOMETRY+1]=g;return g
end
scene=setmetatable({position=Vector3.ZERO,rotation=Quaternion(),children={}},Node)
package.loaded['urhox-libs.Camera.ThirdPersonCamera']={}
ThirdPersonCamera={Create=function()return {}end}
package.loaded['ruins.TimeObject']={}
package.loaded['ruins.DebugLog']={SetEnabled=function()end}
package.loaded['ruins.RuinsTerrain']={}
controller=require('ruins.NomiController').New(scene,{},Vector3.ZERO,0)
character=controller.nomi
assert(#GEOMETRY>20,'actual YSM controller entry must create articulated geometry')
local total=0
for _,g in ipairs(GEOMETRY)do
 assert(g.committed and g.material==MATERIAL and g.castShadows==true)
 assert(#g.vertices==#g.normals and #g.vertices==#g.uv and #g.vertices%3==0)
 total=total+#g.vertices
end
assert(MATERIAL.textures.albedo_map.path=='Textures/Characters/nomi.png')
print('PASS actual NomiController.New -> BlockCharacter.Create: '..#GEOMETRY..' casters, '..total..' textured vertices')
function pose(clip,phase)
 local data=require('game.NomiYSMData')
 character.time=phase*data.animations[clip].length
 character.bbMotion=clip=='idle' and 0 or 1
 character.bbRun=clip=='run' and 1 or 0
 character.bbCycle=phase
 character.air,character.crouch,character.armed=0,0,0
 character:UpdateImportedLocomotion(0,{onGround=true},clip=='run' and 7.2 or 4.2,0)
end
''')
    return lua

def quality_contract(lua):
    lua.execute('''
GetPlatform=function()return 'Web'end
input={numTouches=0}
fileSystem={FileExists=function()return false end}
renderer={}
Variant=function(v)return v end
CascadeParameters=function(...)return {...}end
BLOOM_MODE_UE=1;BLOOM_MODE_LEGACY=0
function Node()return {CreateScriptObject=function()return {SubscribeToEvent=function()end,UnsubscribeFromAllEvents=function()end}end}end
package.loaded['ruins.ContactAO']={New=function()return {SetQuality=function()end}end}
local settings=require('ruins.GameSettings')
settings.Load()
local sun={SetAttribute=function()end}
local dayNight={capture={resolution=64},Apply=function()end}
require('ruins.SceneQuality').Attach{sun=sun,zone={},dayNight=dayNight,surfaceMaterials={}}
for _,tier in ipairs({'high','medium','low','high'})do
 assert(settings.Set('quality',tier))
 assert(sun.castShadows==(tier~='low'),'actual SceneQuality callback must respect selected tier')
 assert(renderer.shadowMapSize==settings.PROFILES[tier].shadowMapSize)
 for _,g in ipairs(GEOMETRY)do assert(g.castShadows==true)end
end
for _,mode in ipairs({'off','low','high','off','high'})do
 assert(settings.Set('shadows',mode))
 assert(sun.castShadows==(mode~='off'),'explicit shadow override must win')
end
assert(MATERIAL.textures.albedo_map.path=='Textures/Characters/nomi.png')
print('PASS real GameSettings.Set -> SceneQuality callbacks: high/medium/low/high and shadow off/low/high; no character/material replacement')
''')

def material_contract():
    material=ET.parse('assets/Materials/Nomi.xml').getroot()
    assert material.find('surfaceshader').get('name')=='Shaders/BLGL/BlockCharacter.shader'
    assert material.find('surfacetexture').get('texture')=='Textures/Characters/nomi.png'
    assert material.find('shadowcull').get('value')=='none'
    shader=Path('assets/Shaders/BLGL/BlockCharacter.shader').read_text()
    src=re.sub(r'//[^\n]*','',shader)
    assert 'shading_model_pbr' in src and 'blend_' not in src
    assert re.search(r'ALBEDO\s*=\s*vec3\(0\.0\)',src)
    for channel in ['SPECULAR','METALLIC']:assert re.search(channel+r'\s*=\s*0\.0',src)
    assert 'ambient_light_disabled' in src and 'specular_disabled' in src
    assert 'ALPHA = c.a' in src and 'ALPHA_SCISSOR_THRESHOLD = 0.5' in src
    assert 'filter_nearest, repeat_disable' in src
    assert 'EMISSION = rgb * (rgb * (rgb * 0.305306011 + 0.682171111) + 0.012522878)' in src
    print('PASS opaque PBR caster / alpha cutout / two-sided shadow / original emissive display colour contract (not an engine shader compilation)')

if __name__=='__main__':
    runtime=character_runtime()
    quality_contract(runtime)
    material_contract()
