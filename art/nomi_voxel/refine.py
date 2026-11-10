"""Semantic finishing of Nomi's sampled mesh. Coordinates are unscaled authoring units.
The approved head is immutable geometry; its face RGB bypasses all colour processing.
Hanging hair keeps its layered shape; authored head colours are restored.
Clothing geometry is untouched; only reviewed stray light samples are recoloured.
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

def garment_spot(bone, points, rgb):
    """Reviewed sampling spill only; coordinates in unscaled authoring units.

    Coat-front specks sit outside the central white blouse. Sleeve specks are
    on the inner elbow, away from the authored cuff. Lower torn-coat specks
    reproduce nearby sock/skin colours; preserve the holes, replace only RGB.
    """
    x,y,z = np.mean(points,axis=0)
    light = min(rgb) >= 125 and max(rgb)-min(rgb) < 65
    if not light: return False
    if bone == 'coat_upper': return 6 <= abs(x) <= 10 and 37 <= y <= 44
    if bone in ('arm_right','arm_left'): return 11 <= abs(x) <= 14 and 31 <= y <= 34
    if bone in ('cloak_strip_r','cloak_strip_l'): return 10 <= y <= 18
    return False


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
        # Restore authored strands, braids and ribbon/clip shading exactly.
        # Broad replacement colours erased these details even with geometry intact.
        return original(index)

    qs, ts = [], []
    for raw in approved['quads']:
        d,layer,u,v,w,h,c = raw
        q = ('head',DIRS[int(d)-1],int(layer),int(u),int(v),int(w),int(h),0)
        qs.append(q[:-1]+(head_colour(quad_points(q),c),))
    for raw in approved['tris']:
        pts = np.array(raw[:9]).reshape(3,3)
        ts.append(('head',pts.tolist(),head_colour(pts-OFFSET,raw[9])))

    # Recolour only stray light samples at the reviewed coat/sleeve/tail spots.
    # All geometry, cuffs, collar, inner skirt and boot/sock colours stay intact.
    def garment_colour(bone, points, ci):
        if garment_spot(bone, points, palette[ci]):
            return colour('navy')
        return ci
    qs.extend(q[:-1]+(garment_colour(q[0],quad_points(q),q[-1]),)
              for q in quads if q[0] not in ('head','hair_back','hair_locks'))
    ts.extend((b,p,garment_colour(b,np.asarray(p)-OFFSET,c))
              for b,p,c in tris if b not in ('head','hair_back','hair_locks'))

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

    # Colour-only polish reviewed against in-game screenshots (baked shading, coat spill, tie).
    from polish import polish
    qs, palette, ts, edits = polish(qs, palette, ts)
    (HERE / 'polish_edits.json').write_text(
        '{"edits": [\n' + ',\n'.join(json.dumps(e, separators=(',', ':')) for e in edits) + '\n]}\n')

    # Drop unused sampled shades; the retained face RGB is copied exactly, never clustered.
    used=sorted(set(q[-1] for q in qs)|set(t[-1] for t in ts))
    remap={old:new for new,old in enumerate(used)}
    qs=[q[:-1]+(remap[q[-1]],) for q in qs]
    ts=[(b,p,remap[c]) for b,p,c in ts]
    return qs,np.asarray([palette[c] for c in used]),ts,bones
