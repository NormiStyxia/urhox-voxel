"""Offline mesh review using the exported geometry (not the reference projections).
Optional captured runtime matrices allow reviewing the exact evaluated animation pose.
This is a software geometry preview, not a screenshot of the game's lighting.
"""
import json,re
from pathlib import Path
import numpy as np
from PIL import Image
from refine import OFFSET,DIRS,quad_points

def read_lua(path):
    s=Path(path).read_text()
    section=lambda name:s.split('    '+name+' = {',1)[1]
    pal=np.array([[float(v) for v in row.split(',')] for row in re.findall(r'[{]([^{}]+)[}]',section('palette').split('bones = {')[0])])*255
    bones=[]
    for name,parent,pivot in re.findall(r'name = "([^"]+)", parent = ([^,]+), pivot = [{]([^{}]+)[}]',s):
        bones.append((name,None if parent=='nil' else parent.strip('"'),tuple(float(x) for x in pivot.split(','))))
    q=[];t=[]
    for sec in ['quads','tris']:
        a=section(sec).split(chr(10)+'    },')[0]
        for block in a.split(chr(10)+'        },'):
            if ' = {' not in block: continue
            name,rows=block.split(' = {',1)
            name=name.strip()
            vals=[[float(v) for v in row.split(',')] for row in re.findall(r'[{]([^{}]+)[}]',rows)]
            for row in vals:
                if sec=='quads':
                    d,l,u,v,w,h,c=row;q.append((name,DIRS[int(d)-1],l,u,v,w,h,int(c)-1))
                else: t.append((name,np.array(row[:9]).reshape(3,3).tolist(),int(row[9])-1))
    return q,pal,t,bones

def triangles(quads,tris):
    result=[]
    for q in quads:
        p=quad_points(q)
        result += [(q[0],p[[0,1,2]],q[-1]),(q[0],p[[0,2,3]],q[-1])]
    result += [(b,np.array(p)-OFFSET,c) for b,p,c in tris]
    return result

def shape(b,p):
    p=np.array(p,float).copy()
    if b!='head':
        p[...,0]*=.85;p[...,2]=-1+(p[...,2]+1)*.92
    if b.startswith(('leg_','shin_')):p[...,1]=18+(p[...,1]-18)*1.35
    return p

def world_tris(q,pal,t,bones,matrices=None):
    piv={b:shape(b,p) for b,_,p in bones}
    result=[]
    for b,p,c in triangles(q,t):
        local=shape(b,p)-piv[b]
        if matrices is None:
            sc={'head':.82,'hair_locks':.85,'hair_back':.85}.get(b,1)
            world=local*sc+piv[b]+(0,6.3,0)
        else:
            m=np.asarray(matrices[b]).reshape(4,3)
            world=(local*.022 @ m[1:] + m[0])/.022
        result.append(((world+OFFSET).tolist(),pal[c]))
    return result

def sheet(mesh,angles,path,scale=5):
    from voxelize import render_iso
    images=[render_iso({},np.empty((52,84,44)),yaw,pitch,scale=scale,tris=mesh) for yaw,pitch in angles]
    w,h=images[0].size; out=Image.new('RGB',(w*len(images),h),(60,60,60))
    for i,im in enumerate(images):out.paste(im,(i*w,0))
    out.save(path)
    return out

def save_review(q,pal,t,bones,here):
    root=here.parent.parent;dest=root/'.tmp/nomi-review';dest.mkdir(exist_ok=True)
    # Round exactly as the Lua exporter does before judging preserved RGB.
    pal=np.round(pal/255,3)*255
    mesh=world_tris(q,pal,t,bones)
    neutral=sheet(mesh,[(0,0),(65,5),(90,0),(180,0)],dest/'neutral.png')
    structure=sheet(mesh,[(-35,8),(145,8),(-110,-10),(35,-10)],dest/'structure.png')
    out=Image.new('RGB',(neutral.width,neutral.height*2),(60,60,60))
    out.paste(neutral,(0,0));out.paste(structure,(0,neutral.height));out.save(here/'preview_3d.png')
    three=sheet(mesh,[(0,0),(90,0),(180,0)],dest/'three_views.png')
    ref=Image.open(here.parent/'nomi_ysm/ref/ref_ysm_navy.png').convert('RGB')
    ref=ref.resize((three.width,round(ref.height*three.width/ref.width)))
    comparison=Image.new('RGB',(three.width,ref.height+three.height),(60,60,60))
    comparison.paste(ref,(0,0));comparison.paste(three,(0,ref.height));comparison.save(here/'compare.png')
    data={'quads':q,'palette':pal.tolist(),'tris':[(b,np.asarray(p).tolist(),c) for b,p,c in t],'bones':bones}
    (dest/'mesh.json').write_text(json.dumps(data,separators=(',',':'),default=lambda x:x.item()))

if __name__=='__main__':
    import sys
    q,pal,t,bones=read_lua(sys.argv[1]);sheet(world_tris(q,pal,t,bones),[(0,0),(65,5),(90,0),(180,0)],sys.argv[2])
