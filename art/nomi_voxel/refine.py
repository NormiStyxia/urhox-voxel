"""Semantic finishing of Nomi's sampled mesh. Coordinates are unscaled authoring units.
The approved head is immutable geometry; its face RGB bypasses all colour processing.
Coat, lining, hood and hanging locks are authored as separate closed meshes, not projections.
"""
import json
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
DIRS = ('px', 'nx', 'py', 'ny', 'pz', 'nz')
OFFSET = np.array((26., 0., 22.))
COLORS = {
    'hair': (231, 234, 244), 'hair_edge': (211, 217, 233),
    'navy': (48, 65, 111), 'fold': (57, 76, 123), 'lining': (35, 47, 80),
    'white': (231, 233, 241), 'white_edge': (211, 217, 230),
    'gold': (235, 190, 73), 'gold_edge': (208, 160, 52),
    'skin': (245, 216, 196), 'sole': (39, 48, 72),
}

def quad_points(q):
    _, d, layer, u, v, w, h, _ = q
    p = layer + (d in ('px','py','pz'))
    if d in ('px','nx'):
        pts = [(p,v,u),(p,v+h,u),(p,v+h,u+w),(p,v,u+w)]
    elif d in ('py','ny'):
        pts = [(u,p,v),(u,p,v+h),(u+w,p,v+h),(u+w,p,v)]
    else:
        pts = [(u,v,p),(u+w,v,p),(u+w,v+h,p),(u,v+h,p)]
    pts = np.asarray(pts,float) - OFFSET
    if d in ('nx','ny','nz'): pts = pts[::-1]
    return pts

def protect_face(points):
    # Preserve all face-adjacent surfaces, including cheeks and the existing bangs boundary.
    p = np.asarray(points)
    return p[:,1].min() <= 66 and p[:,1].max() >= 50 and p[:,2].max() >= 0 and p[:,2].min() <= 11.05 and p[:,0].min() <= 12 and p[:,0].max() >= -12

def finish(quads, palette, tris, bones):
    approved = json.loads((HERE / 'approved_head.json').read_text())
    palette = list(np.asarray(palette,float))
    def colour(name):
        rgb = np.asarray(COLORS[name],float)
        for i,c in enumerate(palette):
            if np.array_equal(c,rgb): return i
        palette.append(rgb); return len(palette)-1
    def original(index):
        rgb = np.asarray(approved['palette'][int(index)-1])*255
        for i,c in enumerate(palette):
            if np.array_equal(c,rgb): return i
        palette.append(rgb); return len(palette)-1
    def head_colour(points, index):
        rgb = np.asarray(approved['palette'][int(index)-1])*255
        if protect_face(points): return original(index)
        center = np.mean(points,axis=0)
        # The yellow ribbons stay yellow. All other non-face head surfaces are silver hair.
        if rgb[0] > rgb[2]*1.35 and rgb[1] > rgb[2]*1.2 and abs(center[0]) > 13:
            return colour('gold')
        return colour('hair_edge' if abs(center[0]) > 14 or center[2] < -12 else 'hair')

    qs, ts = [], []
    for raw in approved['quads']:
        d,layer,u,v,w,h,c = raw
        q = ('head',DIRS[int(d)-1],int(layer),int(u),int(v),int(w),int(h),0)
        qs.append(q[:-1]+(head_colour(quad_points(q),c),))
    for raw in approved['tris']:
        pts = np.array(raw[:9]).reshape(3,3)
        ts.append(('head',pts.tolist(),head_colour(pts-OFFSET,raw[9])))

    def painted(bone, points, old):
        x,y,z = np.mean(points,axis=0)
        if bone.startswith('hair'):
            return colour('hair_edge' if z < -10 else 'hair')
        if bone.startswith('arm'):
            if y < 31.7: return colour('skin')
            if 33 <= y < 35: return colour('white')
            return colour('navy')
        if bone == 'body':
            if z > 4 and 34 <= y < 43:
                return colour('gold' if abs(x)<2.1 else 'white')
            if z > 4 and y >= 43:
                return colour('white' if abs(x)<(49-y)*.7 else 'navy')
            return colour('navy')
        # Boots retain only intentional sole, cuff and upper regions.
        if bone.startswith('leg'):
            return colour('sole' if y<1.2 else ('white_edge' if 1.2<=y<2.4 else 'navy'))
        return colour('navy')

    keep = ('body','arm_right','arm_left','leg_right','leg_left','hair_locks')
    # Leave the hand silhouette and bodice intact. Retain only the original boot below y=10.
    for q in quads:
        bone=q[0]
        if bone not in keep or bone.startswith('arm'): continue
        pts=quad_points(q)
        if bone=='body' and pts[:,1].max() <= 33: continue
        if bone.startswith('leg') and pts[:,1].max()>10: continue
        if bone=='hair_locks': continue  # replaced by continuous beveled locks below
        name=bone.replace('leg_', 'shin_') if bone.startswith('leg') else bone
        qs.append((name,)+tuple(q[1:-1])+(painted(bone,pts,q[-1]),))
    for bone,pts,c in tris:
        if bone not in keep or bone=='hair_locks' or bone.startswith('arm'): continue
        p=np.asarray(pts)-OFFSET
        if bone=='body' and p[:,1].max()<=33: continue
        if bone.startswith('leg') and p[:,1].max()>10: continue
        name=bone.replace('leg_', 'shin_') if bone.startswith('leg') else bone
        ts.append((name,pts,painted(bone,p,c)))

    def face(bone, points, col):
        p=np.asarray(points,float)+OFFSET
        ci=colour(col)
        for i in range(1,len(p)-1): ts.append((bone,[p[0].tolist(),p[i].tolist(),p[i+1].tolist()],ci))
    def tube(bone, rings, cols, caps=True):
        # rings: bottom to top, viewed from above clockwise in X/Z.
        n=len(rings[0])
        for j in range(len(rings)-1):
            for i in range(n):
                k=(i+1)%n
                face(bone,[rings[j][k],rings[j+1][k],rings[j+1][i],rings[j][i]],cols[i%len(cols)])
        if caps:
            face(bone,list(reversed(rings[0])),cols[0]); face(bone,rings[-1],cols[0])
    def ring(cx,y,cz,rx,rz,bevel=.6):
        # clockwise around +Y when seen from above
        return [(cx-rx+bevel,y,cz+rz),(cx+rx-bevel,y,cz+rz),(cx+rx,y,cz+rz-bevel),
                (cx+rx,y,cz-rz+bevel),(cx+rx-bevel,y,cz-rz),(cx-rx+bevel,y,cz-rz),
                (cx-rx,y,cz-rz+bevel),(cx-rx,y,cz+rz-bevel)]

    # Sleeves use broad continuous planes, not per-row extrusion ridges.
    # Keep the A-pose silhouette and shoulder pivots; cuffs and hands are distinct regions.
    for side,sgn in [('right',1),('left',-1)]:
        b='arm_'+side
        tube(b,[ring(sgn*18.2,34,-1.5,4,4.5,.8),ring(sgn*14.2,42,-1.5,3.6,4.4,.8),ring(sgn*10.5,48,-1.5,2.8,4,.7)],['navy'])
        tube(b,[ring(sgn*18.6,33,-1.5,4,4.5,.8),ring(sgn*18.2,34,-1.5,4,4.5,.8)],['white'])
        tube(b,[ring(sgn*19,32,-1.5,4,4.5,.8),ring(sgn*18.6,33,-1.5,4,4.5,.8)],['navy'])
        tube(b,[ring(sgn*19.5,28.5,-1.5,2.6,3.3,.2),ring(sgn*18.7,32.5,-1.5,2.6,3.3,.2)],['skin'])

    # Hips are inside the skirt, not at the exposed hem. Knee is a true child pivot.
    bones=list(bones)
    for side,x in [('right',4.5),('left',-4.5)]:
        leg='leg_'+side; shin='shin_'+side
        idx=next(i for i,b in enumerate(bones) if b[0]==leg)
        bones[idx]=(leg,'root',(x,24,-1))
        bones.insert(idx+1,(shin,leg,(x,12,-1)))
        tube(leg,[ring(x,12,-1,3.1,3,.45),ring(x,15,-1,3.35,3.1,.45),ring(x,25,-1,3.6,3.3,.5)],['skin'])
        tube(shin,[ring(x,8.8,-1,3.4,3.8,.4),ring(x,12.4,-1,3.1,3,.45)],['white'])
        # Closed hinge barrel, circular AFTER the slender shape is baked; no dark flat cut.
        rings=[]
        for xx in (x-3.1,x+3.1):
            rings.append([(xx,12+2.8/1.35*np.sin(a),-1+2.8/.92*np.cos(a)) for a in np.linspace(0,2*np.pi,17)[:-1]])
        # Explicit outward orientation along X.
        for i in range(16):
            k=(i+1)%16
            face(leg,[rings[0][i],rings[1][i],rings[1][k],rings[0][k]],'white')
        face(leg,rings[0],'white');face(leg,list(reversed(rings[1])),'white')

    # A separate closed underskirt and a sparse pleated navy skirt, well inside the coat.
    tube('skirt',[ring(0,18,-.2,10.2,7.8,1.2),ring(0,21.4,-.2,9.9,7.6,1.2)],['white','white_edge'])
    tube('skirt',[ring(0,21,-.2,10,7.5,1.1),ring(0,22,-.2,9.9,7.4,1.1)],['white'])
    tube('skirt',[ring(0,22,-.2,9.9,7.4,1.1),ring(0,28,-.2,8.1,6.1,1.1),ring(0,34,-.2,6.9,5.2,1.1)],['navy','fold','navy','navy'])

    def coat_path(y,hw,back,front,gap):
        return [(gap,y,front),(hw-.5,y,front-.6),(hw,y,front-2),(hw,y,back+3),
                (hw-2,y,back),(0,y,back-.4),(-hw+2,y,back),(-hw,y,back+3),
                (-hw,y,front-2),(-hw+.5,y,front-.6),(-gap,y,front)]
    def shell(bone, rows, thickness=.8):
        inside=[[(x*(1-thickness/max(abs(x),8)),y,z+thickness if z<0 else z-thickness) for x,y,z in row] for row in rows]
        for j in range(len(rows)-1):
            for i in range(len(rows[0])-1):
                k=i+1
                # path goes clockwise around the back; reverse orientation for exterior
                face(bone,[rows[j][k],rows[j+1][k],rows[j+1][i],rows[j][i]],'navy' if i%3 else 'fold')
                face(bone,[inside[j][i],inside[j+1][i],inside[j+1][k],inside[j][k]],'lining')
            for i in [0,len(rows[0])-1]:
                p=[rows[j][i],rows[j+1][i],inside[j+1][i],inside[j][i]]
                face(bone,p if i==0 else list(reversed(p)),'navy')
        for j in [0,len(rows)-1]:
            for i in range(len(rows[0])-1):
                p=[rows[j][i],inside[j][i],inside[j][i+1],rows[j][i+1]]
                face(bone,p if j==0 else list(reversed(p)),'navy')
    shell('coat_upper',[coat_path(35.5,9.6,-10.5,9,6.9),coat_path(42,9.4,-11,9,6.9),coat_path(50.5,10,-10,7,5.5)])
    shell('coat_lower',[coat_path(19,15,-13.5,10,11),coat_path(27,12.8,-12.8,10,8.5),coat_path(36.5,9.6,-10.5,9,6.9)])
    # Torn tails are broad independent panels; no one-voxel horizontal teeth.
    for side,sgn in [('r',1),('l',-1)]:
        rows=[[(sgn*13,7 if sgn>0 else 10,-3),(sgn*16,10 if sgn>0 else 7,-7),(sgn*13,13,-12)],
              [(sgn*13,20,1),(sgn*15,20,-7),(sgn*12,20,-13.5)]]
        if sgn<0: rows=[list(reversed(r)) for r in rows]
        shell('cloak_strip_'+side,rows)
    shell('cloak_strip_b',[[(-9,15,-13.4),(-4,18,-14),(0,13,-14.4),(4,17,-14),(9,14,-13.4)],
                           [(-11,20,-13),(-5,20,-13.7),(0,20,-13.9),(5,20,-13.7),(11,20,-13)]])

    # Folded hood: its rear V and front return have independent surfaces and thickness.
    rim=[(-8.1,50,-10),(8.1,50,-10),(8.1,47,-13),(4,42,-14),(0,40.5,-14),(-4,42,-14),(-8.1,47,-13)]
    back=[(x,y,z-.9) for x,y,z in rim]
    face('hood',back,'navy')
    face('hood',list(reversed(rim)),'lining')
    for i in range(len(rim)):
        k=(i+1)%len(rim);face('hood',[rim[i],back[i],back[k],rim[k]],'fold')

    # Side locks sweep from the head, on either side of (not painted onto) the hood.
    # Separate strands keep broad sloped tips; depth never derives from coat samples.
    for sgn in (-1,1):
        for n in range(2):
            x=sgn*(12.7+2.25*n)
            rows=[ring(x+sgn*.8,35.5+3*n,-8.5-1.8*n,.35,.7,.18),
                  ring(x+sgn*.4,40+2*n,-9.4-1.8*n,1.35,1.5,.45),
                  ring(x,49,-7.5-2*n,1.6,1.6,.5),ring(x*.96,54,-7-2*n,1.55,1.5,.5)]
            tube('hair_back',rows,['hair','hair','hair_edge','hair_edge'])
        tube('hair_locks',[ring(sgn*12,43,11.5,.4,.5,.15),ring(sgn*12.5,47,11.5,1.1,1.2,.4),ring(sgn*13.5,53,9,1.3,1.1,.4)],['hair','hair','hair_edge','hair'])

    # Drop unused sampled shades; the retained face RGB is copied exactly, never clustered.
    used=sorted(set(q[-1] for q in qs)|set(t[-1] for t in ts))
    remap={old:new for new,old in enumerate(used)}
    qs=[q[:-1]+(remap[q[-1]],) for q in qs]
    ts=[(b,p,remap[c]) for b,p,c in ts]
    return qs,np.asarray([palette[c] for c in used]),ts,bones
