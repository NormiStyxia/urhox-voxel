"""Clock catalyst remake: spherical core inside three projected clock frames.
Blender Z-up, horizontal X ring axis. Output is a separate v4 review asset.
"""
import json
import math
import os
import random
import struct
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

OUTPUT = Path('art/weapon_gen/out/clock_catalyst_v4').resolve()
OUTPUT.mkdir(parents=True, exist_ok=True)
(OUTPUT/'frames').mkdir(exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
model = bpy.data.collections.new('Clock_Catalyst_V4')
scene.collection.children.link(model)

def empty(name, parent=None):
    obj = bpy.data.objects.new(name, None)
    model.objects.link(obj)
    obj.parent = parent
    return obj

root = empty('ClockCatalyst_ROOT')
root['units'] = 'metres'
root['design'] = 'Blue-white sphere surrounded by three open projected Roman clocks'

def mesh(name, vertices, faces, materials, parent=root, material_indices=None):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    model.objects.link(obj)
    obj.parent = parent
    for material in materials:
        data.materials.append(material)
    if material_indices:
        for polygon, index in zip(data.polygons, material_indices):
            polygon.material_index = index
    return obj

def light_material(name, colour, alpha=1, strength=1):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = (*colour, alpha)
    shader = material.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*colour, 1)
    shader.inputs['Roughness'].default_value = .9
    shader.inputs['Alpha'].default_value = alpha
    shader.inputs['Emission Color'].default_value = (*colour, 1)
    shader.inputs['Emission Strength'].default_value = strength
    material.surface_render_method = 'DITHERED'
    material.use_backface_culling = False
    return material

ice = light_material('Projection_ice_blue', (.12, .52, 1), .72, 1.5)
white = light_material('Projection_white_light', (.62, .84, 1), .9, 1.35)
blue = light_material('Projection_cobalt_edge', (.025, .18, .58), .7, 1.1)
gold = light_material('Projection_small_gold_marks', (.9, .66, .25), .85, 1.2)
feather_white = light_material('Feather_white', (.55, .81, 1), .62, 1.3)
feather_blue = light_material('Feather_blue', (.12, .43, .82), .35, 1.1)
dust_blue = light_material('Dust_blue', (.15, .53, 1), .8, 1.6)
dust_white = light_material('Dust_white', (.63, .85, 1), .9, 1.8)

# One visible sphere. Its baked colour texture is also exported to glTF.
core_material = bpy.data.materials.new('Core_blue_white_cloud')
core_material.use_nodes = True
core_shader = core_material.node_tree.nodes.get('Principled BSDF')
core_shader.inputs['Roughness'].default_value = .62
core_shader.inputs['Specular IOR Level'].default_value = .25
core_shader.inputs['Emission Strength'].default_value = .16
texture = core_material.node_tree.nodes.new('ShaderNodeTexImage')
texture.image = bpy.data.images.load(str(OUTPUT/'core_blue_white.png'))
texture.image.pack()
core_material.node_tree.links.new(texture.outputs['Color'], core_shader.inputs['Base Color'])
core_material.node_tree.links.new(texture.outputs['Color'], core_shader.inputs['Emission Color'])
bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, radius=.09)
core = bpy.context.object
core.name = 'Core_blue_white_sphere'
for collection in list(core.users_collection):
    collection.objects.unlink(core)
model.objects.link(core)
core.parent = root
core.data.materials.append(core_material)
for polygon in core.data.polygons:
    polygon.use_smooth = True

def arc(name, radius, width, start, stop, parent, material, depth=0):
    count = max(8, round(abs(stop-start)*32))
    vertices = []
    for step in range(count+1):
        angle = start+(stop-start)*step/count
        for distance in (radius-width/2, radius+width/2):
            vertices.append((distance*math.sin(angle), depth, distance*math.cos(angle)))
    faces = [(2*i, 2*i+1, 2*i+3, 2*i+2) for i in range(count)]
    return mesh(name, vertices, faces, [material], parent)

font = bpy.data.fonts.load('/System/Library/Fonts/Supplemental/Times New Roman.ttf')
labels = ['XII','I','II','III','IV','V','VI','VII','VIII','IX','X','XI']
ring_controls = []
radii = [.25, .224, .198]
sectors = [(-65,65),(115,245)]
for index, (radius, phase) in enumerate(zip(radii, [0,60,120])):
    controller = empty('Clock_frame_%d'%(index+1), root)
    controller.rotation_euler.x = math.radians(phase)
    controller['axis'] = 'X'
    controller['radius_m'] = radius
    controller['phase_degrees'] = phase
    ring_controls.append(controller)
    width = .026 if index == 0 else .023
    for sector, (start_degrees, stop_degrees) in enumerate(sectors):
        start, stop = math.radians(start_degrees), math.radians(stop_degrees)
        arc('Outer_luminous_edge', radius+width/2, .0016, start, stop, controller, ice)
        arc('Inner_luminous_edge', radius-width/2, .0008, start, stop, controller, white)
        arc('Blue_secondary_trace', radius+width/2+.003, .0005, start+.04, stop-.04, controller, blue)
        # Small end marks, leaving the entire interior of each dial empty.
        for end in (start,stop):
            radial = Vector((math.sin(end),0,math.cos(end)))
            tangent = Vector((math.cos(end),0,-math.sin(end)))
            centre = radial*radius
            vertices = [tuple(centre+radial*width*.48), tuple(centre+tangent*.002),
                        tuple(centre-radial*width*.48), tuple(centre-tangent*.002)]
            mesh('Gold_terminal_mark', vertices, [(0,1,2,3)], [gold], controller)
    for mark in range(60):
        degrees = mark*6
        normalized = degrees if degrees<=245 else degrees-360
        if not any(start<=normalized<=stop for start,stop in sectors):
            continue
        angle = math.radians(degrees)
        radial = Vector((math.sin(angle),0,math.cos(angle)))
        tangent = Vector((math.cos(angle),0,-math.sin(angle)))
        outer = radius+width/2-.002
        inner = outer-(.0034 if mark%5==0 else .0017)
        half_width = .00045 if mark%5==0 else .00022
        vertices = [tuple(radial*inner-tangent*half_width), tuple(radial*outer-tangent*half_width),
                    tuple(radial*outer+tangent*half_width), tuple(radial*inner+tangent*half_width)]
        mesh('Projected_tick',vertices,[(0,1,2,3)],[white],controller)
    for hour, label in enumerate(labels):
        degrees = hour*30
        normalized = degrees if degrees<=245 else degrees-360
        if not any(start<=normalized<=stop for start,stop in sectors):
            continue
        angle = math.radians(degrees)
        radial = Vector((math.sin(angle),0,math.cos(angle)))
        tangent = Vector((math.cos(angle),0,-math.sin(angle)))
        normal = Vector((0,-1,0))
        curve = bpy.data.curves.new('Roman_'+label,'FONT')
        curve.body = label
        curve.font = font
        curve.align_x = 'CENTER'
        curve.align_y = 'CENTER'
        curve.size = .025 if index == 0 else .021
        curve.resolution_u = 3
        obj = bpy.data.objects.new('Clock_%d_%s'%(index+1,label),curve)
        model.objects.link(obj)
        obj.parent = controller
        obj.location = radial*(radius-.001)+normal*.0001
        obj.rotation_mode = 'QUATERNION'
        obj.rotation_quaternion = Matrix((tangent,radial,normal)).transposed().to_quaternion()
        curve.materials.append(white)

# Rear-biased galaxy dust, built as two translucent/solid meshes rather than a strip.
dust_control = empty('FX_star_sand', root)
randomizer = random.Random(88)
dust_vertices, dust_faces, dust_indices = [], [], []
for index in range(230):
    angle = randomizer.uniform(-.4,3.6)
    radius = .275+randomizer.gauss(0,.018)
    position = Vector((radius*math.cos(angle), .09+randomizer.uniform(0,.12),
                       radius*.75*math.sin(angle)-.015))
    size = randomizer.uniform(.00035,.0011)
    offset = len(dust_vertices)
    dust_vertices.extend([tuple(position+Vector(delta)*size) for delta in
                          [(1,0,0),(-1,0,0),(0,1,0),(0,0,1),(0,0,-1)]])
    for triangle in [(0,2,3),(2,1,3),(1,0,3),(2,0,4),(1,2,4),(0,1,4)]:
        dust_faces.append(tuple(offset+i for i in triangle))
        dust_indices.append(1 if index%5==0 else 0)
mesh('Loose_stellar_grains',dust_vertices,dust_faces,[dust_blue,dust_white],dust_control,dust_indices)

haze_material = light_material('Dust_soft_cloud',(.1,.4,1),1,.8)
haze_shader = haze_material.node_tree.nodes.get('Principled BSDF')
haze_texture = haze_material.node_tree.nodes.new('ShaderNodeTexImage')
haze_texture.image = bpy.data.images.load(str(OUTPUT/'stardust_haze.png'))
haze_texture.image.pack()
for output_name,input_name in [('Color','Base Color'),('Color','Emission Color'),('Alpha','Alpha')]:
    haze_material.node_tree.links.new(haze_texture.outputs[output_name],haze_shader.inputs[input_name])
vertices, faces = [], []
for index in range(25):
    angle = randomizer.uniform(.05,3.3)
    radius = .27+randomizer.gauss(0,.012)
    centre = Vector((radius*math.cos(angle),.17,radius*.75*math.sin(angle)-.015))
    half_size = randomizer.uniform(.022,.047)
    offset = len(vertices)
    vertices.extend([tuple(centre+Vector((x,0,z))*half_size) for x,z in [(-1,-1),(1,-1),(1,1),(-1,1)]])
    faces.append(tuple(offset+j for j in range(4)))
haze = mesh('Scattered_haze_patches',vertices,faces,[haze_material],dust_control)
uv = haze.data.uv_layers.new(name='UVMap')
for polygon in haze.data.polygons:
    for loop_index, coordinate in zip(polygon.loop_indices,[(0,0),(1,0),(1,1),(0,1)]):
        uv.data[loop_index].uv = coordinate

feather_controls = []
for index, (position, tilt) in enumerate([((-.265,.05,.13),-.55),((.245,.1,-.16),.9)]):
    controller = empty('FX_feather_%d'%index,root)
    controller.location = position
    controller.rotation_euler.y = tilt
    feather_controls.append(controller)
    vertices, faces, material_indices = [], [], []
    def feather_point(t, side):
        width = .009*max(0,math.sin(math.pi*t))**.8
        return (.007*t*t+side*width, .002*math.sin(math.pi*t), .052*(t-.5))
    for side in [-1,1]:
        for barb in range(17):
            t = barb/18
            offset = len(vertices)
            vertices.extend([feather_point(t,0),feather_point(min(1,t+.11),side),
                             feather_point(min(1,t+.155),side),feather_point(t+.047,0)])
            faces.append(tuple(offset+j for j in range(4)))
            material_indices.append(0 if side==1 else 1)
    for segment in range(24):
        start = Vector(feather_point(segment/24,0))
        end = Vector(feather_point((segment+1)/24,0))
        offset = len(vertices)
        vertices.extend([tuple(start+Vector((dx,0,0))) for dx in [-.0003,.0003]])
        vertices.extend([tuple(end+Vector((dx,0,0))) for dx in [.0003,-.0003]])
        faces.append(tuple(offset+j for j in range(4)))
        material_indices.append(0)
    mesh('Feather_barbs_%d'%index,vertices,faces,[feather_white,feather_blue],controller,material_indices)

# Convert glyphs and join each frame separately, preserving three independent pivots.
for obj in list(model.objects):
    if obj.type == 'FONT':
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.convert(target='MESH')
for controller in ring_controls:
    children = [obj for obj in model.objects if obj.parent==controller and obj.type=='MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for obj in children:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = children[0]
    bpy.ops.object.join()
    bpy.context.object.name = controller.name+'_projection'

scene.render.fps = 30
scene.frame_start, scene.frame_end = 1, 361
for controller in ring_controls:
    start = controller.rotation_euler.x
    controller.keyframe_insert(data_path='rotation_euler',frame=1,index=0)
    controller.rotation_euler.x = start+2*math.pi
    controller.keyframe_insert(data_path='rotation_euler',frame=361,index=0)
for index, controller in enumerate(feather_controls+[dust_control]):
    original = controller.location.copy()
    for frame in range(1,362,30):
        phase = 2*math.pi*(frame-1)/360
        controller.location = original+Vector((.003*math.sin(phase),0,.006*math.sin(phase+index)-.006*math.sin(index)))
        controller.keyframe_insert(data_path='location',frame=frame)
for controller in ring_controls+feather_controls+[dust_control]:
    action = controller.animation_data.action
    curves = [curve for layer in action.layers for strip in layer.strips for bag in strip.channelbags for curve in bag.fcurves]
    for curve in curves:
        for key in curve.keyframe_points:
            key.interpolation = 'LINEAR' if controller in ring_controls else 'BEZIER'
scene.frame_set(1)

scene.render.engine = 'CYCLES'
scene.cycles.samples = 20
scene.cycles.transparent_max_bounces = 20
scene.render.resolution_x = scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.render.film_transparent = False
scene.world = bpy.data.worlds.new('Deep_blue_world')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.013,.022,.046,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value = .5
scene.view_settings.view_transform = 'Standard'
for name, position, energy, size in [('Key',(-.5,-.5,.7),6,.55),('Rim',(.4,.3,.15),3,.3)]:
    light = bpy.data.lights.new(name,'AREA')
    light.energy, light.shape, light.size = energy,'DISK',size
    obj = bpy.data.objects.new(name,light)
    scene.collection.objects.link(obj)
    obj.location = position
    obj.rotation_euler = (-obj.location).to_track_quat('-Z','Y').to_euler()
camera_data = bpy.data.cameras.new('Review_camera')
camera = bpy.data.objects.new('Review_camera',camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
camera_data.type = 'ORTHO'
camera_data.ortho_scale = .73
def set_camera(position):
    camera.location = position
    camera.rotation_euler = (-camera.location).to_track_quat('-Z','Y').to_euler()
set_camera((.27,-3,.5))

# Scene-level bloom is restrained; geometry/material emission also remains in GLB.
compositor = bpy.data.node_groups.new('Subtle_projection_bloom','CompositorNodeTree')
compositor.interface.new_socket(name='Image',in_out='OUTPUT',socket_type='NodeSocketColor')
render_layer = compositor.nodes.new('CompositorNodeRLayers')
glare = compositor.nodes.new('CompositorNodeGlare')
glare.inputs['Type'].default_value = 'Fog Glow'
glare.inputs['Quality'].default_value = 'High'
glare.inputs['Strength'].default_value = .22
glare.inputs['Size'].default_value = .25
glare.inputs['Threshold'].default_value = 1.2
output = compositor.nodes.new('NodeGroupOutput')
compositor.links.new(render_layer.outputs['Image'],glare.inputs['Image'])
compositor.links.new(glare.outputs['Image'],output.inputs['Image'])
scene.compositing_node_group = compositor

meshes = [obj for obj in model.objects if obj.type=='MESH']
report = {'version':4,'core_count':1,'core_radius_m':.09,'frame_count':3,
          'frame_radii_m':radii,'frame_axis':'X','phase_degrees':[0,60,120],
          'animation_seconds':12,'preview_frames':60,'preview_duration_ms':200,
          'sphere_texture':'core_blue_white.png','frame_geometry':'open edges, ticks and Roman numerals',
          'mesh_count':len(meshes),'triangles':sum(sum(len(p.vertices)-2 for p in obj.data.polygons) for obj in meshes)}
(OUTPUT/'model-report.json').write_text(json.dumps(report,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT/'clock_catalyst.blend'))
bpy.ops.object.select_all(action='DESELECT')
for obj in model.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = root
model_path = OUTPUT/'clock_catalyst.glb'
bpy.ops.export_scene.gltf(filepath=str(model_path),export_format='GLB',use_selection=True,
                          export_animations=True,export_frame_range=True,export_force_sampling=True)
raw = model_path.read_bytes()
json_length = struct.unpack_from('<I',raw,12)[0]
document = json.loads(raw[20:20+json_length])
binary_tail = bytearray(raw[20+json_length:])
combined = {'name':'Clock_12_second_loop','channels':[],'samplers':[]}
for clip in document.get('animations',[]):
    offset = len(combined['samplers'])
    combined['samplers'].extend(clip['samplers'])
    for channel in clip['channels']:
        channel['sampler'] += offset
        combined['channels'].append(channel)
document['animations'] = [combined]
# Exported keyframes start at Blender frame 1. Shift the common timeline to zero.
inputs = {sampler['input'] for sampler in combined['samplers']}
start_time = min(document['accessors'][index]['min'][0] for index in inputs)
for index in inputs:
    accessor = document['accessors'][index]
    assert accessor['componentType']==5126 and accessor['type']=='SCALAR'
    view = document['bufferViews'][accessor['bufferView']]
    offset = 8+view.get('byteOffset',0)+accessor.get('byteOffset',0)
    stride = view.get('byteStride',4)
    for sample in range(accessor['count']):
        position = offset+sample*stride
        value = struct.unpack_from('<f',binary_tail,position)[0]
        struct.pack_into('<f',binary_tail,position,max(0,value-start_time))
    accessor['min'] = [accessor['min'][0]-start_time]
    accessor['max'] = [accessor['max'][0]-start_time]
payload = json.dumps(document,separators=(',',':')).encode()
payload += b' '*(-len(payload)%4)
model_path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(payload)+len(binary_tail))
                      +struct.pack('<II',len(payload),0x4e4f534a)+payload+bytes(binary_tail))
for name, position in [('hero',(.27,-3,.5)),('front',(0,-3,0)),('right',(3,0,0)),('top',(0,-.00001,3))]:
    set_camera(position)
    scene.render.filepath = str(OUTPUT/(name+'.png'))
    bpy.ops.render.render(write_still=True)
if os.environ.get('CLOCK_STILLS_ONLY')!='1':
    scene.render.resolution_x = scene.render.resolution_y = 640
    scene.cycles.samples = 8
    set_camera((.27,-3,.5))
    for frame in range(1,361,6):
        scene.frame_set(frame)
        scene.render.filepath = str(OUTPUT/'frames'/('%03d.png'%frame))
        bpy.ops.render.render(write_still=True)
print('PASS clock catalyst v4 build/export/render '+json.dumps(report))
