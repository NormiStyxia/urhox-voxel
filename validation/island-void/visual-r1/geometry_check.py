from pathlib import Path
from collections import Counter
import math, json
from lupa.lua54 import LuaRuntime
base=Path('validation/island-void/visual-r1')
source=Path('validation/island-void/check.lua').read_text().split('-- 角色真实模块')[0]
source=source.split('-- 比较旧版实际分块分配量')[0]
source=source.replace('function g:DefineVertex(v) assert(v.y==v.y); self.n=self.n+1 end',
 'function g:DefineVertex(v) assert(v.y==v.y); self.n=self.n+1; RecordVertex(v.x,v.y,v.z) end')

def mesh_check(before=False):
 lua=LuaRuntime(unpack_returned_tuples=True)
 vertices=[]
 lua.globals().RecordVertex=lambda x,y,z:vertices.append((x,y,z))
 lua.execute("package.path='scripts/?.lua;'..package.path")
 s=source
 if before:
  s=s.replace("local T=require('ruins.RuinsTerrain')", "local T=assert(loadfile('validation/island-void/visual-r1/RuinsTerrain.lua'))()")
 lua.execute(s+'\nreturn T')
 edges=Counter(); orient=Counter(); tiny=0
 def add(a,b):
  a=tuple(round(x,7) for x in a); b=tuple(round(x,7) for x in b)
  if a==b: return
  key=tuple(sorted((a,b))); edges[key]+=1; orient[key]+=1 if a<b else -1
 for i in range(0,len(vertices),3):
  a,b,c=vertices[i:i+3]
  ab=[b[j]-a[j] for j in range(3)];ac=[c[j]-a[j] for j in range(3)]
  cross=[ab[1]*ac[2]-ab[2]*ac[1],ab[2]*ac[0]-ab[0]*ac[2],ab[0]*ac[1]-ab[1]*ac[0]]
  if sum(v*v for v in cross)<1e-16: tiny+=1
  for a,b in [(a,b),(b,c),(c,a)]:
   # 平坦顶面4m合片边缘与.5m邻片共线；分段后检查几何封闭，不把T接缝误报成洞。
   horizontal=abs(a[1]-b[1])<1e-10 and (a[0]==b[0] or a[2]==b[2])
   n=max(1,round(max(abs(a[0]-b[0]),abs(a[2]-b[2]))/.5)) if horizontal else 1
   for j in range(n):
    p=tuple(a[k]+(b[k]-a[k])*j/n for k in range(3))
    q=tuple(a[k]+(b[k]-a[k])*(j+1)/n for k in range(3))
    add(p,q)
 bad=[(key,count,orient[key]) for key,count in edges.items() if count!=2 or orient[key]!=0]
 tag='baseline' if before else 'current'
 (base/(tag+'-mesh-edges.json')).write_text(json.dumps({'triangles':len(vertices)//3,'degenerate':tiny,'unpaired':len(bad),'samples':bad[:30]},indent=2))
 print(tag, 'triangles',len(vertices)//3,'degenerate',tiny,'unpaired/winding',len(bad))
 if not before: assert not tiny and not bad,tag+' mesh boundary/winding mismatch'
 return lua
mesh_check(True)
lua=mesh_check(False)
lua.execute('''
local T=require('ruins.RuinsTerrain')
local old=assert(loadfile('validation/island-void/visual-r1/RuinsTerrain.lua'))()
local gap,minR,maxR,minLip,maxLip,minSoil,maxSoil=1e9,1e9,-1e9,1e9,-1e9,1e9,-1e9
for j=0,7199 do
 local a=j*math.pi/3600
 local main,inner,outer=T.Edges(a)
 local om,oi,oo=old.Edges(a)
 gap=math.min(gap,inner-main); minR=math.min(minR,main);maxR=math.max(maxR,main)
 assert(inner-main>=5.5-1e-8 and main>33.5 and outer<80)
 assert(math.abs(inner-oi)<1e-8,'outer wall inner support changed')
 for _,r in ipairs({main,inner,outer}) do
  local x,z=r*math.cos(a),r*math.sin(a)
  local lip=6-T.BottomHeight(x,z)
  minLip=math.min(minLip,lip);maxLip=math.max(maxLip,lip)
  local soil=T.SoilDepth(x,z)
  minSoil=math.min(minSoil,soil);maxSoil=math.max(maxSoil,soil)
  assert(soil<lip and soil>=.18 and soil<=.58)
 end
 -- 所有共享承托点顶面不改；环外扩展仍取原高度延拓。
 for _,r in ipairs({20,25,30,33,51,56,64}) do
  local x,z=r*math.cos(a),r*math.sin(a)
  if T.HasGround(x,z) and old.HasGround(x,z) then assert(T.Height(x,z)==old.Height(x,z)) end
 end
end
for i=0,3 do
 local a=math.pi/4+i*math.pi/2
 for x=-3,3,.25 do for z=-3,3,.25 do
  assert(T.HasGround(29.5*math.cos(a)+x,29.5*math.sin(a)+z),'stele footprint cut')
 end end
end
for x=-4.5,4.5,.25 do for z=-68,-49,.25 do assert(T.HasGround(x,z),'spawn path cut') end end
print(string.format('PASS 7200-angle domains: gap>=%.3f, main radius %.3f..%.3f, shore thickness %.3f..%.3f, soil %.3f..%.3f',gap,minR,maxR,minLip,maxLip,minSoil,maxSoil))
print('PASS four full stele footprints / spawn corridor / shared top heights unchanged')
''')

