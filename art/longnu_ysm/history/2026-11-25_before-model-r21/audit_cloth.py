"""Full-cycle, exported-cuboid contact checks and the two run extrema in three projections."""
import argparse
import json

import numpy as np
from PIL import Image, ImageDraw
import build_longnu as b
from audit_animations import channels, collisions, rig, world_boxes


def pair_grid(a,b):
    return tuple(v.ravel() for v in np.meshgrid(a,b,indexing='ij'))


def check(model,steps=65):
    mesh=rig(model);parts,labels=mesh[-2:];parts['outer']=sorted(set(parts['coat']+parts['shell']+parts['sleeve']+parts['cape']))
    pairs={f'{a}/{b}':pair_grid(parts[a],parts[b]) for a,b in [('leg','skirt'),('leg','coat'),('bow','skirt'),('bow','leg'),('bow','outer'),('tail','leg'),('tail','outer')]}
    result={}; extrema={}
    ids={g['name']:g['uuid'] for g in model['groups']}
    for anim in model['animations']:
        if anim['name'] not in ('walk','run','idle','sneak','jump','sit'):continue
        curves=channels(anim);duration=anim['length'] or max(k['time'] for t in anim['animators'].values() for k in t.get('keyframes',[]));summary={k:[0,0] for k in pairs}
        gap_pairs = {'belt_clearance':pair_grid(parts['bow'],parts['leg']+parts['skirt'])}
        summary['belt_clearance']=[0,0]
        for t in np.linspace(0,duration,steps):
            centers,edges=world_boxes(mesh,curves,t)
            contacts=collisions(centers,edges,pairs)
            contacts.update(collisions(centers,edges,gap_pairs,margin=.25))
            for k,(count,depth,i,j) in contacts.items():
                row=summary[k];row[0]+=1
                if depth>row[1]:row[1:]=[depth,round(t,6),labels[i],labels[j]]
        result[anim['name']]=summary;print(anim['name'],json.dumps({k:[row[0],round(row[1],4),*row[2:]] for k,row in summary.items()},ensure_ascii=False),flush=True)
        if anim['name']=='run':
            # A difference between two linear tracks reaches its extrema on the union of their knots.
            left,right=(curves[(ids[s+'Leg'],'rotation')] for s in ('Left','Right'))
            times=np.unique([*left[0],*right[0]]);split=np.interp(times,left[0],left[1][0])-np.interp(times,right[0],right[1][0]);
            extrema=[(float(times[k]),world_boxes(mesh,curves,times[k])) for k in (np.argmax(split),np.argmin(split))]
    return result,mesh,extrema


def render_check(model,mesh,extrema):
    # Recover each visible face from its exported cube UV and animated half-edge vectors.
    from types import SimpleNamespace
    elements={e['uuid']:e for e in model['elements']};ordered=[]
    def walk(node):
        for k in node['children']:
            if isinstance(k,dict):walk(k)
            else:ordered.append(elements[k])
    walk(model['outliner'][0]); parts=[SimpleNamespace(faces={f:d['uv'] for f,d in e['faces'].items()}) for e in ordered]
    unit=b.Cube('unit',[-1,-1,-1],[1,1,1],None);quad={f:np.array(q) for f,q in b.face_quads(unit).items()};atlas=np.asarray(Image.open(b.OUT/'longnu.png').convert('RGBA'))
    sheet=Image.new('RGB',(1560,1680),(219,221,229));pen=ImageDraw.Draw(sheet)
    for row,(t,(center,edge)) in enumerate(extrema):
        faces=[(c,f,q@edge[i].T+center[i]) for i,c in enumerate(parts) for f,q in quad.items()]
        for col,(yaw,caption) in enumerate(((0,'Front'),(90,'Side'),(180,'Back'))):
            im=b.render(faces,atlas,yaw,0,scale=17.4,size=(520,815),center=(0,21,0));sheet.paste(Image.fromarray(im),(520*col,840*row+25));pen.text((520*col+12,840*row+7),f'run   {t:.4f} s   {caption}',fill=(55,53,64))
    sheet.save(b.OUT/'run_pose_check.png')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--steps',type=int,default=65);parser.add_argument('--render',action='store_true');args=parser.parse_args();model=json.loads((b.OUT/'longnu.bbmodel').read_text());result,mesh,extrema=check(model,args.steps)
    if args.render:render_check(model,mesh,extrema)
    if any(row[0] for data in result.values() for row in data.values()):
        raise SystemExit('服装动作检查有未通过项目')
