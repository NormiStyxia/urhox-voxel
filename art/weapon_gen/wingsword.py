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
import json, math, os, sys

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


def signed_area(poly):
    return sum(poly[i][0]*poly[(i+1) % len(poly)][1]-poly[(i+1) % len(poly)][0]*poly[i][1] for i in range(len(poly)))/2


def ear_clip(poly):
    """Triangulate a simple 2D polygon (any winding). Returns index triples."""
    idx = list(range(len(poly)))
    if signed_area(poly) < 0:
        idx.reverse()
    out = []

    def inside(p, a, b, c):
        d1 = (p[0]-b[0])*(a[1]-b[1])-(a[0]-b[0])*(p[1]-b[1])
        d2 = (p[0]-c[0])*(b[1]-c[1])-(b[0]-c[0])*(p[1]-c[1])
        d3 = (p[0]-a[0])*(c[1]-a[1])-(c[0]-a[0])*(p[1]-a[1])
        return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))
    guard = 0
    while len(idx) > 3 and guard < 1000:
        guard += 1
        for k in range(len(idx)):
            i0, i1, i2 = idx[k-1], idx[k], idx[(k+1) % len(idx)]
            a, b, c = poly[i0], poly[i1], poly[i2]
            if (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]) <= 1e-12:
                continue
            if any(inside(poly[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                continue
            out.append((i0, i1, i2)); idx.pop(k); break
        else:
            raise ValueError('ear clipping failed (polygon not simple?)')
    out.append((idx[0], idx[1], idx[2]))
    return out


def face_poly(points, c, shade, glow, outward):
    """Planar cap with constant z: triangulate in XY, orient each triangle to `outward`."""
    for i0, i1, i2 in ear_clip([(q[0], q[1]) for q in points]):
        face([points[i0], points[i1], points[i2]], c, shade, glow, outward)


def edge_outward(poly, i):
    k = (i+1) % len(poly)
    dx, dy = poly[k][0]-poly[i][0], poly[k][1]-poly[i][1]
    return (dy, -dx) if signed_area(poly) > 0 else (-dy, dx)


def prism(poly, z0, z1, c, shade=1.0, glow=0.0, bevel=0.0, inset=0.16, bevel_shade=0.82, side_shade=0.74):
    """Extrude a simple XY polygon between z0<z1. bevel>0 adds a chamfer ring and
    a smaller flat cap on both faces (cap lies `bevel` further out)."""
    cx, cy = centroid2(poly)
    n = len(poly)
    full0 = [(p[0], p[1], z0) for p in poly]
    full1 = [(p[0], p[1], z1) for p in poly]
    for i in range(n):
        k = (i+1) % n
        ox, oy = edge_outward(poly, i)
        face([full0[i], full0[k], full1[k], full1[i]], c, side_shade, glow, (ox, oy, 0))
    if bevel <= 0:
        face_poly(full0, c, shade, glow, (0, 0, -1))
        face_poly(full1, c, shade, glow, (0, 0, 1))
        return
    ins = [(cx+(p[0]-cx)*(1-inset), cy+(p[1]-cy)*(1-inset)) for p in poly]
    cap0 = [(p[0], p[1], z0-bevel) for p in ins]
    cap1 = [(p[0], p[1], z1+bevel) for p in ins]
    for i in range(n):
        k = (i+1) % n
        ox, oy = edge_outward(poly, i)
        face([full0[i], full0[k], cap0[k], cap0[i]], c, bevel_shade, glow, (ox, oy, -1))
        face([full1[i], full1[k], cap1[k], cap1[i]], c, bevel_shade, glow, (ox, oy, 1))
    face_poly(cap0, c, shade, glow, (0, 0, -1))
    face_poly(cap1, c, shade, glow, (0, 0, 1))


def gem(cx, cy, z, sign, hx, hy, h):
    """Half octahedron sitting on a plate surface at depth z, popping toward sign."""
    rim = [(cx-hx, cy, z), (cx, cy-hy, z), (cx+hx, cy, z), (cx, cy+hy, z)]
    peak = (cx, cy, z+sign*h)
    shades = [.78, .9, 1.0, .86]
    for i in range(4):
        face([rim[i], rim[(i+1) % 4], peak], CORE, shades[i], 1.0, ((rim[i][0]+rim[(i+1) % 4][0])/2-cx,
             (rim[i][1]+rim[(i+1) % 4][1])/2-cy, sign*.6))


def feather(root, tip, width, bend=0.10):
    """Curved leaf: spine bows upward by bend*length, widest ~40% along, soft rounded tip."""
    dx, dy = tip[0]-root[0], tip[1]-root[1]
    L = math.hypot(dx, dy)
    nx, ny = -dy/L, dx/L
    if ny < 0:
        nx, ny = -nx, -ny           # bow toward +Y
    def spine(t):
        k = bend*L*math.sin(math.pi*t)
        return (root[0]+dx*t+nx*k, root[1]+dy*t+ny*k)
    def side(t, sgn):
        e = .001
        a, b = spine(max(t-e, 0)), spine(min(t+e, 1))
        tx, ty = b[0]-a[0], b[1]-a[1]
        tl = math.hypot(tx, ty)
        px, py = -ty/tl, tx/tl
        w = width*{.12: .45, .32: .92, .52: 1.0, .72: .78, .90: .38}[t]
        q = spine(t)
        return (q[0]+px*w*sgn, q[1]+py*w*sgn)
    ts = [.12, .32, .52, .72, .90]
    return [root] + [side(t, 1) for t in ts] + [tip] + [side(t, -1) for t in reversed(ts)]


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

# 1) Blade: flat hex section with a flat glowing core strip on each face
def blade():
    # (y, half width, half thickness)
    stations = [(BLADE_BASE, .064, .012), (BLADE_BASE+.10, .054, .0115), (1.25, .054, .0105),
                (1.31, .0605, .0105), (TIP_Y-.0, 0, 0)]
    rings = []
    for y, w, d in stations[:-1]:
        c = .36*w
        rings.append([(-w, y, 0), (-c, y, -d), (c, y, -d), (w, y, 0), (c, y, d), (-c, y, d)])
    rings.append([(0, stations[-1][0], 0)])
    cols = [BLADE_SHADOW, CORE, BLADE, BLADE, CORE, BLADE_SHADOW]   # P0P1,P1P2,P2P3,P3P4,P4P5,P5P0
    shd = [.88, .95, 1.0, 1.0, .95, .88]
    glo = [0, .35, 0, 0, .35, 0]
    ring_loft(rings, lambda i: cols[i], lambda i: shd[i], lambda i: glo[i])

# 2) Collar over the blade root + small gem
def collar():
    y0 = GUARD_Y+.035
    poly = [(-.070, y0), (.070, y0), (.062, y0+.075), (-.062, y0+.075)]
    prism(poly, -.014, .014, METAL, 1.0, 0, bevel=.003, inset=.12)
    for s in (-1, 1):
        gem(0, y0+.052, s*(.014+.003), s, .015, .019, .010)

# 3) Centre plate with a long downward spike + gem
def guard_core():
    g = GUARD_Y
    poly = [(0, g+.07), (.042, g+.012), (.034, g-.085), (0, g-.17), (-.034, g-.085), (-.042, g+.012)]
    prism(poly, -.026, .026, METAL, 1.0, 0, bevel=.004, inset=.14)
    for s in (-1, 1):
        gem(0, g-.045, s*.030, s, .018, .030, .012)

# 4) Asymmetric feather wings: tall swept-up left, short flat right
WING_L = [((-.022, .030), (-.172, .310), .052, .10, 1.00),
          ((-.022, .012), (-.272, .158), .056, .09, .93),
          ((-.022, -.008), (-.262, -.030), .050, .08, .87),
          ((-.020, -.030), (-.168, -.128), .040, .07, .81)]
WING_R = [((.022, .026), (.212, .118), .046, .08, 1.00),
          ((.022, .000), (.252, -.034), .048, .07, .92),
          ((.020, -.024), (.138, -.138), .040, .06, .84)]

def wings():
    for k, (root, tip, w, bend, sh) in enumerate(WING_L + WING_R):
        poly = [(p[0], GUARD_Y+p[1]) for p in feather(root, tip, w, bend)]
        # unique depth per feather: overlapping layers never share a plane
        zc = (k-3)*.0032
        prism(poly, -.0085+zc, .0085+zc, METAL, sh, 0)

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
    prism(poly, -.012, .012, METAL, 1.0, 0, bevel=.004, inset=.18)
    for s in (-1, 1):
        gem(0, -.152, s*.016, s, .013, .020, .010)


for part in (blade, collar, guard_core, wings, grip, pommel):
    part()

# ------------------------------------------------------------------ export
lo = [min(q[a] for t in tris for q in t['p']) for a in range(3)]
hi = [max(q[a] for t in tris for q in t['p']) for a in range(3)]
meta = {
    'height': hi[1]-lo[1],
    'bounds': {'min': lo, 'max': hi},
    # sockets (metres, model space): grip centre = origin, blade tip, blade base
    'sockets': {'grip': [0, 0, 0], 'tip': [0, TIP_Y, 0], 'bladeBase': [0, GUARD_Y+.11, 0], 'pommel': [0, POMMEL_BOTTOM, 0]},
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
