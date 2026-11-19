"""Independent Blender round-trip verification of the delivered GLB."""
import bpy, json, os, math, struct, sys
from mathutils import Vector
ARGS=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
OUT=os.path.abspath(ARGS[0] if ARGS else 'art/weapon_gen/out/clock_catalyst_v2')
with open(OUT+'/clock_catalyst.glb','rb') as f:raw=f.read()
length=struct.unpack_from('<I',raw,12)[0];gltf=json.loads(raw[20:20+length])
assert len(gltf['animations'])==1,'Expected one synchronized clip'
rotation_channels=[c for c in gltf['animations'][0]['channels'] if c['target']['path']=='rotation']
assert len(rotation_channels)==4,'Expected all three rings plus dial animated'
projection_materials=[m for m in gltf['materials'] if m.get('name','').startswith('Projection')]
assert len(projection_materials)==4
for m in projection_materials:
    assert m.get('alphaMode')=='BLEND','Projection alpha missing: '+m['name']
    assert m['pbrMetallicRoughness']['baseColorFactor'][3]<1
    assert max(m.get('emissiveFactor',[0]))>0,'Projection emission missing'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=OUT+'/clock_catalyst.glb')
scene=bpy.context.scene;scene.render.fps=30
objects=list(scene.objects);meshes=[o for o in objects if o.type=='MESH']
assert len(meshes)==4, 'Expected three rings plus projection; no support mesh'
names=['01_OUTER_MERIDIAN','02_MIDDLE_MERIDIAN','03_INNER_MERIDIAN','04_DIAL_SPIN']
controllers=[bpy.data.objects[n] for n in names]
report={'meshes':len(meshes),'projection_materials':len(projection_materials),'poses':[]}
rotations=[]
for frame in [1,31,61,121,181,240]:
    scene.frame_set(frame);bpy.context.view_layer.update()
    current=[]
    for i,o in enumerate(controllers):
        assert o.matrix_world.translation.length<1e-5,'Pivot drift: '+o.name
        # Imported glTF is restored to Blender Z-up.
        expected=Vector((1,0,0)) if i<3 else Vector((0,0,1))
        axis=o.matrix_world.to_3x3()@expected
        assert (axis-expected).length<1e-4,'Incorrect rotation axis: '+o.name
        current.append(list(o.matrix_world.to_quaternion()))
    rotations.append(current)
    points=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
    bounds=[[min(p[i] for p in points),max(p[i] for p in points)] for i in range(3)]
    assert all(math.isfinite(x) for pair in bounds for x in pair)
    assert max(abs(x) for pair in bounds for x in pair)<.27
    report['poses'].append({'frame':frame,'bounds_m':bounds,'rotation_quaternions':current})
for j in [0,1,2,3]:
    assert any(abs(a-b)>.1 for a,b in zip(rotations[0][j],rotations[1][j])), 'Missing animation: '+names[j]
report['result']='PASS: 3 horizontal-axis animated rings, unsupported emissive translucent dial, 4 meshes, one synchronized clip'
with open(OUT+'/roundtrip-report.json','w') as f:json.dump(report,f,indent=2)
print(report['result'])
