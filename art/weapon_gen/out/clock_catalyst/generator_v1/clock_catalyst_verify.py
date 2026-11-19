"""Independent Blender round-trip verification of the delivered GLB."""
import bpy, json, os, math
from mathutils import Vector
OUT=os.path.abspath('art/weapon_gen/out/clock_catalyst')
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=OUT+'/clock_catalyst.glb')
scene=bpy.context.scene;scene.render.fps=30
objects=list(scene.objects);meshes=[o for o in objects if o.type=='MESH']
assert len(meshes)==5, 'Expected one mesh per controller including shared axle'
names=['01_OUTER_MERIDIAN','02_MIDDLE_MERIDIAN','03_INNER_MERIDIAN','04_DIAL_SPIN']
controllers=[bpy.data.objects[n] for n in names]
report={'meshes':len(meshes),'materials':len(bpy.data.materials),'poses':[]}
rotations=[]
for frame in [1,31,61,121,181,240]:
    scene.frame_set(frame);bpy.context.view_layer.update()
    current=[]
    for o in controllers:
        assert o.matrix_world.translation.length<1e-5,'Pivot drift: '+o.name
        # Imported glTF is restored to Blender Z-up.
        axis=o.matrix_world.to_3x3()@Vector((0,0,1))
        assert (axis-Vector((0,0,1))).length<1e-4,'Axis not vertical: '+o.name
        current.append(list(o.matrix_world.to_quaternion()))
    rotations.append(current)
    points=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
    bounds=[[min(p[i] for p in points),max(p[i] for p in points)] for i in range(3)]
    assert all(math.isfinite(x) for pair in bounds for x in pair)
    assert max(abs(x) for pair in bounds for x in pair)<.27
    report['poses'].append({'frame':frame,'bounds_m':bounds,'rotation_quaternions':current})
for j in [1,2,3]:
    assert any(abs(a-b)>.1 for a,b in zip(rotations[0][j],rotations[1][j])), 'Missing animation: '+names[j]
assert all(abs(a-b)<1e-5 for a,b in zip(rotations[0][0],rotations[1][0]))
report['result']='PASS: 3 meridians, 5 meshes, common vertical pivots, 3 independent animations, finite bounds'
with open(OUT+'/roundtrip-report.json','w') as f:json.dump(report,f,indent=2)
print(report['result'])
