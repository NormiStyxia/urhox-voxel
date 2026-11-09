"""Regression checks against the approved face and authored structural constraints."""
import json
from pathlib import Path
import numpy as np
from refine import protect_face,quad_points,OFFSET,DIRS,COLORS
from review_mesh import read_lua,triangles,shape

HERE=Path(__file__).resolve().parent
ROOT=HERE.parent.parent
q,p,t,b=read_lua(ROOT/'scripts/game/NomiVoxelData.lua')
saved=json.loads((HERE/'approved_head.json').read_text())
oldq=[('head',DIRS[int(r[0])-1],*r[1:6],int(r[6])-1) for r in saved['quads']]
oldt=[('head',np.array(r[:9]).reshape(3,3),int(r[9])-1) for r in saved['tris']]
oldpal=np.array(saved['palette'])*255
old=[(v,c) for _,v,c in triangles(oldq,oldt)]
new=[(v,c) for name,v,c in triangles(q,t) if name=='head']
assert len(old)==len(new)
face_count=0
for (v,c),(vv,cc) in zip(old,new):
    assert np.array_equal(v,vv),'approved head geometry changed'
    if protect_face(v):
        assert np.array_equal(oldpal[c],p[cc]),'protected face RGB changed'
        face_count+=1
bone_map={name:(parent,pivot) for name,parent,pivot in b}
for side in ['right','left']:
    assert bone_map['shin_'+side][0]=='leg_'+side
    assert bone_map['shin_'+side][1][1]==12
alltris=triangles(q,t)
for name,v,c in alltris:
    assert np.isfinite(v).all()
    assert np.linalg.norm(np.cross(v[1]-v[0],v[2]-v[0]))>1e-9,(name,'degenerate face')
    assert 0<=c<len(p)
# The hanging locks live outside the hood width in final slender coordinates.
# Root attachments intentionally overlap the head, so only the hood's vertical band is tested.
# Full per-bone scaling includes a pivot transformed by Shape (not a world origin scale).
pivot=shape('hair_back',np.array((0,51,-8)))
hair=np.concatenate([(shape(n,v)-pivot)*.85+pivot for n,v,c in alltris if n=='hair_back'])
hood=np.concatenate([shape(n,v) for n,v,c in alltris if n=='hood'])
hair_band=hair[(hair[:,1]>=40)&(hair[:,1]<=50)]
gap=float(np.abs(hair_band[:,0]).min()-np.abs(hood[:,0]).max())
assert gap>1,'hanging hair merges into hood'
for name in ['hair_back','hair_locks']:
    colours={tuple(p[c]) for n,_,c in alltris if n==name}
    approved={tuple(np.round(np.array(COLORS[x])/255,3)*255) for x in ['hair','hair_edge']}
    assert colours<=approved
nonface={tuple(p[c]) for n,_,c in alltris if n!='head'}
assert len(nonface)<=11
# Skin cannot appear on the coat/hood, and white hair cannot be projected onto those surfaces.
coat_allowed={tuple(np.round(np.array(COLORS[x])/255,3)*255) for x in ['navy','fold','lining']}
for n,_,c in alltris:
    if n.startswith(('coat','cloak')) or n=='hood': assert tuple(p[c]) in coat_allowed
report={'head_triangles_unchanged':len(old),'face_triangles_rgb_unchanged':face_count,
        'non_head_colour_count':len(nonface),'hair_to_hood_lateral_gap_m':round(gap*.022,5),
        'bones':len(b),'render_triangles':len(alltris)}
print(json.dumps(report,indent=2))
(ROOT/'.tmp/nomi-review/checks.json').write_text(json.dumps(report,indent=2))
