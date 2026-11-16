"""Blender headless preview of a generated weapon JSON (not used by the game).
blender -b -P art/weapon_gen/preview_blender.py -- in.json out_prefix
Sapphire colours are a schematic of the real facets, NOT a shader preview. Urho (x,y,z)->Blender (x,z,y), winding reversed.
"""
import bpy, json, sys, math
from mathutils import Vector

argv = sys.argv[sys.argv.index('--')+1:]
src, prefix = argv[0], argv[1]
data = json.load(open(src))

def lin(c):  # sRGB -> linear
    return tuple((v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4) for v in c)

PAL = {'blade': (.96, .99, 1.0), 'metal': (1.0, .84, .43), 'accent': (.015, .46, .98), 'grip': (.08, .15, .36)}

bpy.ops.wm.read_factory_settings(use_empty=True)
verts, faces, cols = [], [], []
for t in data['tris']:
    base = len(verts)
    for q in t['p']:
        verts.append((q[0], q[2], q[1]))
    faces.append((base, base+2, base+1))
    r, g, b = t['c']; k = max(0, 1-r-g-b)
    rgb = [r*PAL['blade'][i]+g*PAL['metal'][i]+b*PAL['accent'][i]+k*PAL['grip'][i] for i in range(3)]
    sh = t['shade']
    rgb = [min(1, v*sh) for v in rgb]
    if t['glow'] > 0 or (b > .32 and r > .5):
        # Illustrative deep/mid/bright blue cut faces. The Web material adds
        # absorption, view-dependent returns and specular; Workbench cannot.
        p0,p1,p2=[Vector(q) for q in t['p']]
        normal=(p1-p0).cross(p2-p0).normalized()
        response=max(0,min(1,.5+normal.x*.7+normal.y*.22))
        tone=max(0,min(1,.18+.55*response+(sh-.82)*1.2))
        deep=(.012,.10,.38);middle=(.015,.46,.94);bright=(.025,.72,1.0)
        rgb=[deep[i]*(1-tone)+middle[i]*tone for i in range(3)]
        rgb=[rgb[i]*.88+bright[i]*response*.12 for i in range(3)]
    cols.append(lin(rgb))

mesh = bpy.data.meshes.new('m'); mesh.from_pydata(verts, [], faces); mesh.update()
attr = mesh.color_attributes.new('Col', 'FLOAT_COLOR', 'CORNER')
for fi, poly in enumerate(mesh.polygons):
    for li in poly.loop_indices:
        attr.data[li].color = (*cols[fi], 1)
ob = bpy.data.objects.new('sword', mesh); bpy.context.scene.collection.objects.link(ob)
for p in mesh.polygons: p.use_smooth = False

sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sh = sc.display.shading
sh.light = 'FLAT'; sh.color_type = 'VERTEX'; sh.show_cavity = False
sh.show_object_outline = True; sh.object_outline_color = (.05, .09, .25)
sc.display.render_aa = '16'
sc.view_settings.view_transform = 'Standard'
sc.world = bpy.data.worlds.new('w'); sc.world.color = (.8, .8, .82)
sc.render.film_transparent = True
sc.render.resolution_x, sc.render.resolution_y = 520, 1100

cam = bpy.data.cameras.new('c'); cam.type = 'ORTHO'
co = bpy.data.objects.new('cam', cam); sc.collection.objects.link(co); sc.camera = co
h = data['meta']['height']; mid = (data['meta']['bounds']['min'][1]+data['meta']['bounds']['max'][1])/2
cam.ortho_scale = h*1.08
views = {'front': (0, -5, mid, 0), 'back': (0, 5, mid, 180), 'side': (5, 0, mid, 90)}
for name, (x, y, z, rz) in views.items():
    co.location = (x, y, z)
    co.rotation_euler = (math.radians(90), 0, math.radians(rz))
    sc.render.filepath = f'{prefix}_{name}.png'
    bpy.ops.render.render(write_still=True)
# 3/4 view, perspective
cam.type = 'PERSP'; cam.lens = 70
sc.render.resolution_x, sc.render.resolution_y = 900, 1100
co.location = (2.6, -4.2, mid+.2)
d = Vector((0, 0, mid)) - co.location
co.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
sc.render.filepath = f'{prefix}_iso.png'
bpy.ops.render.render(write_still=True)
