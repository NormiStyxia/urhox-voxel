#!/usr/bin/env python3
"""v3 regression evidence. Not a shader compiler or a visual acceptance test.
python3 -I art/weapon_gen/verify_sapphire.py [pre-v3 wingsword.json]
"""
import collections, hashlib, json, math, pathlib, re, runpy, sys
ROOT=pathlib.Path(__file__).resolve().parents[2]
d=json.loads((ROOT/'art/weapon_gen/out/wingsword.json').read_text())
shader=(ROOT/'assets/model/forge-blades/WingSword.shader').read_text()
report={'triangles':len(d['tris']),'height':d['meta']['height'],'sockets':d['meta']['sockets']}
assert len(d['tris'])<=1100
normals=[]
for t in d['tris']:
    if t['glow']!=.35:continue
    a,b,c=[[round(v*10000)/10000 for v in q] for q in t['p']]
    y=(a[1]+b[1]+c[1])/3
    u=[b[i]-a[i] for i in range(3)];v=[c[i]-a[i] for i in range(3)]
    n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
    length=math.sqrt(sum(x*x for x in n));n=[x/length for x in n]
    if n[2]<0 and .60<y<1.49:normals.append(n)
report['front_core_normal_x_range']=[min(n[0] for n in normals),max(n[0] for n in normals)]
report['front_core_normal_directions_rounded_0_1']=len(set(tuple(round(x,1) for x in n) for n in normals))
assert report['front_core_normal_x_range'][0]<-.18 and report['front_core_normal_x_range'][1]>.18
assert report['front_core_normal_directions_rounded_0_1']>=6
if len(sys.argv)>1:
    old=json.loads(pathlib.Path(sys.argv[1]).read_text())
    assert old['meta']==d['meta'],'height/bounds/sockets changed'
    assert [t for t in old['tris'] if t['part']!='blade']==[t for t in d['tris'] if t['part']!='blade'],'non-blade changed'
    # All original silhouette points survive. Added edge points must lie on
    # the old piecewise-linear edge profile (no blade widening or shortening).
    oldedge=set(tuple(q) for t in old['tris'] if t['part']=='blade' for q in t['p'] if q[2]==0)
    newedge=set(tuple(q) for t in d['tris'] if t['part']=='blade' for q in t['p'] if q[2]==0)
    assert oldedge<=newedge
    for q in newedge-oldedge:
        side=sorted((p for p in oldedge if p[0]*q[0]>=0),key=lambda p:p[1])
        assert any(a[1]<=q[1]<=b[1] and b[1]>a[1] and
                   abs(q[0]-(a[0]+(b[0]-a[0])*(q[1]-a[1])/(b[1]-a[1])))<1e-9
                   for a,b in zip(side,side[1:]))
    report['baseline_regression']='PASS: metadata, non-blade triangles, silhouette'
# Source-level gate: only the established intrinsic subset, no alpha/screen
# inputs; this intentionally does not pretend to type-check/compile UrhoX.
code=re.sub(r'//[^\n]*','',shader)
functions=set(re.findall(r'\b([A-Za-z_]\w*)\s*\(',code))
allowed={'vertex','fragment','vec3','vec4','hint_range','if','normalize','dot','clamp','mix','smoothstep','pow','floor','fract','sin','step','abs','min','max'}
assert functions<=allowed,functions-allowed
for forbidden in ('ALPHA','SCREEN_UV','texture','blend_mix','c_hot'):
    assert not re.search(r'\b'+forbidden+r'\b',code),forbidden
assert code.count('{')==code.count('}')
for name in ('primary_color','secondary_color','accent_color','grip_color','gold_metal','metal_dark','metal_env',
             'blade_rim','blade_glint','blade_emit','core_glow','crystal_amt','crystal_glow','flow_strength','flow_speed'):
    assert re.search(r'uniform\s+\w+\s+'+name+r'\b',code),name
report['shader_source_gate']='PASS; actual shader compilation remains Web-only'
report['shader_sha256']=hashlib.sha256(shader.encode()).hexdigest()
report['model_sha256']=hashlib.sha256((ROOT/'scripts/combat/models/WingSword.lua').read_bytes()).hexdigest()
out=ROOT/'art/weapons_2d/wing_sword_v3';out.mkdir(exist_ok=True)
(out/'geometry_report.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
