"""Exercise real Cloud Lua + read-only engine async wrapper with a queued download.
No Runtime/GPU: documents cold-cache behavior, not the observed Web root cause.
"""
from pathlib import Path
import subprocess
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
prefix = (ROOT/'validation/sky-fx/check.lua').read_text().split('local settings=require',1)[0]
old = subprocess.check_output(['git','show','1a78a3d:scripts/ruins/SkyClouds.lua'],text=True)
current = (ROOT/'scripts/ruins/SkyClouds.lua').read_text()
wrapper = (ROOT/'urhox-libs/Engine/ResourceCacheExtensions.lua').read_text()

def fixture(source):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(prefix + '''
scene=node('Scene')
local original=cache.GetResource
cache.GetResourceAsync=nil
local methods={};methods.__index=methods;setmetatable(cache,methods)
diskReady=false;downloads={};placeholderReads=0;loadCalls=0
placeholder={width=1,height=1}
function cache:Exists(path) return diskReady end
function cache:GetResource(kind,path)
 if path:find('sculpted') then
  loadCalls=loadCalls+1
  if not diskReady then placeholderReads=placeholderReads+1;return placeholder end
 end
 return original(self,kind,path)
end
dm={DownloadResource=function(_,uri,callback)
 downloads[#downloads+1]={uri=uri,callback=callback}
end}
function GetCache()return cache end
function GetDownloadManager()return dm end
LOG_ERROR=1;LOG_WARNING=2;log={Write=function()end}
function finish(index,success)
 diskReady=success
 placeholder.width,placeholder.height=2048,1024
 local item=downloads[index]
 item.callback({IsSuccess=function()return success end,errorMessage='injected failure'})
end
''')
    lua.execute(wrapper)
    lua.globals().Clouds = lua.execute(source)
    return lua

# Reproduce the pre-existing source defect: a DWP placeholder is discarded; even
# when it becomes the real texture, the Cloud has no root/material to hot-reload.
lua = fixture(old)
lua.execute('''
local c=Clouds.New(scene,24,true,true)
assert(c.unavailable and not c.root and placeholderReads==1)
diskReady=true;placeholder.width,placeholder.height=2048,1024
for i=1,600 do c:Update(.2,1,0);c:Follow(Vector3.ZERO) end
assert(c.unavailable and not c.ready and not c.root and loadCalls==1)
''')
print('PASS old source reproduction: cold placeholder -> permanently hidden after real texture arrives')

lua = fixture(current)
lua.execute('''
local c=Clouds.New(scene,24,true,true)
assert(c.loading and not c.unavailable and not c.root and #downloads==1 and placeholderReads==0)
local dn={day=0,dusk=0,sky={skyTopColor=Color(.01,.02,.03),skyHorizonColor=Color(.02,.03,.04),groundBottomColor=Color(.01,.01,.01)}}
for i=1,600 do c:Update(.2,0,0,dn);c:Follow(Vector3(1,30000,3))end
assert(not c.root and #downloads==1 and loadCalls==0,'no polling or placeholder rendering')
finish(1,true)
assert(c.ready and not c.loading and c.count==24 and c.triangleCount==194)
assert(c.material.params.cloud_enabled==1 and c.material.params.day==0 and c.material.params.dusk==0)
assert(c.root.position.y==30000 and c.geometry[1].commits==1)
local root=c.root;finish(1,true);assert(c.root==root,'duplicate completion must not build twice')
c:Dispose();assert(not c.root or c.root.disposed)
''')
print('PASS cold download: no placeholder, no polling, one build, current night palette and bounds before display')

for budget in (24,12,4):
    lua=fixture(current)
    lua.execute('local c=Clouds.New(scene,...,true,true);c:Dispose();finish(1,true);assert(not c.root and not c.material and not c.texture and not c.loading)',budget)
print('PASS disposed high/medium/low ignore late completion, cannot resurrect nodes/materials')

lua=fixture(current)
lua.execute('''
local old=Clouds.New(scene,24,true,true);old:Dispose()
local low=Clouds.New(scene,4,true,false)
finish(1,true);assert(not old.root and not low.root)
finish(2,true);assert(low.ready and low.count==4 and low.triangleCount==34)
assert(downloads[2].uri=='Textures/Sky/cloud_sculpted_atlas_low.png')
''')
print('PASS quality switch while loading: old callback ignored, small atlas builds only current tier')

lua=fixture(current)
lua.execute('''
local c=Clouds.New(scene,24,true,true);finish(1,false)
assert(c.unavailable and not c.loading and not c.root and not c.texture)
for i=1,600 do c:Update(.2,1,0);c:Follow(Vector3.ZERO) end
assert(#downloads==1 and loadCalls==0 and not c.root)
local n=#downloads;local off=Clouds.New(scene,0,false,false)
for i=1,600 do off:Update(.2,1,0);off:Follow(Vector3.ZERO) end
assert(#downloads==n and not off.root and off.elapsed==0)
''')
print('PASS real failure remains hidden without retry; off has zero downloads/updates')

lua=fixture(current)
lua.execute('diskReady=true;local c=Clouds.New(scene,12,true,true);assert(c.ready and c.count==12 and #downloads==0)')
print('PASS cached atlas fast path remains immediate; actual engine wrapper executed read-only')
