"""Semantic finishing of Nomi's sampled mesh. Coordinates are unscaled authoring units.
The approved head is immutable geometry; its face RGB bypasses all colour processing.
Only hanging hair is rebuilt. Clothing, limbs and their colour details pass through unchanged.
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

    # Preserve original clothing, hands and legs verbatim. Cleaning hair must not
    # replace garment construction or overwrite its authored colour accents.
    qs.extend(q for q in quads if q[0] not in ('head','hair_back','hair_locks'))
    ts.extend(t for t in tris if t[0] not in ('head','hair_back','hair_locks'))

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
