"""Thorn-branch flower bow (Castorice palette) - procedural Blender model + material preview.

Built against the orthographic three-view art/weapons_2d/castorice_bow/thornbow_threeview_v1.jpg.
All landmark coordinates below were measured on that sheet's SIDE view and are normalised by the
total bow height L (x to the right = string side, y downwards from the top flower).

Blender axes: X = side-view horizontal (string at +X, crystal points to -X / the target),
Z = up, Y = depth (front-view horizontal). Origin = grip centre.

Run (from project root):
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -P art/weapon_gen/thornbow_blender.py -- [stills|anim] [outdir]
"""
import bpy, bmesh, math, random, sys, os
from mathutils import Vector, Matrix

ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
MODE = ARGS[0] if ARGS else 'stills'
OUT = ARGS[1] if len(ARGS) > 1 else 'art/weapons_2d/castorice_bow/blender'
os.makedirs(OUT, exist_ok=True)
DETAIL = 1.0          # 1 = preview density; lower for a game LOD later
L = 1.0               # metres; fitted to the in-game bow at integration time
YC = 0.489            # sheet y of the grip centre (top/bottom mirror line)
XC = 0.160            # sheet x of the grip centre
rng = random.Random(7)


def P(x, y, z=0.0):
    """Sheet coordinates (x right, y down, z depth; all /L) -> Blender world."""
    return Vector(((x - XC) * L, z * L, (YC - y) * L))


def mirror_y(y):
    return 2 * YC - y


# ---------------------------------------------------------------- curves
def catmull(ctrl, n):
    pts = [ctrl[0]] + list(ctrl) + [ctrl[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        steps = max(2, n // (len(ctrl) - 1))
        for k in range(steps):
            t = k / steps
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(ctrl[-1])
    return out


def resample(pts, n):
    d = [0.0]
    for i in range(1, len(pts)):
        d.append(d[-1] + (pts[i] - pts[i - 1]).length)
    total = d[-1]
    out, j = [], 0
    for k in range(n):
        s = total * k / (n - 1)
        while j < len(d) - 2 and d[j + 1] < s:
            j += 1
        seg = d[j + 1] - d[j]
        t = 0 if seg < 1e-9 else (s - d[j]) / seg
        out.append(pts[j].lerp(pts[j + 1], t))
    return out


def curve(ctrl, n):
    return resample(catmull(ctrl, n * 4), n)


# ---------------------------------------------------------------- mesh builders
class Builder:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.tint = self.bm.verts.layers.float_color.new('tint')

    def vert(self, co, tint):
        v = self.bm.verts.new(co)
        v[self.tint] = (tint[0], tint[1], tint[2], tint[3] if len(tint) > 3 else 1.0)
        return v

    def tube(self, pts, radii, seg, tint_fn=lambda t: (0, 0, 0), cap=True, jitter=0.0, rmod=None):
        """Rotation-minimising frames; tip collapses to a point when its radius is ~0."""
        n = len(pts)
        tang = []
        for i in range(n):
            a = pts[max(0, i - 1)]
            b = pts[min(n - 1, i + 1)]
            tang.append((b - a).normalized())
        ref = Vector((0, 1, 0)) if abs(tang[0].y) < 0.9 else Vector((1, 0, 0))
        nrm = (ref - tang[0] * ref.dot(tang[0])).normalized()
        rings = []
        for i in range(n):
            if i:
                nrm = (nrm - tang[i] * nrm.dot(tang[i]))
                nrm = nrm.normalized() if nrm.length > 1e-6 else nrm
            bin_ = tang[i].cross(nrm)
            t = i / (n - 1)
            r = radii[i]
            if r < 1e-5:
                rings.append([self.vert(pts[i], tint_fn(t))])
                continue
            ring = []
            for k in range(seg):
                a = 2 * math.pi * k / seg
                rr = r * (1 + jitter * (rng.random() - 0.5)) * (rmod(t, a) if rmod else 1.0)
                ring.append(self.vert(pts[i] + (nrm * math.cos(a) + bin_ * math.sin(a)) * rr, tint_fn(t)))
            rings.append(ring)
        for i in range(n - 1):
            A, B = rings[i], rings[i + 1]
            if len(A) == 1 and len(B) == 1:
                continue
            if len(B) == 1:
                for k in range(len(A)):
                    self.bm.faces.new((A[k], A[(k + 1) % len(A)], B[0]))
            elif len(A) == 1:
                for k in range(len(B)):
                    self.bm.faces.new((A[0], B[(k + 1) % len(B)], B[k]))
            else:
                for k in range(seg):
                    self.bm.faces.new((A[k], A[(k + 1) % seg], B[(k + 1) % seg], B[k]))
        if cap and len(rings[0]) > 1:
            c = self.vert(pts[0], tint_fn(0))
            for k in range(seg):
                self.bm.faces.new((rings[0][(k + 1) % seg], rings[0][k], c))

    def finish(self, mat, smooth=True):
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for p in me.polygons:
            p.use_smooth = smooth
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        me.materials.append(mat)
        return ob


def taper(n, r0, r1, power=1.0, tip=True):
    out = []
    for i in range(n):
        t = i / (n - 1)
        out.append(r0 + (r1 - r0) * (t ** power))
    if tip:
        out[-1] = 0.0
    return out


# ---------------------------------------------------------------- materials
def node(nt, kind, loc, **inputs):
    nd = nt.nodes.new(kind)
    nd.location = loc
    for k, v in inputs.items():
        if k in nd.inputs:
            nd.inputs[k].default_value = v
    return nd


def principled(name, **inputs):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes['Principled BSDF']
    for k, v in inputs.items():
        if k in b.inputs:
            b.inputs[k].default_value = v
    return m, nt, b


def mat_wood():
    # Ink-black violet bark: noisy dark base, faint lacquer coat, violet bleed toward the flowers.
    m, nt, b = principled('Wood_Bark', Roughness=0.72, **{'Coat Weight': 0.06, 'Coat Roughness': 0.3})
    tc = node(nt, 'ShaderNodeTexCoord', (-1100, 0))
    mp = node(nt, 'ShaderNodeMapping', (-900, 0))
    mp.inputs['Scale'].default_value = (55, 55, 18)
    nt.links.new(tc.outputs['Object'], mp.inputs['Vector'])
    nz = node(nt, 'ShaderNodeTexNoise', (-700, 0), Scale=1.0, Detail=6.0, Roughness=0.62)
    nt.links.new(mp.outputs['Vector'], nz.inputs['Vector'])
    ramp = nt.nodes.new('ShaderNodeValToRGB'); ramp.location = (-480, 120)
    ramp.color_ramp.elements[0].position = 0.35; ramp.color_ramp.elements[0].color = (0.009, 0.006, 0.015, 1)
    ramp.color_ramp.elements[1].position = 0.75; ramp.color_ramp.elements[1].color = (0.046, 0.030, 0.070, 1)
    nt.links.new(nz.outputs['Fac'], ramp.inputs['Fac'])
    at = node(nt, 'ShaderNodeAttribute', (-700, 300)); at.attribute_name = 'tint'
    sep = node(nt, 'ShaderNodeSeparateColor', (-480, 330))
    nt.links.new(at.outputs['Color'], sep.inputs['Color'])
    mix = node(nt, 'ShaderNodeMix', (-220, 200)); mix.data_type = 'RGBA'
    mix.inputs[7].default_value = (0.13, 0.045, 0.28, 1)   # violet bleed
    nt.links.new(sep.outputs['Red'], mix.inputs['Factor'])
    nt.links.new(ramp.outputs['Color'], mix.inputs[6])
    nt.links.new(mix.outputs[2], b.inputs['Base Color'])
    em = node(nt, 'ShaderNodeMath', (-220, -40)); em.operation = 'MULTIPLY'; em.inputs[1].default_value = 0.12
    nt.links.new(sep.outputs['Red'], em.inputs[0])
    b.inputs['Emission Color'].default_value = (0.55, 0.30, 0.95, 1)
    nt.links.new(em.outputs['Value'], b.inputs['Emission Strength'])
    bump = node(nt, 'ShaderNodeBump', (-220, -220), Strength=0.55, Distance=0.002)
    nt.links.new(nz.outputs['Fac'], bump.inputs['Height'])
    nt.links.new(bump.outputs['Normal'], b.inputs['Normal'])
    return m


def mat_flower():
    # Glowing lilac lotus: deeper violet at the petal base, almost white tips, translucent and self-lit.
    m, nt, b = principled('Flower_Petal', Roughness=0.45, **{'Subsurface Weight': 0.35, 'Transmission Weight': 0.25,
                                                             'Subsurface Radius': (0.6, 0.4, 0.9)})
    m.use_backface_culling = False
    at = node(nt, 'ShaderNodeAttribute', (-700, 200)); at.attribute_name = 'tint'
    sep = node(nt, 'ShaderNodeSeparateColor', (-500, 200))
    nt.links.new(at.outputs['Color'], sep.inputs['Color'])
    ramp = nt.nodes.new('ShaderNodeValToRGB'); ramp.location = (-300, 250)
    e = ramp.color_ramp.elements
    e[0].position = 0.0; e[0].color = (0.30, 0.11, 0.72, 1)
    e[1].position = 1.0; e[1].color = (0.82, 0.72, 1.0, 1)
    mid = e.new(0.5); mid.color = (0.55, 0.34, 0.95, 1)
    nt.links.new(sep.outputs['Red'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], b.inputs['Base Color'])
    nt.links.new(ramp.outputs['Color'], b.inputs['Emission Color'])
    inv = node(nt, 'ShaderNodeMath', (-300, 0)); inv.operation = 'SUBTRACT'; inv.inputs[0].default_value = 1.0
    nt.links.new(sep.outputs['Red'], inv.inputs[1])
    gl = node(nt, 'ShaderNodeMath', (-120, 0)); gl.operation = 'MULTIPLY_ADD'
    gl.inputs[1].default_value = 0.55; gl.inputs[2].default_value = 0.10
    nt.links.new(inv.outputs['Value'], gl.inputs[0])
    nt.links.new(gl.outputs['Value'], b.inputs['Emission Strength'])
    return m


def mat_crystal():
    # Clear amethyst: near-fully transmissive, very low roughness; colour deepens through a soft low-frequency
    # cloud (inclusions) rather than hard cell lines, and brightens at grazing angles like a polished gem.
    m, nt, b = principled('Crystal_Gem', Roughness=0.05, IOR=1.56,
                          **{'Transmission Weight': 0.96, 'Coat Weight': 0.0, 'Specular IOR Level': 0.75})
    tc = node(nt, 'ShaderNodeTexCoord', (-1100, 0))
    nz = node(nt, 'ShaderNodeTexNoise', (-800, 80), Scale=9.0, Detail=3.0, Roughness=0.5)
    nt.links.new(tc.outputs['Object'], nz.inputs['Vector'])
    ramp = nt.nodes.new('ShaderNodeValToRGB'); ramp.location = (-520, 120)
    e = ramp.color_ramp.elements
    e[0].position = 0.30; e[0].color = (0.16, 0.03, 0.62, 1)
    e[1].position = 0.75; e[1].color = (0.52, 0.22, 0.96, 1)
    nt.links.new(nz.outputs['Fac'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], b.inputs['Base Color'])
    lw = node(nt, 'ShaderNodeLayerWeight', (-500, -380), Blend=0.35)
    pw = node(nt, 'ShaderNodeMath', (-300, -380)); pw.operation = 'POWER'; pw.inputs[1].default_value = 2.4
    nt.links.new(lw.outputs['Facing'], pw.inputs[0])
    ma = node(nt, 'ShaderNodeMath', (-120, -380)); ma.operation = 'MULTIPLY_ADD'
    ma.inputs[1].default_value = 1.1; ma.inputs[2].default_value = 0.10
    nt.links.new(pw.outputs['Value'], ma.inputs[0])
    nt.links.new(ma.outputs['Value'], b.inputs['Emission Strength'])
    nt.links.new(ramp.outputs['Color'], b.inputs['Emission Color'])
    if hasattr(m, 'use_raytrace_refraction'):
        m.use_raytrace_refraction = True
    if hasattr(m, 'thickness_mode'):
        m.thickness_mode = 'SLAB'
    m.use_backface_culling = False
    return m


def mat_emit(name, color, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = node(nt, 'ShaderNodeOutputMaterial', (300, 0))
    em = node(nt, 'ShaderNodeEmission', (0, 0), Color=color, Strength=strength)
    nt.links.new(em.outputs['Emission'], out.inputs['Surface'])
    return m


def mat_sand():
    # Emission coloured by the per-vertex tint; tint alpha fades streak tails to transparent.
    m = bpy.data.materials.new('Sand_Grain')
    m.use_nodes = True
    if hasattr(m, 'surface_render_method'):
        m.surface_render_method = 'BLENDED'
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = node(nt, 'ShaderNodeOutputMaterial', (500, 0))
    at = node(nt, 'ShaderNodeAttribute', (-300, 0)); at.attribute_name = 'tint'
    em = node(nt, 'ShaderNodeEmission', (100, 60), Strength=1.7)
    tr = node(nt, 'ShaderNodeBsdfTransparent', (100, -80))
    mx = node(nt, 'ShaderNodeMixShader', (300, 0))
    nt.links.new(at.outputs['Color'], em.inputs['Color'])
    nt.links.new(at.outputs['Alpha'], mx.inputs['Fac'])
    nt.links.new(tr.outputs['BSDF'], mx.inputs[1])
    nt.links.new(em.outputs['Emission'], mx.inputs[2])
    nt.links.new(mx.outputs['Shader'], out.inputs['Surface'])
    return m


def mat_cloth():
    m, nt, b = principled('Grip_Cloth', Roughness=0.85, **{'Base Color': (0.075, 0.042, 0.125, 1), 'Sheen Weight': 0.3,
                                                         'Sheen Tint': (0.7, 0.55, 1.0, 1)})
    tc = node(nt, 'ShaderNodeTexCoord', (-900, 0))
    wv = node(nt, 'ShaderNodeTexWave', (-650, 0), Scale=22.0, Distortion=1.5)
    nt.links.new(tc.outputs['Object'], wv.inputs['Vector'])
    bump = node(nt, 'ShaderNodeBump', (-300, -150), Strength=0.25, Distance=0.002)
    nt.links.new(wv.outputs['Fac'], bump.inputs['Height'])
    nt.links.new(bump.outputs['Normal'], b.inputs['Normal'])
    return m


# ---------------------------------------------------------------- the bow
def limb_ctrl(sign):
    """Measured centreline of the main branch, grip centre -> limb tip (upper limb; sign=-1 mirrors)."""
    pts = [(0.160, 0.489), (0.150, 0.430), (0.137, 0.395), (0.118, 0.350), (0.121, 0.300), (0.148, 0.258),
           (0.193, 0.215), (0.238, 0.168), (0.265, 0.122), (0.276, 0.080)]
    return [(x, y if sign > 0 else mirror_y(y)) for x, y in pts]


def nearest_index(pts, target):
    best, bi = 1e9, 0
    for i, p in enumerate(pts):
        d = (p - target).length
        if d < best:
            best, bi = d, i
    return bi



TRACE = None
try:
    import json
    _tp = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out', 'thornbow_trace.json')
    TRACE = json.load(open(_tp))
except Exception as exc:
    print('no trace json', exc)

BR_SCALE = float(os.environ.get('TB_RAD_SCALE', 1.22))     # branch thickness vs the traced silhouette
FL_SCALE = float(os.environ.get('TB_FLOWER_SCALE', 1.9)) # lotus petal length vs the traced blob radius


def np_median(a):
    a = sorted(a)
    return a[len(a) // 2] if a else 0.0


def build_wood_from_trace(wb, flowers, seg_main, seg_thin):
    """Branches = tubes along the traced skeleton, radius from the silhouette (1:1 with the side view);
    depth from the front view; free ends taper to points; flowers sit on stems at the traced blobs."""
    B = TRACE['branches']
    grip_band = 0.069

    def zfun(x, y):
        # depth budget grows away from the grip, tapers at the tips; deterministic weave
        amp = 0.030 * min(1.0, max(0.0, (abs(y - YC) - 0.05) / 0.18)) * min(1.0, (0.50 - abs(y - YC)) / 0.18 + 0.35)
        return amp * math.sin(9.1 * x + 6.7 * y + 1.3 * math.sin(13.0 * y))

    # junction clustering (endpoints closer than 0.012 L share one depth + a hub sphere)
    ends = []
    for bi, br in enumerate(B):
        ends.append((bi, 0, br['pts'][0])); ends.append((bi, 1, br['pts'][-1]))
    hubs = []
    for bi, k, pt in ends:
        for h in hubs:
            if math.dist(h['p'], pt) < 0.022:
                h['m'].append((bi, k)); h['r'] = max(h['r'], float(np_median(B[bi]['rad'][1:4] if k == 0 else B[bi]['rad'][-4:-1]))); break
        else:
            hubs.append(dict(p=pt, m=[(bi, k)], r=float(np_median(B[bi]['rad'][1:4] if k == 0 else B[bi]['rad'][-4:-1]))))
    hub_of = {}
    for hi, h in enumerate(hubs):
        for m in h['m']:
            hub_of[m] = hi
    free = {}
    for hi, h in enumerate(hubs):
        for bi, k in h['m']:
            free[(bi, k)] = len(h['m']) == 1
    for bi, br in enumerate(B):
        pts, rad = br['pts'], br['rad']
        n = len(pts)
        if n < 3:
            continue
        zs = []
        z0 = zfun(*hubs[hub_of[(bi, 0)]]['p'])
        z1 = zfun(*hubs[hub_of[(bi, 1)]]['p'])
        for i, (x, y) in enumerate(pts):
            t = i / (n - 1)
            zs.append(z0 + (z1 - z0) * (t * t * (3 - 2 * t)) + 0.35 * zfun(x + 0.5, y))
        P3 = [P(x, y, z) for (x, y), z in zip(pts, zs)]
        for end, idx_ in ((0, 0), (1, n - 1)):          # snap ends onto their hub so tubes connect
            hb_ = hubs[hub_of[(bi, end)]]
            if len(hb_['m']) > 1:
                P3[idx_] = P(hb_['p'][0], hb_['p'][1], zfun(*hb_['p']))
        P3 = curve(P3, max(n * 2, 12))
        m = len(P3)
        def lin(i):
            f = i * (n - 1) / (m - 1)
            j = min(n - 2, int(f))
            return rad[j] + (rad[j + 1] - rad[j]) * (f - j)
        rr = [max(0.0022, lin(i)) * L * BR_SCALE for i in range(m)]
        # light smoothing so the silhouette radius never ribs the tube
        for _ in range(3):
            rr = [rr[0]] + [(rr[i - 1] + 2 * rr[i] + rr[i + 1]) / 4 for i in range(1, m - 1)] + [rr[-1]]
        # taper free tips to a point over the last 30 %
        for k, end in ((0, 0), (1, 1)):
            if free.get((bi, end)):
                for i in range(m):
                    t = i / (m - 1) if end == 1 else 1 - i / (m - 1)
                    if t > 0.70:
                        rr[i] *= max(0.0, 1 - (t - 0.70) / 0.30) ** 0.9
        if free.get((bi, 1)):
            rr[-1] = 0.0
        if free.get((bi, 0)):
            rr[0] = 0.0
        wb.tube(P3, rr, seg_main if max(rr) > 0.007 * L else seg_thin,
                lambda t, bi=bi: (0.0, 0, 0), cap=False, jitter=0.015)
        br['_p3'] = P3; br['_rr'] = rr
    # hub spheres hide the seams between tubes
    for h in hubs:
        if len(h['m']) < 3:
            continue
        x, y = h['p']
        c = P(x, y, zfun(x, y))
        res = bmesh.ops.create_icosphere(wb.bm, subdivisions=2, radius=h['r'] * L * BR_SCALE * 1.0, matrix=Matrix.Translation(c))
        for v in res['verts']:
            v[wb.tint] = (0.0, 0.0, 0.0, 1.0)
    # flowers on stems: nearest branch point -> traced flower centre
    allp = []
    for br in B:
        for q, r_ in zip(br.get('_p3', []), br.get('_rr', [])):
            allp.append((q, r_))
    for f in TRACE['flowers']:
        fc = P(f['x'], f['y'], f['z'])
        best = min(allp, key=lambda qr: (qr[0] - fc).length)
        q0, r0 = best
        d = fc - q0
        if d.length > 0.012 * L:
            nrm = Vector((-d.z, 0, d.x)).normalized() * (0.18 * d.length)
            if nrm.x * (fc.x - XC * 0) < 0:
                nrm = -nrm
            S = curve([q0, q0 + d * 0.33 + nrm, q0 + d * 0.72 + nrm * 0.55, fc - d.normalized() * 0.010 * L], 14)
            wb.tube(S, taper(len(S), max(r0 * 0.85, 0.0055 * L), 0.0036 * L, 1.0), seg_thin, lambda t: (t * 0.5, 0, 0))
        inplane = d.normalized() if d.length > 1e-6 else Vector((0, 0, 1))
        facing = Vector((0, -1.0 if len(flowers) % 3 else 1.0, 0))      # blooms open toward the side camera (mostly)
        axis = (inplane * 0.45 + facing * 0.90).normalized()
        flowers.append((fc, axis, f['radius'] * L * FL_SCALE))


def build_bow():
    wood, flower_m, crystal_m = mat_wood(), mat_flower(), mat_crystal()
    core_m = mat_emit('Crystal_Core', (0.34, 0.10, 0.95, 1), 2.4)
    string_m = mat_emit('Bow_String', (1.0, 0.36, 0.90, 1), 1.6)
    stamen_m = mat_emit('Flower_Heart', (1.0, 0.80, 1.0, 1), 2.2)
    cloth_m = mat_cloth()

    wood_b = Builder('Wood')
    flower_b = Builder('Flowers')
    hearts = Builder('FlowerHearts')
    grip_zone = 0.069 * L   # |z| inside this stays smooth: no twigs or thorns in the hand

    def grip_safe(p):
        return abs(p.z) > grip_zone + 0.012 * L

    flowers = []          # (position, outward axis, size)
    seg_main = max(6, int(10 * DETAIL))
    seg_thin = max(4, int(7 * DETAIL))
    gem_base_x, gem_tip_x = 0.120, 0.004
    tips = {1: P(0.2736, 0.013), -1: P(0.2736, 0.992)}          # string nocks (measured on the sheet)
    build_wood_from_trace(wood_b, flowers, seg_main, seg_thin)

    wood_ob = wood_b.finish(wood)

    # ---- flowers
    for pos, axis, size in flowers:
        lotus(flower_b, hearts, pos, axis, size)
    flower_b.finish(flower_m)
    hearts.finish(stamen_m)

    # ---- grip wrap (follows the bow arc between the grip zone ends)
    A = curve([P(x, y) for x, y in limb_ctrl(-1)][::-1][-4:] + [P(x, y) for x, y in limb_ctrl(1)][1:4], 40)
    G = [p for p in A if abs(p.z) <= grip_zone]
    grip = Builder('GripWrap')
    Gd = curve(G, 48)
    def band(t, a):
        f = (a / (2 * math.pi) + t * 6.0) % 1.0          # 6 diagonal turns of strap
        return 1.0 + 0.085 * (f ** 0.6) - 0.03           # each strap rises then drops onto the next
    grip.tube(Gd, [0.0232 * L] * len(Gd), max(10, int(20 * DETAIL)), cap=True, rmod=band)
    # two binding rings
    for p_i in (0, len(G) - 1):
        p = G[p_i]
        tng = (G[min(len(G) - 1, p_i + 1)] - G[max(0, p_i - 1)]).normalized()
        side = tng.cross(Vector((0, 1, 0))).normalized()
        ring = [p + (side * math.cos(a) + Vector((0, 1, 0)) * math.sin(a)) * 0.0225 * L
                for a in [2 * math.pi * k / 24 for k in range(25)]]
        ring = [p + (q - p) * (0.0262 / 0.0225) for q in ring]
        grip.tube(ring, [0.0032 * L] * 25, 6, cap=False)
    grip.finish(cloth_m)

    # ---- crystal (long faceted shard pointing at the target) + inner glow core
    gem(P(gem_tip_x - 0.008, YC), P(gem_base_x + 0.020, YC), 0.030 * L, 0.030 * L, crystal_m, 'Crystal', 1.0)
    gem(P(gem_tip_x - 0.008, YC), P(gem_base_x + 0.020, YC), 0.030 * L, 0.030 * L, core_m, 'CrystalCore', 0.52)

    # ---- string (nocks at the measured limb tips)
    top, bottom = tips[1], tips[-1]
    s = Builder('String')
    s.tube([top.lerp(bottom, k / 30) for k in range(31)], [0.0016 * L] * 31, 6, cap=True)
    s.finish(string_m)
    return wood_ob


def lotus(fb, hb, pos, axis, size):
    axis = axis.normalized()
    ref = Vector((0, 1, 0)) if abs(axis.y) < 0.85 else Vector((1, 0, 0))
    n1 = axis.cross(ref).normalized()
    n2 = axis.cross(n1).normalized()
    layers = ((7, size, math.radians(46), 0.0), (6, size * 0.88, math.radians(28), math.pi / 6),
              (4, size * 0.66, math.radians(10), 0.3))
    nu, nv = max(4, int(7 * DETAIL)), max(3, int(5 * DETAIL))
    for count, ln, tilt, rot in layers:
        for k in range(count):
            phi = rot + 2 * math.pi * k / count + rng.uniform(-0.12, 0.12)
            e = n1 * math.cos(phi) + n2 * math.sin(phi)
            s = axis.cross(e).normalized()
            grid = []
            for iu in range(nu + 1):
                u = iu / nu
                th = tilt + 0.36 * u ** 2.2
                spine = pos + (axis * math.cos(th) + e * math.sin(th)) * ln * u
                tang = (axis * math.cos(th) + e * math.sin(th))
                out = s.cross(tang).normalized()
                if out.dot(e) < 0:
                    out = -out
                w = ln * 0.52 * math.sqrt(max(0.0, 1 - ((u - 0.5) / 0.5) ** 2)) ** 0.8
                row = []
                for iv in range(nv + 1):
                    v = -1 + 2 * iv / nv
                    co = spine + s * v * w - out * 0.55 * w * v * v
                    row.append(fb.vert(co, (u, 0, 0)))
                grid.append(row)
            for iu in range(nu):
                for iv in range(nv):
                    fb.bm.faces.new((grid[iu][iv], grid[iu][iv + 1], grid[iu + 1][iv + 1], grid[iu + 1][iv]))
    # glowing heart
    bmesh.ops.create_icosphere(hb.bm, subdivisions=1, radius=size * 0.16,
                               matrix=Matrix.Translation(pos + axis * size * 0.12))


def gem(tip, base, ry, rz, mat, name, scale):
    """Faceted crystal shard from base to tip: short back pyramid, long 8-sided prism body that narrows
    slightly, then a long pointed front. Front view reads as a rhombus (vertical/horizontal points
    dominant), side view as a long hexagonal shard. scale<1 shrinks it about its body centre."""
    b = Builder(name)
    d = (tip - base)
    length = d.length
    d = d.normalized()
    side = d.cross(Vector((0, 0, 1))).normalized()
    up = side.cross(d).normalized()
    centre = base + d * (0.40 * length)
    def put(co):
        return b.vert(centre + (co - centre) * scale, (0, 0, 0))
    stations = ((0.16, 0.86), (0.30, 1.0), (0.58, 0.92))   # (fraction along base->tip, radius factor)
    rings = []
    for frac, rf in stations:
        c = base + d * (frac * length)
        ring = []
        for k in range(8):
            a = 2 * math.pi * k / 8 + math.pi / 2
            f = 1.0 if k % 2 == 0 else 0.70
            ring.append(put(c + (side * math.cos(a) * ry + up * math.sin(a) * rz) * f * rf))
        rings.append(ring)
    tipv = put(tip)
    back = put(base)
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(8):
            k2 = (k + 1) % 8
            b.bm.faces.new((r0[k], r0[k2], r1[k2], r1[k]))
    for k in range(8):
        k2 = (k + 1) % 8
        b.bm.faces.new((rings[-1][k], rings[-1][k2], tipv))
        b.bm.faces.new((rings[0][k2], rings[0][k], back))
    bmesh.ops.recalc_face_normals(b.bm, faces=b.bm.faces[:])
    return b.finish(mat, smooth=False)


# ---------------------------------------------------------------- flowing sand around the crystal
def sand(time=0.0, name='Sand'):
    """Flowing sand: two spiral ribbons of short glowing streaks wrapping the crystal from its base to its
    tip and trickling off the point, plus fine dust along them. Head warm gold -> tail lilac & transparent.
    `time` in [0,1) slides everything along the spiral (seamless loop)."""
    sb = Builder(name)
    r2 = random.Random(11)
    basex, tipx = 0.150, -0.045
    def spiral(phase, s):
        x = basex + (tipx - basex) * s
        a = phase + 2 * math.pi * 1.25 * s + 0.25 * math.sin(7 * s + phase)
        rad = 0.040 - 0.030 * s + 0.030 * s * s
        return P(x, YC + math.sin(a) * rad, math.cos(a) * rad)
    head, tail = (1.0, 0.70, 0.36), (0.58, 0.38, 1.0)
    for stream in range(2):
        phase = stream * math.pi + 0.6
        for k in range(9):
            s0 = (k / 9 + time) % 1.0
            span = 0.075 + 0.03 * r2.random()
            if s0 + span > 1.0:
                continue
            pts = [spiral(phase, s0 + span * j / 10) for j in range(11)]
            # streak points backwards: head at the leading end (larger s)
            pts = pts[::-1]
            fade = 1 - s0
            col = lambda t, s0=s0: tuple(head[c] + (tail[c] - head[c]) * min(1, s0 + t * 0.4) for c in range(3)) + ((1 - t) ** 1.4 * (0.35 + 0.65 * fade),)
            radii = [0.0013 * L * (1 - 0.8 * j / 10) * (0.6 + 0.4 * fade) for j in range(11)]
            radii[-1] = 0.0
            sb.tube(pts, radii, 5, col, cap=True)
    for _ in range(int(260 * DETAIL)):
        stream = r2.randrange(2)
        s = (r2.random() + time) % 1.0
        c = spiral(stream * math.pi + 0.6, s)
        c += Vector((r2.gauss(0, 1), r2.gauss(0, 1), r2.gauss(0, 1))) * (0.003 + 0.012 * s * s) * L
        size = (0.0007 + 0.0005 * r2.random()) * L * (1 - 0.5 * s)
        a_ = (1 - s) ** 0.8
        col = tuple(head[j] + (tail[j] - head[j]) * s for j in range(3)) + (0.3 + 0.7 * a_,)
        res = bmesh.ops.create_icosphere(sb.bm, subdivisions=1, radius=size, matrix=Matrix.Translation(c))
        for v in res['verts']:
            v[sb.tint] = col
    return sb.finish(SAND_MAT, smooth=True)


# ---------------------------------------------------------------- scene, lights, compositing
def setup_scene(dark=False):
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    ee = sc.eevee
    ee.use_raytracing = True
    ee.taa_render_samples = 48
    try:
        ee.ray_tracing_options.resolution_scale = '1'
    except Exception:
        pass
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    w = bpy.data.worlds.new('W') if not sc.world else sc.world
    sc.world = w
    w.use_nodes = True
    wt = w.node_tree
    bgn = wt.nodes.get('Background')
    bgn.inputs['Color'].default_value = (0.35, 0.34, 0.40, 1)
    bgn.inputs['Strength'].default_value = 0.35
    cam_bg = wt.nodes.new('ShaderNodeBackground')
    cam_bg.name = 'CameraBackdrop'
    cam_bg.inputs['Color'].default_value = (0.022, 0.018, 0.035, 1) if dark else (0.70, 0.70, 0.73, 1)
    lp = wt.nodes.new('ShaderNodeLightPath')
    mx = wt.nodes.new('ShaderNodeMixShader')
    wt.links.new(lp.outputs['Is Camera Ray'], mx.inputs['Fac'])
    wt.links.new(bgn.outputs['Background'], mx.inputs[1])
    wt.links.new(cam_bg.outputs['Background'], mx.inputs[2])
    wt.links.new(mx.outputs['Shader'], wt.nodes['World Output'].inputs['Surface'])
    sc.render.film_transparent = False

    def area(name, loc, energy, color, size):
        ld = bpy.data.lights.new(name, 'AREA')
        ld.energy, ld.color, ld.size = energy, color, size
        ob = bpy.data.objects.new(name, ld)
        sc.collection.objects.link(ob)
        ob.location = loc
        ob.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
        return ob
    area('Key', (-1.6, -2.4, 1.8), 110, (1.0, 0.96, 0.93), 2.0)
    area('Fill', (2.2, -1.5, 0.2), 28, (0.85, 0.85, 1.0), 2.5)
    area('Rim', (0.8, 2.4, 1.2), 220, (0.80, 0.62, 1.0), 1.5)

    # bloom-style glow on emissive parts (compositor glare)
    try:
        tree = bpy.data.node_groups.new('Comp', 'CompositorNodeTree')
        sc.compositing_node_group = tree
        rl = tree.nodes.new('CompositorNodeRLayers')
        gl = tree.nodes.new('CompositorNodeGlare')
        out = tree.nodes.new('NodeGroupOutput')
        tree.interface.new_socket('Image', in_out='OUTPUT', socket_type='NodeSocketColor')
        for key, val in (('Type', 'Fog Glow'), ('Quality', 'High'), ('Threshold', 1.0), ('Strength', 0.32), ('Size', 0.12)):
            if key in gl.inputs:
                try:
                    gl.inputs[key].default_value = val
                except Exception as exc:
                    print('glare input', key, exc)
        tree.links.new(rl.outputs['Image'], gl.inputs['Image'])
        tree.links.new(gl.outputs[0], out.inputs[0])
        print('compositor glare ok', [i.name for i in gl.inputs])
    except Exception as exc:
        print('compositor unavailable:', exc)


def camera(name, loc, target, ortho=None, lens=70):
    cd = bpy.data.cameras.new(name)
    if ortho:
        cd.type = 'ORTHO'
        cd.ortho_scale = ortho
        cd.sensor_fit = 'VERTICAL'
    else:
        cd.lens = lens
    ob = bpy.data.objects.new(name, cd)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return ob


def render(cam, path, w, h):
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


# ---------------------------------------------------------------- main
bpy.ops.wm.read_factory_settings(use_empty=True)
SAND_MAT = mat_sand()
build_bow()
cx = (0.17 - XC) * L

if MODE == 'stills':
    sand_ob = sand(0.0)
    setup_scene(dark=False)
    ortho = 1.08 * L
    render(camera('SideCam', (cx, -4, 0), (cx, 0, 0), ortho), f'{OUT}/side.png', 560, 1600)
    render(camera('FrontCam', (-4, 0, 0), (0, 0, 0), ortho), f'{OUT}/front.png', 300, 1600)
    render(camera('BackCam', (cx, 4, 0), (cx, 0, 0), ortho), f'{OUT}/side_other.png', 560, 1600)
    render(camera('Hero', (-1.15, -2.05, 0.45), (0.02, 0, 0.0), lens=80), f'{OUT}/hero_light.png', 1100, 1500)
    render(camera('Gem', (-0.42, -0.42, 0.10), (P(0.07, YC).x, 0, 0), lens=60), f'{OUT}/crystal_closeup.png', 1200, 900)
    # dark variant for glow reading
    bpy.context.scene.world.node_tree.nodes['CameraBackdrop'].inputs['Color'].default_value = (0.02, 0.016, 0.03, 1)
    render(bpy.data.objects['Hero'], f'{OUT}/hero_dark.png', 1100, 1500)
    render(bpy.data.objects['Gem'], f'{OUT}/crystal_closeup_dark.png', 1200, 900)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath('art/weapon_gen/out/thornbow.blend'))
elif MODE == 'measure':
    # Pixel-registered side view against the 2560x1440 three-view sheet: 1 L = 1334 px, sheet x0=328, y0=65.
    setup_scene(dark=False)
    sc = bpy.context.scene
    sc.render.film_transparent = True
    try:
        sc.compositing_node_group = None
    except Exception:
        pass
    PXL = 1334.0
    cam = camera('Meas', (P((1280 - 328) / PXL, (720 - 65) / PXL).x, -4, P((1280 - 328) / PXL, (720 - 65) / PXL).z),
                 (P((1280 - 328) / PXL, (720 - 65) / PXL).x, 0, P((1280 - 328) / PXL, (720 - 65) / PXL).z), 1440 / PXL * L)
    groups = {'wood': ['Wood'], 'flowers': ['Flowers', 'FlowerHearts'], 'crystal': ['Crystal', 'CrystalCore'],
              'grip': ['GripWrap'], 'string': ['String']}
    for gname, names in groups.items():
        for ob in bpy.data.objects:
            if ob.type == 'MESH':
                ob.hide_render = ob.name not in names
        render(cam, f'{OUT}/meas_{gname}.png', 2560, 1440)
elif MODE == 'anim':
    setup_scene(dark=True)
    cam = camera('Gem', (-0.42, -0.42, 0.10), (P(0.07, YC).x, 0, 0), lens=60)
    frames = int(ARGS[2]) if len(ARGS) > 2 else 24
    for f in range(frames):
        ob = sand(f / frames, 'Sand_%d' % f)
        render(cam, f'{OUT}/sand_{f:03d}.png', 640, 480)
        bpy.data.objects.remove(ob, do_unlink=True)
print('THORNBOW DONE', MODE)
