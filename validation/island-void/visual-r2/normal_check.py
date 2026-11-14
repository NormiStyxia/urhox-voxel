from pathlib import Path
from lupa.lua54 import LuaRuntime
from collections import defaultdict
import math,json,time
p=Path('validation/island-void/visual-r2')
src=Path('validation/island-void/check.lua').read_text().split('-- 角色真实模块')[0].split('-- 比较旧版实际分块分配量')[0]
src=src.replace('DefineNormal=noop','DefineNormal=function(_,n) RecordNormal(n.x,n.y,n.z) end').replace('DefineColor=noop','DefineColor=function(_,c) RecordColor(c.r) end')
src=src.replace('function g:DefineVertex(v) assert(v.y==v.y); self.n=self.n+1 end','function g:DefineVertex(v) assert(v.y==v.y); self.n=self.n+1; RecordVertex(v.x,v.y,v.z) end')
def build(before):
 lua=LuaRuntime(unpack_returned_tuples=True); v=[];n=[];c=[]
 lua.globals().RecordVertex=lambda *x:v.append(x)
 lua.globals().RecordNormal=lambda *x:n.append(x)
 lua.globals().RecordColor=lambda x:c.append(x)
 lua.execute("package.path='scripts/?.lua;'..package.path")
 s=src.replace("local T=require('ruins.RuinsTerrain')","local T=assert(loadfile('validation/island-void/visual-r2/RuinsTerrain.lua'))()") if before else src
 t=time.perf_counter();lua.execute(s);elapsed=time.perf_counter()-t
 return v,n,c,elapsed
a,na,ca,ta=build(True);b,nb,cb,tb=build(False)
assert a==b and ca==cb,'positions/order or color payload changed'
changed={a[i] for i in range(len(a)) if math.dist(na[i],nb[i])>1e-7}
assert changed,'no smoothed normals'
def unit(v):
 l=math.sqrt(sum(x*x for x in v));assert l>0;return tuple(x/l for x in v)
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def sub(a,b):return tuple(x-y for x,y in zip(a,b))
expected=defaultdict(lambda:[0.,0.,0.]);oldnorms=defaultdict(set);newnorms=defaultdict(set)
for i in range(0,len(a),3):
 if ca[i]!=0 or na[i][1]>0:continue
 for j in range(3):
  v=a[i+j]
  if v not in changed:continue
  u=unit(sub(a[i+(j+1)%3],v));w=unit(sub(a[i+(j+2)%3],v))
  angle=math.acos(max(-1,min(1,dot(u,w))))
  for k in range(3):expected[v][k]+=na[i][k]*angle
  oldnorms[v].add(na[i+j]);newnorms[v].add(nb[i+j])
min_dot=1;changed_entries=0
for i in range(len(a)):
 assert abs(dot(nb[i],nb[i])-1)<1e-6,'nonunit normal'
 if ca[i]==1 or na[i][1]>0:assert na[i]==nb[i],'soil/top normal changed'
 elif a[i] in changed:
  assert math.dist(unit(expected[a[i]]),nb[i])<1e-6,'not true adjacent-face angle average'
  min_dot=min(min_dot,dot(na[i],nb[i]));changed_entries+=1
assert min_dot>0,'normal points behind original face'
assert all(len(x)==1 for x in newnorms.values()),'cross chunk normal seam'
samples=[]
for v,ns in oldnorms.items():
 if abs(v[0])<8 and -73<v[2]<-65 and any(n[1]<-.1 for n in ns) and any(abs(n[1])<1e-8 for n in ns):
  angle=max(math.degrees(math.acos(max(-1,min(1,dot(x,y))))) for x in ns for y in ns)
  samples.append({'position':v,'oldCreaseDegrees':angle,'oldNormals':list(ns),'newNormal':next(iter(newnorms[v]))})
samples.sort(key=lambda x:x['oldCreaseDegrees'],reverse=True)
assert samples,'no south outer rim sample'
result={'vertices':len(a),'triangles':len(a)//3,'changedVertexEntries':changed_entries,'shorePositions':len(changed),'minFaceDot':min_dot,'baselineSeconds':ta,'currentSeconds':tb,'southRimSamples':samples[:6]}
(p/'normal-results.json').write_text(json.dumps(result,indent=2))
print('PASS exact emitted vertex/order/color preservation:',len(a),'vertices')
print('PASS unchanged soil/top normals; unit/outward normals; true angle-weighted adjacent geometry; shared normals across chunks')
print('STATS',json.dumps({k:v for k,v in result.items() if k!='southRimSamples'}))
print('CAUSE south rim sample:',json.dumps(samples[0]))
print('CAUSE deep_y=-12, old transition [-13,-10.5]; at all these positive-y shore samples old deep mix is zero')
