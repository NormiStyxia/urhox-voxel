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
    assert np.array_equal(oldpal[c],p[cc]),'authored head RGB changed'
    if protect_face(v):
        face_count+=1
# Exact part restoration is the acceptance criterion; a low colour count is not.
import hashlib
baseline=json.loads((HERE/'rollback_baseline.json').read_text())
cleanup=json.loads((HERE/'detail_cleanup.json').read_text())
edits={(e['kind'],e['index']):e for e in cleanup['edits']}
def digest(names, undo_cleanup=False):
    records=[]
    for kind,items in [('q',q),('t',t)]:
        for i,row in enumerate(items):
            if row[0] not in names:continue
            rgb=p[row[-1]].tolist()
            if undo_cleanup and (kind,i) in edits:
                edit=edits[kind,i]
                assert row[0]==edit['bone'] and rgb==edit['after'],'targeted cleanup changed'
                rgb=edit['before']
            records.append([kind,*row[:-1],rgb])
    return hashlib.sha256(json.dumps(records,separators=(',',':')).encode()).hexdigest()
hair={'head','hair_back','hair_locks'}
parts={name for name,_,_ in b}-hair
assert digest(parts,True)==baseline['clothing_limbs'],'unreviewed clothing/limb change'
assert digest({'hair_back','hair_locks'})==cleanup['hanging_hair'],'accepted hanging hair changed'
assert json.loads(json.dumps(b))==baseline['original_bones'],'bone structure not restored'
report={'head_triangles_unchanged':len(old),'face_triangles_rgb_unchanged':face_count,
        'clothing_geometry_and_unmarked_colours_preserved':True,
        'authored_head_rgb_restored':True,'hanging_hair_preserved':True,
        'targeted_colour_edits':len(edits),
        'bones':len(b),'palette_entries':len(p)}
print(json.dumps(report,indent=2))
(ROOT/'.tmp/nomi-review/checks.json').write_text(json.dumps(report,indent=2))
