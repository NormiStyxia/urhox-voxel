exec(open('validation/settings/check.py').read())
# Native math constructors only; retain this test's settings subscription mock.
lua.execute(Path('validation/sky-fx/check.lua').read_text().split('local web,',1)[0])
lua.execute(r'''
local children={}; for i=1,16 do children[i]={enabled=true} end
local terrain=require('ruins.RuinsTerrain')
terrain.grass,terrain.flowers,terrain.tufts={enabled=true},{enabled=true},{root={GetChildren=function() return children end}}
terrain.groundMaterial={params={},SetShaderParameter=function(s,k,v)s.params[k]=v end}
renderer={}; BLOOM_MODE_LEGACY=1; BLOOM_MODE_UE=3
Variant=function(x) return x end
CascadeParameters=function(...) return {...} end
local host={sun={SetAttribute=function(self,k,v) self[k]=v end},
 zone={bloomMode=3,bloomWeight=.25,bloomPlusIntensity=.675,bloomUEIntensity=.675},
 dayNight={capture={resolution=64,minCaptureInterval=.5},capturePending=false,day=1,
 Apply=function(self)self.applies=(self.applies or 0)+1;self.contactAO:Apply(self.day)end}}
storage=nil; platform='Windows'; S.Load()
require('ruins.SceneQuality').Attach(host)
assert(host.dayNight.contactAO.layoutSupported and host.dayNight.applies==1)
assert(terrain.groundMaterial.params.contact_ao_strength==S.GetProfile().contactAO)
assert(host.sun.castShadows and renderer.shadowMapSize==2048 and terrain.grass.density==110)
S.Set('quality','medium')
assert(host.sun.castShadows and host.sun.shadowCascade[2]==65 and host.sun.shadowCascade[3]==0)
assert(terrain.grass.density==55 and terrain.flowers.density==1.25 and host.zone.bloomMode==1 and host.zone.bloomWeight==0)
assert(host.dayNight.capture.resolution==32 and host.dayNight.capture.minCaptureInterval==2 and host.dayNight.capturePending)
local active=0; for _,node in ipairs(children) do if node.enabled then active=active+1 end end; assert(active==8)
S.Set('quality','low'); assert(not host.sun.castShadows and terrain.grass.density==27.5)
assert(terrain.groundMaterial.params.contact_ao_strength==0)
S.Set('grass','off'); assert(not terrain.grass.enabled and not terrain.flowers.enabled and not terrain.tufts.root.enabled)
S.Set('grass',nil); S.Set('quality','high'); assert(terrain.grass.enabled and host.zone.bloomMode==3 and host.zone.bloomUEIntensity==.675)
S.Set('shadows','off'); S.Set('quality','medium'); assert(not host.sun.castShadows)
S.Stop(); assert(nodes==0)
''')
print('Scene quality mock: shadows, capture, postfx, native grass, fallback thinning + hot restoration PASS')
