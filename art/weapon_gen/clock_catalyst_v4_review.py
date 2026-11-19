"""GLB round-trip checks, followed by optional animation rendering."""
import json
import math
import os
import struct
from pathlib import Path
import bpy
from mathutils import Vector

output = Path('art/weapon_gen/out/clock_catalyst_v4').resolve()
raw = (output/'clock_catalyst.glb').read_bytes()
length = struct.unpack_from('<I',raw,12)[0]
document = json.loads(raw[20:20+length])
assert len(document['animations'])==1, 'All rotations must share one playable clip'
clip = document['animations'][0]
rotation_channels = [channel for channel in clip['channels'] if channel['target']['path']=='rotation']
assert len(rotation_channels)==3
duration = max(document['accessors'][sampler['input']]['max'][0] for sampler in clip['samplers'])
assert abs(duration-12)<.001, 'Incorrect exported animation duration'
assert len(document.get('images',[]))==2, 'Sphere texture or soft dust alpha missing'
for material in document['materials']:
    if material.get('name','').startswith('Projection_'):
        assert material.get('alphaMode')=='BLEND'
        assert max(material['emissiveFactor'])>0
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(output/'clock_catalyst.glb'))
scene = bpy.context.scene
scene.render.fps = 30
cores = [obj for obj in scene.objects if obj.type=='MESH' and obj.name.startswith('Core_')]
assert len(cores)==1, 'More than one visible core shell'
core = cores[0]
assert max(abs(vertex.co.length-.09) for vertex in core.data.vertices)<.00001, 'Core must be spherical'
controllers = [bpy.data.objects['Clock_frame_%d'%index] for index in range(1,4)]
samples = []
for frame in [1,31,61,121,181,241,301,361]:
    scene.frame_set(frame)
    bpy.context.view_layer.update()
    rotations = []
    for obj in controllers:
        assert obj.matrix_world.translation.length<.00001
        assert (obj.matrix_world.to_3x3()@Vector((1,0,0))-Vector((1,0,0))).length<.0001
        rotations.append(obj.matrix_world.to_quaternion())
    for index in [1,2]:
        difference = rotations[0].rotation_difference(rotations[index]).angle
        difference = min(difference,2*math.pi-difference)
        assert abs(difference-math.radians(60*index))<.001, 'Ring phase changed'
    samples.append([list(rotation) for rotation in rotations])
assert abs(samples[0][0][1]-samples[1][0][1])>.1, 'Ring did not move'
report = {'result':'PASS','core_spheres':1,'texture_images':2,'horizontal_clock_frames':3,
          'phase_degrees':[0,60,120],'clip_seconds':duration,'sampled_poses':len(samples)}
(output/'roundtrip-report.json').write_text(json.dumps(report,indent=2))
print('PASS GLB round-trip '+json.dumps(report))

if os.environ.get('CLOCK_RENDER_ANIMATION')=='1':
    bpy.ops.wm.open_mainfile(filepath=str(output/'clock_catalyst.blend'))
    scene = bpy.context.scene
    scene.render.resolution_x = scene.render.resolution_y = 640
    scene.cycles.samples = 8
    for frame in range(1,361,6):
        scene.frame_set(frame)
        scene.render.filepath = str(output/'frames'/('%03d.png'%frame))
        bpy.ops.render.render(write_still=True)
    print('PASS animation rendered: 60 frames at 0.2 seconds, 12 seconds total')
