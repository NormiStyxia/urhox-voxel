#!/usr/bin/env python3
"""Wing sword (anime hard-edge) model generator.

Axes follow UrhoX: X right, Y up (blade tip +Y), Z depth, viewer at -Z.
Origin = grip centre (hand socket). Units: metres.

Material channel weights per triangle (r,g,b), remainder = grip:
  r = blade body   g = metal trim   b = core/gem (accent, glows)   rest = grip
Outputs:
  scripts/combat/models/WingSword.lua   compact data for the game
  art/weapon_gen/out/wingsword.json   full data for Blender preview
Run:  python3 -I art/weapon_gen/wingsword.py
"""
import json, math, os, runpy

TRACE = runpy.run_path(os.path.join(os.path.dirname(__file__), 'trace_wingsword.py'))
xy = TRACE['xy']

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT_LUA = os.path.join(ROOT, 'scripts', 'combat', 'models', 'WingSword.lua')
OUT_JSON = os.path.join(os.path.dirname(__file__), 'out', 'wingsword.json')

BLADE, BLADE_SHADOW = (1, 0, 0), (.72, 0, .28)
METAL, CORE, GRIP = (0, 1, 0), (0, 0, 1), (0, 0, 0)

tris = []   # {p:[3 pts], c:(r,g,b), shade, glow}


def sub(a, b): return (a[0]-b[0], a[1]-b[1], a[2]-b[2])
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def dot(a, b): return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]


def face(points, c, shade=1.0, glow=0.0, outward=(0, 0, -1)):
    """Fan triangulate a convex planar polygon. Winding is chosen so that the
    component-wise cross product (b-a)x(c-a) points along `outward` - the same
    convention as ForgeShowroomBlades.Face, which Urho treats as front-facing."""
    n = cross(sub(points[1], points[0]), sub(points[2], points[0]))
    if math.sqrt(dot(n, n)) < 1e-12:
        return
    flip = dot(n, outward) < 0
    for i in range(1, len(points)-1):
        t = (points[0], points[i+1], points[i]) if flip else (points[0], points[i], points[i+1])
        tris.append({'p': [list(q) for q in t], 'c': c, 'shade': shade, 'glow': glow})


def centroid2(poly):
    return (sum(p[0] for p in poly)/len(poly), sum(p[1] for p in poly)/len(poly))


def prism(poly, z0, z1, c, shade=1.0, glow=0.0, bevel=0.0, inset=0.16, bevel_shade=0.82, side_shade=0.74):
    """Extrude a convex XY polygon between z0<z1. bevel>0 adds a chamfer ring and
    a smaller flat cap on both faces (cap lies `bevel` further out)."""
    cx, cy = centroid2(poly)
    n = len(poly)
    full0 = [(p[0], p[1], z0) for p in poly]
    full1 = [(p[0], p[1], z1) for p in poly]
    for i in range(n):
        k = (i+1) % n
        mx, my = (poly[i][0]+poly[k][0])/2-cx, (poly[i][1]+poly[k][1])/2-cy
        face([full0[i], full0[k], full1[k], full1[i]], c, side_shade, glow, (mx, my, 0))
    if bevel <= 0:
        face(full0, c, shade, glow, (0, 0, -1))
        face(full1, c, shade, glow, (0, 0, 1))
        return
    ins = [(cx+(p[0]-cx)*(1-inset), cy+(p[1]-cy)*(1-inset)) for p in poly]
    cap0 = [(p[0], p[1], z0-bevel) for p in ins]
    cap1 = [(p[0], p[1], z1+bevel) for p in ins]
    for i in range(n):
        k = (i+1) % n
        mx, my = (poly[i][0]+poly[k][0])/2-cx, (poly[i][1]+poly[k][1])/2-cy
        face([full0[i], full0[k], cap0[k], cap0[i]], c, bevel_shade, glow, (mx, my, -1))
        face([full1[i], full1[k], cap1[k], cap1[i]], c, bevel_shade, glow, (mx, my, 1))
    face(cap0, c, shade, glow, (0, 0, -1))
    face(cap1, c, shade, glow, (0, 0, 1))


def gem(cx, cy, z, sign, hx, hy, h):
    """Half octahedron sitting on a plate surface at depth z, popping toward sign."""
    rim = [(cx-hx, cy, z), (cx, cy-hy, z), (cx+hx, cy, z), (cx, cy+hy, z)]
    peak = (cx, cy, z+sign*h)
    shades = [.78, .9, 1.0, .86]
    for i in range(4):
        face([rim[i], rim[(i+1) % 4], peak], CORE, shades[i], 1.0, ((rim[i][0]+rim[(i+1) % 4][0])/2-cx,
             (rim[i][1]+rim[(i+1) % 4][1])/2-cy, sign*.6))


def feather(root, tip, width, bulge=.38):
    dx, dy = tip[0]-root[0], tip[1]-root[1]
    L = math.hypot(dx, dy)
    nx, ny = -dy/L, dx/L
    mx, my = root[0]+dx*bulge, root[1]+dy*bulge
    return [root, (mx+nx*width, my+ny*width), tip, (mx-nx*width, my-ny*width)]


def ring_loft(rings, c_of_edge, shade_of_edge, glow_of_edge, close_bottom=None):
    """rings: list of point lists with identical length (last may be 1 point = tip)."""
    for j in range(len(rings)-1):
        a, b = rings[j], rings[j+1]
        n = len(a)
        for i in range(n):
            k = (i+1) % n
            mid = ((a[i][0]+a[k][0])/2, 0, (a[i][2]+a[k][2])/2)
            ci, si, gi = c_of_edge(i), shade_of_edge(i), glow_of_edge(i)
            if len(b) == 1:
                face([a[i], a[k], b[0]], ci, si, gi, mid)
            else:
                face([a[i], a[k], b[k], b[i]], ci, si, gi, mid)
    if close_bottom:
        face(rings[0], close_bottom[0], close_bottom[1], 0, (0, -1, 0))


# ---------------------------------------------------------------- layout (m)
GRIP_Y = (-.095, .095)
GUARD_Y = .215                 # guard centre height
BLADE_BASE = GUARD_Y + .07
TIP_Y = 1.62
POMMEL_BOTTOM = -.235

# 1) Sapphire slab: five long cuts, a shallow wandering Lambda ridge and
# four blue facets per face (two crown faces + two narrow shoulder bevels).
# White boundary vertices and the original front silhouette remain identical.
SAPPHIRE_CUTS = [
    # image y, extra crown height (m), lateral ridge / core half-width
    (1150, .004, -.22), (1000, .013, .26), (800, .005, -.25),
    (575, .014, .24), (350, .005, -.18), (180, .000, .00),
]

def blade():
    original = []
    for py, lx, rx, core_ratio, dp in TRACE['BLADE']:
        y = xy((949, py))[1]
        w = (rx-lx)*.5*TRACE['SCALE']
        d = dp*TRACE['SCALE']*1.10
        c = w*core_ratio
        a = w*(.10 if py==180 else .65)
        ring=[(-w,y,0),(-a,y,-d*.72),(-c,y,-d),(0,y,-d*1.025),
              (c,y,-d),(a,y,-d*.72),(w,y,0),(a,y,d*.72),
              (c,y,d),(0,y,d*1.025),(-c,y,d),(-a,y,d*.72)]
        original.append((py,ring))
    stations=sorted(set([p[0] for p in original]+[p[0] for p in SAPPHIRE_CUTS]),reverse=True)
    rings=[]
    for py in stations:
        # Interpolate the existing WHITE geometry, not a fresh width estimate.
        ring=None
        for sample,points in original:
            if py==sample: ring=list(points)
        if ring is None:
            for (pa,ra),(pb,rb) in zip(original,original[1:]):
                if pa>py>pb:
                    t=(pa-py)/(pa-pb)
                    ring=[tuple(u+(v-u)*t for u,v in zip(a,b)) for a,b in zip(ra,rb)]
                    break
        assert ring is not None
        if py<=1150:
            lift,shift=next((p[1],p[2]) for p in SAPPHIRE_CUTS if p[0]==py)
            d=abs(ring[2][2]);c=ring[4][0];y=ring[3][1]
            # The shoulders stay inside the old blue/white join. Crown height
            # varies by 4-14mm; the off-axis ridge prevents a straight hot seam.
            ring[2]=(-c,y,-d*.90);ring[4]=(c,y,-d*.93)
            ring[3]=(c*shift,y,-d-lift)
            ring[8]=(c,y,d*.90);ring[10]=(-c,y,d*.93)
            ring[9]=(-c*shift,y,d+lift)
        rings.append(ring)
    cols=[BLADE,(.60,0,.40),CORE,CORE,(.60,0,.40),BLADE,
          BLADE,(.60,0,.40),CORE,CORE,(.60,0,.40),BLADE]
    tones=[(.84,.97),(.96,.83),(.82,.94),(.98,.85),(.86,.96)]
    for j,(ra,rb) in enumerate(zip(rings,rings[1:])):
        mid=(stations[j]+stations[j+1])*.5
        left,right=.94,.96
        for cut in range(len(SAPPHIRE_CUTS)-1):
            if SAPPHIRE_CUTS[cut][0]>=mid>=SAPPHIRE_CUTS[cut+1][0]:
                left,right=tones[cut]
        # These are ordinary shade values, NOT a new UV/material-ID encoding.
        shades=[1,left,left,right,right,1,1,right,right,left,left,1]
        ring_loft([ra,rb],lambda i:cols[i],lambda i:shades[i],
                  lambda i:.35 if i in (2,3,8,9) else 0)
    face(rings[0],BLADE,.8,0,(0,-1,0))
    for i in range(12):
        a,b=rings[-1][i],rings[-1][(i+1)%12]
        face([a,b,(0,TIP_Y,0)],BLADE,1,0,((a[0]+b[0])/2,0,(a[2]+b[2])/2))

def signed_area(poly):
    return sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(poly,poly[1:]+poly[:1]))*.5

def turn(a,b,c):
    return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])

def ears(poly):
    """Ear clipping for concave traced outlines; returned indices are CCW."""
    idx=list(range(len(poly)))
    if signed_area(poly)<0: idx.reverse()
    out=[]
    while len(idx)>3:
        for j in range(len(idx)):
            a,b,c=idx[j-1],idx[j],idx[(j+1)%len(idx)]
            if turn(poly[a],poly[b],poly[c])<=1e-12: continue
            if any(min(turn(poly[a],poly[b],poly[k]),turn(poly[b],poly[c],poly[k]),
                       turn(poly[c],poly[a],poly[k]))>=-1e-12
                   for k in idx if k not in (a,b,c)): continue
            out.append((a,b,c));idx.pop(j);break
        else: raise ValueError('Non-simple trace polygon')
    out.append(tuple(idx))
    return out

def traced_plate(pixels, layer=0, ridge=None):
    """Closed, outward-wound thin gold plate. The depth field sweeps forward
    toward the feather tips (side-view arc); each layer has its own depth.
    No coplanar overlay; rear uses the same physical polygon, naturally mirrored.
    """
    poly=[xy(p) for p in pixels]
    if signed_area(poly)<0: poly.reverse()
    def depth(p):
        py=50+(1.62-p[1])/TRACE['SCALE']
        center=-max(0,1475-py)*.00024
        half=.011+layer*.002
        return center,half
    front=[];back=[]
    for p in poly:
        z,h=depth(p);front.append((*p,z-h));back.append((*p,z+h))
    for i in range(len(poly)):
        k=(i+1)%len(poly)
        dx,dy=poly[k][0]-poly[i][0],poly[k][1]-poly[i][1]
        face([front[i],front[k],back[k],back[i]],METAL,.66,0,(dy,-dx,0))
    if ridge is not None:
        r=xy(ridge)
        assert all(turn(poly[i],poly[(i+1)%len(poly)],r)>1e-9 for i in range(len(poly))), 'ridge outside polygon kernel'
        z,h=depth(r)
        for sign,edge in ((-1,front),(1,back)):
            peak=(*r,z+sign*(h+.009))
            # A narrow physical accent-metal rim separates overlapping feathers.
            cap=[]
            for point in edge:
                dx,dy=r[0]-point[0],r[1]-point[1]
                length=math.hypot(dx,dy)
                ratio=min(.12,.0020/length)
                cap.append((point[0]+dx*ratio,point[1]+dy*ratio,point[2]+sign*.001))
            for i in range(len(poly)):
                k=(i+1)%len(poly)
                face([edge[i],edge[k],cap[k],cap[i]],CORE,.20,0,(0,0,sign))
            for i in range(len(poly)):
                k=(i+1)%len(poly)
                tone=1.0 if poly[k][0]-poly[i][0]<0 else .82
                face([cap[i],cap[k],peak],METAL,tone,0,(0,0,sign))
    else:
        for ids in ears(poly):
            for sign,edge in ((-1,front),(1,back)):
                tone=1.0 if sum(poly[i][0] for i in ids)<0 else .84
                face([edge[i] for i in ids],METAL,tone,0,(0,0,sign))

# 2) Diamond collar, replacing the wide rectangular band across the blade.
def collar():
    cx,cy=xy((949,1368))
    poly=[xy(p) for p in [(949,1316),(979,1368),(949,1423),(919,1368)]]
    prism(poly,-.032,.032,METAL,1,0,bevel=.004,inset=.16)
    for sign in (-1,1):
        gem(cx,cy,sign*.036,sign,.015,.030,.013)

# 3) Concave central gold breastplate and long down-pointing keel.
def guard_core():
    traced_plate(TRACE['CORE'],layer=7)
    cx,cy=xy((946,1572))
    for sign in (-1,1):
        gem(cx,cy,sign*.025,sign,.022,.043,.027)
    poly=[xy(p) for p in [(949,1420),(983,1476),(948,1510),(914,1476)]]
    prism(poly,-.030,.030,METAL,1,0,bevel=.010,inset=.15)

# 4) Individually traced sharp feathers, no generic leaf/star primitive.
def wings():
    for k,(name,pixels,ridge) in enumerate(TRACE['FEATHERS']):
        traced_plate(pixels,layer=k if k<5 else k-5,ridge=ridge)

# 5) Grip: dark 8-gon wrap with banded shading + gold collars
def octagon(y, r, rot=math.pi/8):
    return [(r*math.sin(rot+i*math.pi/4), y, -r*math.cos(rot+i*math.pi/4)) for i in range(8)]

def grip():
    ys = [GRIP_Y[0], -.045, 0.0, .045, GRIP_Y[1]]
    rings = [octagon(y, .021) for y in ys]
    for j in range(len(rings)-1):
        sh = .86 if j % 2 == 0 else 1.0
        ring_loft(rings[j:j+2], lambda i: GRIP, lambda i, sh=sh: sh*(.92 if i % 2 else 1.0), lambda i: 0)
    for y0, y1 in ((GRIP_Y[1], GRIP_Y[1]+.02), (GRIP_Y[0]-.02, GRIP_Y[0])):
        ring_loft([octagon(y0, .027), octagon(y1, .027)], lambda i: METAL, lambda i: .92 if i % 2 else 1.0, lambda i: 0)
        face(octagon(y1, .027), METAL, .9, 0, (0, 1, 0))
        face(octagon(y0, .027), METAL, .8, 0, (0, -1, 0))

# 6) Pommel: gold diamond plate + gem
def pommel():
    poly = [(0, GRIP_Y[0]), (.034, -.142), (0, POMMEL_BOTTOM), (-.034, -.142)]
    prism(poly, -.020, .020, METAL, 1.0, 0, bevel=.005, inset=.18)
    for s in (-1, 1):
        gem(0, -.152, s*.025, s, .014, .022, .014)


for part in (blade, collar, wings, guard_core, grip, pommel):
    start = len(tris)
    part()
    for tri in tris[start:]: tri['part'] = part.__name__

# ------------------------------------------------------------------ export
lo = [min(q[a] for t in tris for q in t['p']) for a in range(3)]
hi = [max(q[a] for t in tris for q in t['p']) for a in range(3)]
meta = {
    'height': hi[1]-lo[1],
    'bounds': {'min': lo, 'max': hi},
    # sockets (metres, model space): grip centre = origin, blade tip, blade base
    'sockets': {'grip': [0, 0, 0], 'tip': [0, TIP_Y, 0], 'bladeBase': [0, xy((949,1443))[1], 0], 'pommel': [0, POMMEL_BOTTOM, 0]},
}

os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
with open(OUT_JSON, 'w') as f:
    json.dump({'meta': meta, 'tris': tris}, f)

Q = 10000   # 0.1 mm integer positions
pos, col = [], []
for t in tris:
    for q in t['p']:
        pos += [round(v*Q) for v in q]
    col += [round(t['c'][0]*100), round(t['c'][1]*100), round(t['c'][2]*100), round(t['shade']*100), round(t['glow']*100)]


def block(vals, per=27):
    return ',\n    '.join(','.join(str(v) for v in vals[i:i+per]) for i in range(0, len(vals), per))


os.makedirs(os.path.dirname(OUT_LUA), exist_ok=True)
with open(OUT_LUA, 'w') as f:
    f.write('-- GENERATED by art/weapon_gen/wingsword.py - do not hand edit.\n')
    f.write('-- Wing sword, anime hard-edge. Metres, origin = grip centre, tip +Y, viewer at -Z.\n')
    f.write('-- Per triangle: 9 positions (x,y,z of 3 verts, 1e-4 m ints) and 5 material ints:\n')
    f.write('--   r,g,b weights x100 (r blade, g metal, b core/gem, remainder grip), shade x100, glow x100.\n')
    f.write('return {\n')
    f.write(f'  name="wing_sword", scale={Q}, triangles={len(tris)},\n')
    f.write(f'  height={meta["height"]:.4f},\n')
    f.write('  bounds={min={%s},max={%s}},\n' % (','.join('%.4f' % v for v in lo), ','.join('%.4f' % v for v in hi)))
    f.write('  sockets={%s},\n' % ','.join('%s={%s}' % (k, ','.join('%.4f' % x for x in v)) for k, v in meta['sockets'].items()))
    f.write('  pos={\n    ' + block(pos) + '\n  },\n')
    f.write('  col={\n    ' + block(col, 25) + '\n  },\n}\n')

print('triangles', len(tris), 'height %.3f' % meta['height'], 'lua bytes', os.path.getsize(OUT_LUA))
