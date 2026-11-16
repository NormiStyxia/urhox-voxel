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
    # Clear violet gem: raytraced refraction, low roughness, faint internal glow from the core object.
    m, nt, b = principled('Crystal_Gem', Roughness=0.03, IOR=1.62,
                          **{'Base Color': (0.36, 0.12, 0.92, 1), 'Transmission Weight': 0.9, 'Specular IOR Level': 0.9,
                             'Coat Weight': 0.5, 'Coat Roughness': 0.02,
                             'Emission Color': (0.32, 0.08, 0.90, 1), 'Emission Strength': 0.35})
    lw = node(nt, 'ShaderNodeLayerWeight', (-500, -300), Blend=0.35)
    pw = node(nt, 'ShaderNodeMath', (-300, -300)); pw.operation = 'POWER'; pw.inputs[1].default_value = 2.0
    nt.links.new(lw.outputs['Facing'], pw.inputs[0])
    ma = node(nt, 'ShaderNodeMath', (-120, -300)); ma.operation = 'MULTIPLY_ADD'
    ma.inputs[1].default_value = 2.2; ma.inputs[2].default_value = 0.22
    nt.links.new(pw.outputs['Value'], ma.inputs[0])
    nt.links.new(ma.outputs['Value'], b.inputs['Emission Strength'])
    b.inputs['Emission Color'].default_value = (0.55, 0.30, 1.0, 1)
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


def build_bow():
    wood, flower_m, crystal_m = mat_wood(), mat_flower(), mat_crystal()
    core_m = mat_emit('Crystal_Core', (0.48, 0.22, 1.0, 1), 4.0)
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
    tips = {}
    seg_main = max(5, int(9 * DETAIL))
    seg_thin = max(4, int(6 * DETAIL))
    for sign in (1, -1):
        ctrl = [P(x, y) for x, y in limb_ctrl(sign)]
        A = curve(ctrl, int(46 * DETAIL) + 8)
        n = len(A)
        tips[sign] = A[-1]
        fade = lambda t: (max(0.0, (t - 0.72) / 0.28) ** 1.5, 0, 0)
        wood_b.tube(A, taper(n, 0.0135 * L, 0.0046 * L, 0.9), seg_main, fade, cap=False, jitter=0.12)
        # top lotus: the main branch continues a little past the nock
        top_flower = P(0.259, 0.022 if sign > 0 else mirror_y(0.022))
        ext = curve([A[-2], A[-1], A[-1].lerp(top_flower, 0.55) + Vector((-0.004 * L, 0, 0)), top_flower], 10)
        wood_b.tube(ext, taper(len(ext), 0.0048 * L, 0.0018 * L), seg_thin, lambda t: (max(0.0, (t - 0.6) / 0.4), 0, 0))
        flowers.append((top_flower, (top_flower - ext[-3]).normalized(), 0.044 * L))

        # two strands braided around the main branch, each peeling off into a flower branch
        strands = [
            dict(phase=0.0, turns=1.15, leave=0.42, flower=(0.079, 0.259, -0.018), via=(0.100, 0.300, -0.012)),
            dict(phase=2 * math.pi / 3, turns=1.0, leave=0.56, flower=(0.292, 0.214, 0.022), via=(0.240, 0.243, 0.016)),
            dict(phase=4 * math.pi / 3, turns=0.9, leave=0.70, flower=None, via=(0.215, 0.180, -0.010)),
        ]
        for sd in strands:
            fx, fy, fz = sd['flower'] or (0.262, 0.150, -0.014)
            vx, vy, vz = sd['via']
            if sign < 0:
                fy, vy = mirror_y(fy), mirror_y(vy)
                fz, vz = -fz, -vz
            leave_i = int(sd['leave'] * (n - 1))
            pts = []
            for i in range(0, leave_i + 1, 1):
                t = i / (n - 1)
                a = sd['phase'] + 2 * math.pi * sd['turns'] * t * sign
                tng = (A[min(n - 1, i + 1)] - A[max(0, i - 1)]).normalized()
                side = tng.cross(Vector((0, 1, 0))).normalized()
                gz = min(1.0, max(0.0, (abs(A[i].z) - grip_zone) / (0.05 * L)))
                amp = (0.40 + 0.60 * gz * gz * (3 - 2 * gz)) * (1 - 0.40 * t)
                off = (side * math.cos(a) * 0.030 + Vector((0, 1, 0)) * math.sin(a) * 0.014) * L * amp
                pts.append(A[i] + off)
            pts += [P(vx, vy, vz), P(fx, fy, fz)]
            S = curve(pts, int(30 * DETAIL) + 6)
            ns = len(S)
            wood_b.tube(S, taper(ns, 0.0100 * L, 0.0022 * L if sd['flower'] else 0.0, 1.1), seg_thin,
                        lambda t: (max(0.0, (t - 0.82) / 0.18) ** 1.2, 0, 0), cap=True, jitter=0.1)
            if sd['flower']:
                flowers.append((S[-1], (S[-1] - S[-4]).normalized(), 0.042 * L))

        # flower twigs off the upper main branch
        for (fx, fy, fz), t0, bend in (((0.232, 0.112, -0.028), 0.80, (-0.010, 0.0)), ((0.307, 0.094, 0.026), 0.86, (0.012, 0.0))):
            if sign < 0:
                fy, fz = mirror_y(fy), -fz
            i0 = int(t0 * (n - 1))
            end = P(fx, fy, fz)
            mid = A[i0].lerp(end, 0.5) + Vector((bend[0] * L, 0, 0.006 * L * sign))
            T = curve([A[i0], mid, end], 12)
            wood_b.tube(T, taper(len(T), 0.0050 * L, 0.0018 * L), seg_thin, lambda t: (max(0.0, (t - 0.8) / 0.2), 0, 0))
            flowers.append((end, (end - T[-3]).normalized(), 0.038 * L))

        # bare thorny twigs (decoration), never inside the grip zone
        for t0, dx, dy, dz, length in ((0.30, -1.0, 0.55, 0.20, 0.070), (0.40, 0.95, 0.85, -0.25, 0.060),
                                       (0.52, -0.9, 0.9, 0.15, 0.058), (0.66, 0.75, 1.0, 0.30, 0.048),
                                       (0.36, -0.7, -0.35, -0.3, 0.042), (0.74, -0.85, 0.6, -0.2, 0.045),
                                       (0.26, 0.8, 0.2, 0.35, 0.045), (0.46, -1.0, 0.1, -0.35, 0.050),
                                       (0.58, 0.95, 0.4, -0.1, 0.040), (0.84, -0.7, 0.9, 0.25, 0.035)):
            i0 = int(t0 * (n - 1))
            if not grip_safe(A[i0]):
                continue
            d = Vector((dx, dz, dy * sign)).normalized()
            curl = Vector((0, 0, 0.35 * sign))
            T = curve([A[i0], A[i0] + d * length * 0.5 * L, A[i0] + (d + curl).normalized() * length * L], 10)
            wood_b.tube(T, taper(len(T), 0.0052 * L, 0.0, 0.9), seg_thin, lambda t: (0.15 * t, 0, 0))
            if length >= 0.05:   # small fork near the twig's middle
                fk = T[len(T) // 2]
                fd = (d + Vector((0, 0, 0.9 * sign)) + Vector((0, rng.uniform(-0.4, 0.4), 0))).normalized()
                F = curve([fk, fk + fd * 0.012 * L, fk + (fd + curl).normalized() * 0.026 * L], 7)
                wood_b.tube(F, taper(len(F), 0.0028 * L, 0.0, 0.9), 4, lambda t: (0.2 * t, 0, 0))
        # small thorns
        for _ in range(int(14 * DETAIL)):
            t0 = rng.uniform(0.18, 0.92)
            i0 = int(t0 * (n - 1))
            if not grip_safe(A[i0]):
                continue
            tng = (A[min(n - 1, i0 + 1)] - A[max(0, i0 - 1)]).normalized()
            a = rng.uniform(0, 2 * math.pi)
            side = tng.cross(Vector((0, 1, 0))).normalized()
            out = (side * math.cos(a) + Vector((0, 1, 0)) * math.sin(a)).normalized()
            r = 0.0165 * L * (1 - 0.7 * t0)
            base = A[i0] + out * r * 0.8
            tip = base + (out * 0.85 + tng * 0.5).normalized() * 0.014 * L
            wood_b.tube([base, base.lerp(tip, 0.5), tip], [0.0024 * L, 0.0012 * L, 0.0], 4, lambda t: (0, 0, 0))

    # crystal claws: four branch fingers holding the gem in front of the grip
    gem_base_x, gem_tip_x = 0.120, 0.004
    for ry_, zz, reach in ((0.400, 0.010, 0.060), (0.578, -0.010, 0.060), (0.410, -0.022, 0.085), (0.568, 0.022, 0.085)):
        root = P(0.128, ry_, zz * 0.5)
        mid = P(0.090, YC + (ry_ - YC) * 0.62, zz * 1.4)
        hold = P(0.120 - reach, YC + (ry_ - YC) * 0.30, zz * 1.2)
        T = curve([root, root.lerp(mid, 0.5) + Vector((-0.004 * L, 0, 0)), mid, hold], 16)
        wood_b.tube(T, taper(len(T), 0.0068 * L, 0.0, 0.85), seg_thin, lambda t: (0.25 * t, 0, 0))

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
    layers = ((5, size, math.radians(42), 0.0), (5, size * 0.88, math.radians(23), math.pi / 5),
              (3, size * 0.64, math.radians(7), 0.3))
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
                w = ln * 0.36 * (math.sin(math.pi * min(u, 0.999) ** 0.8) ** 0.9)
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
elif MODE == 'anim':
    setup_scene(dark=True)
    cam = camera('Gem', (-0.42, -0.42, 0.10), (P(0.07, YC).x, 0, 0), lens=60)
    frames = int(ARGS[2]) if len(ARGS) > 2 else 24
    for f in range(frames):
        ob = sand(f / frames, 'Sand_%d' % f)
        render(cam, f'{OUT}/sand_{f:03d}.png', 640, 480)
        bpy.data.objects.remove(ob, do_unlink=True)
print('THORNBOW DONE', MODE)
