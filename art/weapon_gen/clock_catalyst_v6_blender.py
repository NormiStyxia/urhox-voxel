"""Clock catalyst v6 - follows the user's FRONT reference sheet (2026-11-18):
two thick crescent halves of deep-navy *star-metal* bands with silver bevel rims, white Roman numerals
(XII / III / VI / IX) and small gold 4-point sparkles; a sharp glassy blade crescent inside each band whose
tip runs past the band end; two navy rhombus gems; a few ice shards; a faceted SAPPHIRE gem sphere in the
centre (user: "中间是那种宝石的感觉"). 180-degree rotational symmetry like the reference.

Blender Z-up. Front camera at -Y. Ring plane = XZ; angle theta measured from the top, clockwise on screen.
Motion (12 s loop): band pair turns around the horizontal X axis, blade pair counter-turns, rhombus gems
orbit in the front plane, shards bob.

Run:  Blender -b --factory-startup -P art/weapon_gen/clock_catalyst_v6_blender.py
      (CLOCK_STILLS_ONLY=1 skips the 60 animation frames)
"""
import json
import math
import os
import random
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

OUT = Path('art/weapon_gen/out/clock_catalyst_v6').resolve()
(OUT / 'frames').mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
col = bpy.data.collections.new('Clock_Catalyst_V6')
scene.collection.children.link(col)
rng = random.Random(6)
EXPORT = os.environ.get('CLOCK_EXPORT') == '1'   # game LOD: coarse arcs, flat numerals, JSON dump instead of renders
STEP_SCALE = float(os.environ.get('CLOCK_STEP_SCALE', .34 if EXPORT else 1.0))


def empty(name, parent=None):
    o = bpy.data.objects.new(name, None)
    col.objects.link(o)
    o.parent = parent
    return o


def mesh(name, verts, faces, mats, parent, mat_idx=None, smooth=False):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    for m in mats:
        me.materials.append(m)
    if mat_idx:
        for p, i in zip(me.polygons, mat_idx):
            p.material_index = i
    for p in me.polygons:
        p.use_smooth = smooth
    o = bpy.data.objects.new(name, me)
    col.objects.link(o)
    o.parent = parent
    return o


def link(nt, a, b):
    nt.links.new(a, b)


def principled(name, **inputs):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    for k, v in inputs.items():
        b.inputs[k].default_value = v
    return m, m.node_tree, b


# ------------------------------------------------------------------ materials
def mat_star_metal():
    """Deep navy enamel/metal with soft lighter nebula patches, fine white stars (object space)."""
    m, nt, b = principled('Star_metal_navy', Roughness=.32, Metallic=.35, **{'Coat Weight': .5, 'Coat Roughness': .08})
    tc = nt.nodes.new('ShaderNodeTexCoord')
    mp = nt.nodes.new('ShaderNodeMapping'); mp.inputs['Scale'].default_value = (14, 14, 14)
    link(nt, tc.outputs['Object'], mp.inputs['Vector'])
    nz = nt.nodes.new('ShaderNodeTexNoise'); nz.inputs['Detail'].default_value = 4; nz.inputs['Roughness'].default_value = .55
    link(nt, mp.outputs['Vector'], nz.inputs['Vector'])
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    e = ramp.color_ramp.elements
    e[0].position, e[0].color = .38, (.012, .030, .115, 1)
    e[1].position, e[1].color = .72, (.060, .140, .420, 1)
    link(nt, nz.outputs['Fac'], ramp.inputs['Fac'])
    # stars: tiny voronoi cells
    mp2 = nt.nodes.new('ShaderNodeMapping'); mp2.inputs['Scale'].default_value = (160, 160, 160)
    link(nt, tc.outputs['Object'], mp2.inputs['Vector'])
    vo = nt.nodes.new('ShaderNodeTexVoronoi'); vo.feature = 'F1'
    link(nt, mp2.outputs['Vector'], vo.inputs['Vector'])
    st = nt.nodes.new('ShaderNodeMath'); st.operation = 'LESS_THAN'; st.inputs[1].default_value = .07
    link(nt, vo.outputs['Distance'], st.inputs[0])
    mix = nt.nodes.new('ShaderNodeMix'); mix.data_type = 'RGBA'
    mix.inputs[7].default_value = (.85, .92, 1, 1)
    link(nt, st.outputs['Value'], mix.inputs['Factor'])
    link(nt, ramp.outputs['Color'], mix.inputs[6])
    link(nt, mix.outputs[2], b.inputs['Base Color'])
    em = nt.nodes.new('ShaderNodeMath'); em.operation = 'MULTIPLY_ADD'
    em.inputs[1].default_value = 2.5; em.inputs[2].default_value = .25
    link(nt, st.outputs['Value'], em.inputs[0])
    link(nt, mix.outputs[2], b.inputs['Emission Color'])
    link(nt, em.outputs['Value'], b.inputs['Emission Strength'])
    return m


def mat_silver():
    m, nt, b = principled('Silver_bevel', **{'Base Color': (.86, .88, .93, 1), 'Metallic': .85, 'Roughness': .22,
                                              'Emission Color': (.80, .86, 1, 1), 'Emission Strength': .25})
    return m


def mat_glass_blade():
    """Glassy ice-blue crescent blade: light at the edges, deeper blue body, see-through."""
    m, nt, b = principled('Glass_blade', **{'Base Color': (.20, .40, .92, 1), 'Roughness': .05,
                                             'Specular IOR Level': .9, 'Coat Weight': .7, 'Coat Roughness': .02})
    lw = nt.nodes.new('ShaderNodeLayerWeight'); lw.inputs['Blend'].default_value = .4
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    e = ramp.color_ramp.elements
    e[0].position, e[0].color = 0, (.62, .62, .62, 1)
    e[1].position, e[1].color = 1, (.97, .97, .97, 1)
    link(nt, lw.outputs['Facing'], ramp.inputs['Fac'])
    link(nt, ramp.outputs['Color'], b.inputs['Alpha'])
    b.inputs['Emission Color'].default_value = (.40, .62, 1, 1)
    em = nt.nodes.new('ShaderNodeMath'); em.operation = 'MULTIPLY_ADD'
    em.inputs[1].default_value = .8; em.inputs[2].default_value = .15
    link(nt, lw.outputs['Facing'], em.inputs[0])
    link(nt, em.outputs['Value'], b.inputs['Emission Strength'])
    m.surface_render_method = 'BLENDED'
    m.use_backface_culling = False
    return m


def mat_gold():
    m, nt, b = principled('Gold_sparkle', **{'Base Color': (1, .78, .36, 1), 'Metallic': .6, 'Roughness': .25,
                                              'Emission Color': (1, .80, .42, 1), 'Emission Strength': 1.6})
    return m


def mat_numeral():
    m, nt, b = principled('Numeral_white', **{'Base Color': (.96, .97, 1, 1), 'Roughness': .4,
                                               'Emission Color': (.95, .97, 1, 1), 'Emission Strength': .9})
    return m


def mat_sapphire():
    """Faceted sapphire: every cut gets its own blue level (face attribute 'facet'), icy fresnel rim, a few
    white star glints on the surface, glossy coat. Opaque on purpose - reads as a cut gem, not a glass bubble."""
    m, nt, b = principled('Sapphire_core', **{'Roughness': .05, 'Specular IOR Level': 1.0, 'IOR': 1.77,
                                               'Coat Weight': .9, 'Coat Roughness': .02})
    at = nt.nodes.new('ShaderNodeAttribute'); at.attribute_name = 'facet'; at.attribute_type = 'GEOMETRY'
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    e = ramp.color_ramp.elements
    e[0].position, e[0].color = 0.0, (.006, .020, .120, 1)
    e[1].position, e[1].color = 1.0, (.420, .720, 1.00, 1)
    mid = e.new(.50); mid.color = (.030, .130, .560, 1)
    hi = e.new(.80); hi.color = (.110, .360, .920, 1)
    link(nt, at.outputs['Fac'], ramp.inputs['Fac'])
    lw = nt.nodes.new('ShaderNodeLayerWeight'); lw.inputs['Blend'].default_value = .25
    rim = nt.nodes.new('ShaderNodeMix'); rim.data_type = 'RGBA'
    rim.inputs[7].default_value = (.55, .80, 1, 1)
    pw = nt.nodes.new('ShaderNodeMath'); pw.operation = 'POWER'; pw.inputs[1].default_value = 2.2
    link(nt, lw.outputs['Facing'], pw.inputs[0])
    link(nt, pw.outputs['Value'], rim.inputs['Factor'])
    link(nt, ramp.outputs['Color'], rim.inputs[6])
    link(nt, rim.outputs[2], b.inputs['Base Color'])
    # glints
    tc = nt.nodes.new('ShaderNodeTexCoord')
    mp = nt.nodes.new('ShaderNodeMapping'); mp.inputs['Scale'].default_value = (60, 60, 60)
    link(nt, tc.outputs['Object'], mp.inputs['Vector'])
    vo = nt.nodes.new('ShaderNodeTexVoronoi')
    link(nt, mp.outputs['Vector'], vo.inputs['Vector'])
    gl = nt.nodes.new('ShaderNodeMath'); gl.operation = 'LESS_THAN'; gl.inputs[1].default_value = .05
    link(nt, vo.outputs['Distance'], gl.inputs[0])
    emc = nt.nodes.new('ShaderNodeMix'); emc.data_type = 'RGBA'
    emc.inputs[7].default_value = (1, 1, 1, 1)
    link(nt, gl.outputs['Value'], emc.inputs['Factor'])
    link(nt, rim.outputs[2], emc.inputs[6])
    link(nt, emc.outputs[2], b.inputs['Emission Color'])
    ems = nt.nodes.new('ShaderNodeMath'); ems.operation = 'MULTIPLY_ADD'
    ems.inputs[1].default_value = 3.0; ems.inputs[2].default_value = .38
    link(nt, gl.outputs['Value'], ems.inputs[0])
    link(nt, ems.outputs['Value'], b.inputs['Emission Strength'])
    return m


def mat_ice():
    m, nt, b = principled('Ice_shard', **{'Base Color': (.48, .66, 1, 1), 'Roughness': .05, 'Alpha': .8,
                                           'Emission Color': (.45, .64, 1, 1), 'Emission Strength': .7})
    m.surface_render_method = 'BLENDED'
    m.use_backface_culling = False
    return m


STAR, SILVER, GLASS, GOLD, WHITE, SAPPHIRE, ICE = (mat_star_metal(), mat_silver(), mat_glass_blade(), mat_gold(),
                                                   mat_numeral(), mat_sapphire(), mat_ice())


# ------------------------------------------------------------------ geometry helpers
def P(r, th, y):
    return (r * math.sin(th), y, r * math.cos(th))


def arc_prism(name, a0, a1, radii, depth, parent, mats, face_mat=0, side_mat=1, steps=None):
    """Arc prism in the XZ plane. radii(t) -> (inner, outer). Front face at y=-depth/2 (camera side)."""
    n = steps or max(10, int(abs(a1 - a0) * 40))
    n = max(5, int(n * STEP_SCALE))
    V, F, M = [], [], []
    for i in range(n + 1):
        t = i / n
        th = a0 + (a1 - a0) * t
        ri, ro = radii(t)
        for r, y in ((ro, -depth / 2), (ri, -depth / 2), (ri, depth / 2), (ro, depth / 2)):
            V.append(P(r, th, y))
    for i in range(n):
        a, b = 4 * i, 4 * (i + 1)
        F += [(a, a + 1, b + 1, b), (a + 3, b + 3, b + 2, a + 2),       # front, back
              (a, b, b + 3, a + 3), (a + 1, a + 2, b + 2, b + 1)]       # outer, inner side
        M += [face_mat, face_mat, side_mat, side_mat]
    F += [(0, 3, 2, 1), (4 * n, 4 * n + 1, 4 * n + 2, 4 * n + 3)]
    M += [side_mat, side_mat]
    o = mesh(name, V, F, mats, parent, M)
    # outward-consistent normals
    me = o.data
    import bmesh
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me); bm.free()
    return o


def sparkle(name, centre, size, parent, normal_y=-1):
    """Flat 4-point star facing the camera, slightly in front of the surface."""
    cx, cy, cz = centre
    V = [(cx, cy, cz)]
    for k in range(8):
        a = k * math.pi / 4
        r = size if k % 2 == 0 else size * .22
        V.append((cx + r * math.sin(a), cy, cz + r * math.cos(a)))
    F = [(0, 1 + k, 1 + (k + 1) % 8) for k in range(8)]
    return mesh(name, V, F, [GOLD], parent)


def numeral(label, r, th, y, size, parent):
    cu = bpy.data.curves.new('N_' + label, 'FONT')
    cu.body = label
    cu.font = FONT
    cu.align_x, cu.align_y = 'CENTER', 'CENTER'
    cu.size = size
    cu.extrude = 0 if EXPORT else .0006
    cu.resolution_u = 1 if EXPORT else 12
    o = bpy.data.objects.new('Numeral_' + label, cu)
    col.objects.link(o)
    o.parent = parent
    tangent = Vector((math.cos(th), 0, -math.sin(th)))
    radial = Vector((math.sin(th), 0, math.cos(th)))
    if math.cos(th) < .1:          # lower half and sides: keep the numeral readable, tops toward the centre
        tangent, radial = -tangent, -radial
    normal = Vector((0, -1, 0))
    o.location = Vector(P(r, th, y))
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = Matrix((tangent, radial, normal)).transposed().to_quaternion()
    cu.materials.append(WHITE)
    return o


FONT = bpy.data.fonts.load('/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf') \
    if os.path.exists('/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf') else \
    bpy.data.fonts.load('/System/Library/Fonts/Supplemental/Times New Roman.ttf')

root = empty('ClockCatalyst_ROOT')
D = math.radians
R_BAND = .245          # band centre radius
W_BAND = .040          # band radial width
T_BAND = .014          # band thickness (Y)

# ------------------------------------------------------------------ band pair (rotates around X)
band_pivot = empty('Bands_pivot', root)
blade_pivot = empty('Blades_pivot', root)
for half, rot in ((0, 0.0), (1, math.pi)):
    # left half (theta 190..350) / right half rotated 180
    a0, a1 = D(192) + rot, D(352) + rot
    # crescent band: outer edge is a true circle, inner edge swells toward the middle and the ends taper
    # to slanted blade points (reference silhouette)
    def band_r(t):
        w = W_BAND * max(.10, math.sin(math.pi * t) ** .45)
        return R_BAND + W_BAND / 2 - w, R_BAND + W_BAND / 2
    arc_prism('Band_%d' % half, a0, a1, band_r, T_BAND, band_pivot, [STAR, SILVER], steps=80)
    # silver bevel rims on the front and back faces
    for side in (-1, 1):
        y = side * (T_BAND / 2 + .0005)
        rim = arc_prism('Rim_outer', a0, a1, lambda t: (R_BAND + W_BAND / 2 - .0034, R_BAND + W_BAND / 2 - .0002),
                        .0012, band_pivot, [SILVER, SILVER], steps=80)
        rim.location.y = y
        rim = arc_prism('Rim_inner', a0, a1, lambda t: (band_r(t)[0] + .0002, band_r(t)[0] + .0030),
                        .0012, band_pivot, [SILVER, SILVER], steps=80)
        rim.location.y = y
    # silver segment bars across the band
    for frac in (.36, .70):
        th = a0 + (a1 - a0) * frac
        arc_prism('Bar', th - D(.6), th + D(.6), lambda t, th=th: (band_r((th - a0) / (a1 - a0))[0], R_BAND + W_BAND / 2),
                  T_BAND + .0026, band_pivot, [SILVER, SILVER], steps=1)
    # numerals: XII/IX on one half, VI/III on the other (front + mirrored back)
    labels = (('XII', D(338)), ('IX', D(270))) if half == 0 else (('VI', D(158)), ('III', D(90)))
    for label, th in labels:
        numeral(label, R_BAND + W_BAND * .12, th, -(T_BAND / 2 + .0012), .026, band_pivot)
    # gold sparkles on the band
    for frac in (.12, .52, .88):
        th = a0 + (a1 - a0) * frac
        sparkle('Band_sparkle', P(R_BAND + W_BAND * .18, th, -(T_BAND / 2 + .0013)), .0055, band_pivot)

    # glass blade crescent just inside the band; thick in the middle, sharp tips, the lower tip runs past
    # the band end (like the reference's left blade)
    b0, b1 = D(168) + rot, D(300) + rot
    def blade(t):
        w = .019 * math.sin(math.pi * t) ** .8
        outer = R_BAND - W_BAND / 2 - .006
        return outer - w, outer
    arc_prism('Blade_%d' % half, b0, b1, blade, .006, blade_pivot, [GLASS, SILVER], steps=60)
    # silver hairline along the blade's outer edge
    arc_prism('Blade_edge', b0 + D(6), b1 - D(6), lambda t: (R_BAND - W_BAND / 2 - .0072, R_BAND - W_BAND / 2 - .0052),
              .007, blade_pivot, [SILVER, SILVER])
    # inner silver hairline following the swelling edge
    arc_prism('Blade_edge_in', b0 + D(10), b1 - D(10),
              lambda t: (blade(.06 + .88 * t)[0] - .0004, blade(.06 + .88 * t)[0] + .0014), .007, blade_pivot, [SILVER, SILVER], steps=50)

# ------------------------------------------------------------------ rhombus gems (orbit in the front plane)
gem_pivot = empty('Rhombus_pivot', root)


def rhombus(name, centre, h, w, d, parent, tilt):
    cx, cz = centre
    ca, sa = math.cos(tilt), math.sin(tilt)
    def q(x, z):
        return (cx + x * ca + z * sa, 0, cz - x * sa + z * ca)
    V = [q(0, h), q(w, 0), q(0, -h), q(-w, 0), (cx, -d, cz), (cx, d, cz)]
    F = [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4), (1, 0, 5), (2, 1, 5), (3, 2, 5), (0, 3, 5)]
    g = mesh(name, V, F, [STAR], parent)
    # silver outline: slightly larger flat rhombus behind
    s = 1.22
    V2 = [q(0, h * s), q(w * s, 0), q(0, -h * s), q(-w * s, 0)]
    V2 = [(x, .0015, z) for x, _, z in V2]
    mesh(name + '_rim', V2, [(0, 1, 2, 3)], [SILVER], parent)
    sparkle(name + '_star', (cx, -d - .0006, cz), .007, parent)
    return g


rhombus('Rhombus_a', (-.085, .145), .028, .017, .009, gem_pivot, D(-18))
rhombus('Rhombus_b', (.085, -.145), .028, .017, .009, gem_pivot, D(-18))

# ------------------------------------------------------------------ ice shards
shard_pivot = empty('Shards_pivot', root)
for i, (x, z, tilt) in enumerate([(-.125, -.035, 35), (.125, .035, 215), (-.105, .06, -20), (.11, -.075, 160)]):
    ln, wd = (.032, .008) if i < 2 else (.022, .006)
    ca, sa = math.cos(D(tilt)), math.sin(D(tilt))
    def q(u, v):
        return (x + u * ca + v * sa, 0, z - u * sa + v * ca)
    V = [q(ln, 0), q(0, wd), q(-ln * .6, 0), q(0, -wd), (x, -.004, z), (x, .004, z)]
    V = [V[0], V[1], V[2], V[3], V[4], V[5]]
    F = [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4), (1, 0, 5), (2, 1, 5), (3, 2, 5), (0, 3, 5)]
    mesh('Ice_shard_%d' % i, V, F, [ICE], shard_pivot)

# ------------------------------------------------------------------ sapphire core
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=.088)
core = bpy.context.object
core.name = 'Sapphire_core'
for c in list(core.users_collection):
    c.objects.unlink(core)
col.objects.link(core)
core.parent = root
core.data.materials.append(SAPPHIRE)
attr = core.data.attributes.new('facet', 'FLOAT', 'FACE')
light_dir = Vector((-.5, -.7, .5)).normalized()
for p in core.data.polygons:
    p.use_smooth = False
    # facets facing the key light are brighter, plus a random cut variation -> gem sparkle
    k = .5 + .5 * p.normal.dot(light_dir)
    attr.data[p.index].value = min(1, max(0, .04 + .80 * k ** 3 + rng.uniform(-.14, .14)))

# convert text to mesh
for o in list(col.objects):
    if o.type == 'FONT':
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.convert(target='MESH')

# ------------------------------------------------------------------ animation (12 s loop @30fps)
scene.render.fps = 30
scene.frame_start, scene.frame_end = 1, 361
for pivot, axis, turns in ((band_pivot, 0, 1), (blade_pivot, 0, -1), (gem_pivot, 1, 1)):
    pivot.rotation_euler[axis] = 0
    pivot.keyframe_insert('rotation_euler', frame=1, index=axis)
    pivot.rotation_euler[axis] = 2 * math.pi * turns
    pivot.keyframe_insert('rotation_euler', frame=361, index=axis)
for f in range(1, 362, 45):
    shard_pivot.location.z = .006 * math.sin(2 * math.pi * (f - 1) / 360)
    shard_pivot.keyframe_insert('location', frame=f, index=2)
for pivot in (band_pivot, blade_pivot, gem_pivot):
    for layer in pivot.animation_data.action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    for kp in fc.keyframe_points:
                        kp.interpolation = 'LINEAR'
scene.frame_set(1)

# ------------------------------------------------------------------ game export (CLOCK_EXPORT=1)
if EXPORT:
    import bmesh
    # kind ids (see assets/model/forge-blades/ClockCatalyst.shader): 0 star-metal band, 1 silver, 2 gold sparkle,
    # 3 white numeral, 4 glass blade, 5 sapphire (a = facet brightness), 6 ice shard
    def kind_of(name):
        if name.startswith('Numeral'):
            return 3
        if name.startswith('Band_sparkle') or name.endswith('_star'):
            return 2
        if name.startswith(('Rim', 'Bar', 'Blade_edge')) or name.endswith('_rim'):
            return 1
        if name.startswith('Band_') or name.startswith('Rhombus'):
            return 0
        if name.startswith('Blade_'):
            return 4
        if name.startswith('Sapphire'):
            return 5
        if name.startswith('Ice'):
            return 6
        raise ValueError(name)
    # single-sided sheets are emitted twice (both windings); closed solids are re-oriented outward
    SHEET = ('Band_sparkle', 'Rhombus_a_rim', 'Rhombus_b_rim', 'Rhombus_a_star', 'Rhombus_b_star')
    def collect(parents):
        out, dg = [], bpy.context.evaluated_depsgraph_get()
        for o in col.objects:
            if o.type != 'MESH':
                continue
            p_ = o.parent
            while p_ is not None and p_ not in parents:
                p_ = p_.parent
            if p_ is None:
                continue
            ob = o.evaluated_get(dg)
            me = ob.to_mesh()
            bm = bmesh.new(); bm.from_mesh(me)
            bmesh.ops.triangulate(bm, faces=bm.faces[:])
            sheet = o.name.startswith(SHEET)
            if not sheet:
                bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            kind = kind_of(o.name)
            facet = bm.faces.layers.float.get('facet') if kind == 5 else None
            M = o.matrix_world
            for f in bm.faces:
                pts = [M @ v.co for v in f.verts]
                n = ((pts[1] - pts[0]).cross(pts[2] - pts[0])).normalized()
                a = f[facet] if facet else 1.0
                tris = [(pts, n)]
                if sheet:
                    tris.append(([pts[0], pts[2], pts[1]], -n))
                for pp, nn in tris:
                    for q in pp:
                        out.append([q.x, q.z, q.y, nn.x, nn.z, nn.y, kind, a])   # game axes: (bx, bz, by)
            bm.free()
            ob.to_mesh_clear()
        return out
    groups = {'bands': [band_pivot], 'blades': [blade_pivot], 'gems': [gem_pivot], 'shards': [shard_pivot], 'core': [root]}
    result = {}
    for gname, parents in groups.items():
        if gname == 'core':
            # core is a direct child of root: collect only Sapphire_core
            dg = bpy.context.evaluated_depsgraph_get()
            rows = []
            o = bpy.data.objects['Sapphire_core']
            ob = o.evaluated_get(dg); me = ob.to_mesh()
            bm = bmesh.new(); bm.from_mesh(me)
            bmesh.ops.triangulate(bm, faces=bm.faces[:])
            fl = bm.faces.layers.float.get('facet')
            for f in bm.faces:
                pts = [v.co.copy() for v in f.verts]
                n = ((pts[1] - pts[0]).cross(pts[2] - pts[0])).normalized()
                a = f[fl] if fl else 1.0
                for q in pts:
                    rows.append([q.x, q.z, q.y, n.x, n.z, n.y, 5, a])
            bm.free(); ob.to_mesh_clear()
            result[gname] = rows
        else:
            result[gname] = collect(parents)
    (OUT / 'clock_catalyst_game.json').write_text(json.dumps(result))
    print('EXPORT', {k: len(v) // 3 for k, v in result.items()})
    raise SystemExit(0)

# ------------------------------------------------------------------ studio (matches the reference sheet)
scene.render.engine = 'BLENDER_EEVEE'
scene.eevee.use_raytracing = True
scene.eevee.taa_render_samples = 64
scene.view_settings.view_transform = 'Standard'
world = bpy.data.worlds.new('Studio'); scene.world = world; world.use_nodes = True
wt = world.node_tree
bg = wt.nodes['Background']; bg.inputs['Color'].default_value = (.42, .45, .55, 1); bg.inputs['Strength'].default_value = .55
cam_bg = wt.nodes.new('ShaderNodeBackground'); cam_bg.inputs['Color'].default_value = (.80, .82, .87, 1)
lp = wt.nodes.new('ShaderNodeLightPath'); mx = wt.nodes.new('ShaderNodeMixShader')
link(wt, lp.outputs['Is Camera Ray'], mx.inputs['Fac'])
link(wt, bg.outputs['Background'], mx.inputs[1])
link(wt, cam_bg.outputs['Background'], mx.inputs[2])
link(wt, mx.outputs['Shader'], wt.nodes['World Output'].inputs['Surface'])
for name, loc, energy, colour, size in (('Key', (-1.4, -2.4, 1.7), 120, (1, .97, .94), 1.6),
                                        ('Fill', (2.0, -1.8, -.2), 35, (.82, .88, 1), 2.4),
                                        ('Rim', (.6, 2.2, 1.4), 160, (.70, .82, 1), 1.4)):
    ld = bpy.data.lights.new(name, 'AREA'); ld.energy, ld.color, ld.size = energy, colour, size
    lo = bpy.data.objects.new(name, ld); scene.collection.objects.link(lo); lo.location = loc
    lo.rotation_euler = (-Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
tree = bpy.data.node_groups.new('Comp', 'CompositorNodeTree')
tree.interface.new_socket('Image', in_out='OUTPUT', socket_type='NodeSocketColor')
rl = tree.nodes.new('CompositorNodeRLayers'); gl = tree.nodes.new('CompositorNodeGlare'); go = tree.nodes.new('NodeGroupOutput')
gl.inputs['Type'].default_value = 'Fog Glow'; gl.inputs['Quality'].default_value = 'High'
gl.inputs['Strength'].default_value = .25; gl.inputs['Size'].default_value = .2; gl.inputs['Threshold'].default_value = 1.0
link(tree, rl.outputs['Image'], gl.inputs['Image']); link(tree, gl.outputs['Image'], go.inputs['Image'])
scene.compositing_node_group = tree

cd = bpy.data.cameras.new('Cam'); cd.type = 'ORTHO'; cd.ortho_scale = .66
cam = bpy.data.objects.new('Cam', cd); scene.collection.objects.link(cam); scene.camera = cam


def shoot(name, loc, w=1200, h=1200):
    cam.location = loc
    cam.rotation_euler = (-Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    scene.render.resolution_x, scene.render.resolution_y = w, h
    scene.render.filepath = str(OUT / (name + '.png'))
    bpy.ops.render.render(write_still=True)


meshes = [o for o in col.objects if o.type == 'MESH']
report = {'version': 6, 'triangles': sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes),
          'mesh_count': len(meshes), 'band_radius_m': R_BAND, 'core_radius_m': .088, 'loop_seconds': 12,
          'motion': 'bands +360 about X, blades -360 about X, rhombus gems +360 about Y (front plane), shards bob'}
(OUT / 'model-report.json').write_text(json.dumps(report, indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'clock_catalyst.blend'))
shoot('front', (0, -3, 0))
shoot('hero', (-.9, -2.7, .7))
shoot('right', (3, 0, 0), 800, 800)
shoot('top', (0, -.00001, 3), 800, 800)
if os.environ.get('CLOCK_STILLS_ONLY') != '1':
    for f in range(1, 361, 6):
        scene.frame_set(f)
        shoot('frames/%03d' % f, (-.9, -2.7, .7), 640, 640)
print('PASS clock catalyst v6 ' + json.dumps(report))
