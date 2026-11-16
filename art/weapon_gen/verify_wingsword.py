#!/usr/bin/env python3
"""Geometry review on the exact 0.1mm-quantized export. Standard library only."""
import collections, hashlib, json, pathlib
ROOT=pathlib.Path(__file__).resolve().parents[2]
d=json.loads((ROOT/'art/weapon_gen/out/wingsword.json').read_text())
def cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def sub(a,b):return tuple(x-y for x,y in zip(a,b))
def dot(a,b):return sum(x*y for x,y in zip(a,b))
assert len(d['tris'])<=900
seen=set();by_part=collections.defaultdict(list)
for t in d['tris']:
    p=[tuple(round(v*10000) for v in q) for q in t['p']]
    key=tuple(sorted(p));assert key not in seen,'Duplicate triangle';seen.add(key)
    n=cross(sub(p[1],p[0]),sub(p[2],p[0]));assert dot(n,n)>0,'Quantized degeneracy'
    assert sum(round(v*100) for v in t['c'])<=100
    if t['glow']==.35:assert t['c']==[0,0,1]
    by_part[t['part']].append(p)
# Blade and eight feathers are individually closed shells. Checking directed
# edge pairs detects truly inward/inconsistent winding, not just normals
# recomputed from the same vertex order in the Lua loader.
for name,expected in [('blade',1),('wings',8)]:
    ts=by_part[name];edges=collections.defaultdict(list)
    for idx,p in enumerate(ts):
        for a,b in zip(p,p[1:]+p[:1]):edges[tuple(sorted((a,b)))].append((idx,a,b))
    graph=collections.defaultdict(set)
    for uses in edges.values():
        assert len(uses)==2,(name,'unclosed edge',uses)
        a,b=uses;assert a[1]==b[2] and a[2]==b[1],(name,'inconsistent winding')
        graph[a[0]].add(b[0]);graph[b[0]].add(a[0])
    unseen=set(range(len(ts)));volumes=[]
    while unseen:
        pending=[unseen.pop()];component=[]
        while pending:
            i=pending.pop();component.append(i)
            for k in graph[i]&unseen:unseen.remove(k);pending.append(k)
        volume=sum(dot(ts[i][0],cross(ts[i][1],ts[i][2])) for i in component)/6e12
        assert volume>0,(name,'inside-out shell',volume)
        volumes.append(volume)
    assert len(volumes)==expected,(name,len(volumes))
    print(name,'closed outward shells',len(volumes),'volume m3',sum(volumes))
print('PASS triangles',len(d['tris']),'height',d['meta']['height'],'sockets',d['meta']['sockets'])
print('SHA256 Lua',hashlib.sha256((ROOT/'scripts/combat/models/WingSword.lua').read_bytes()).hexdigest())
