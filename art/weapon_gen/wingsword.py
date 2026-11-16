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

# 1) Blade: flat hex section with a flat glowing core strip on each face
def blade():
    # (y, half width, half thickness)
    stations = [(BLADE_BASE, .064, .014), (BLADE_BASE+.10, .054, .0135), (1.25, .054, .0125),
                (1.31, .0605, .0125), (TIP_Y-.0, 0, 0)]
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
    prism(poly, -.018, .018, METAL, 1.0, 0, bevel=.004, inset=.12)
    for s in (-1, 1):
        gem(0, y0+.052, s*(.018+.004), s, .017, .021, .016)

# 3) Centre plate with a long downward spike + gem
def guard_core():
    g = GUARD_Y
    poly = [(0, g+.07), (.042, g+.012), (.034, g-.085), (0, g-.17), (-.034, g-.085), (-.042, g+.012)]
    prism(poly, -.034, .034, METAL, 1.0, 0, bevel=.006, inset=.14)
    for s in (-1, 1):
        gem(0, g-.045, s*.040, s, .019, .032, .024)

# 4) Asymmetric feather wings: tall swept-up left, short flat right
WING_L = [((-.022, .030), (-.172, .310), .036, 1.00),
          ((-.022, .012), (-.272, .158), .040, .93),
          ((-.022, -.008), (-.262, -.030), .036, .87),
          ((-.020, -.030), (-.168, -.128), .028, .81)]
WING_R = [((.022, .026), (.212, .118), .032, 1.00),
          ((.022, .000), (.252, -.034), .034, .92),
          ((.020, -.024), (.138, -.138), .028, .84)]

def wings():
    for k, (root, tip, w, sh) in enumerate(WING_L + WING_R):
        poly = [(p[0], GUARD_Y+p[1]) for p in feather(root, tip, w, .42)]
        # unique depth per feather: overlapping layers never share a plane
        zc = ((k % 4)-1.5)*.0042
        prism(poly, -.017+zc, .017+zc, METAL, sh, 0, bevel=.005, inset=.20)

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
