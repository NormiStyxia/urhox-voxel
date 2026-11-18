"""Clock catalyst v5: v4 structure (three projected Roman clock frames, horizontal X axis, 12 s loop)
with a TRANSPARENT faceted crystal core and the wing-sword / thorn-bow look (Eevee, light grey studio,
white + cobalt + small gold accents, crisp faceted crystal). Run:
  Blender -b --factory-startup -P art/weapon_gen/clock_catalyst_v5_blender.py   (CLOCK_STILLS_ONLY=1 skips frames)
"""
import json
import math
import os
import random
import struct
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

OUTPUT = Path('art/weapon_gen/out/clock_catalyst_v5').resolve()
OUTPUT.mkdir(parents=True, exist_ok=True)
(OUTPUT/'frames').mkdir(exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
model = bpy.data.collections.new('Clock_Catalyst_V5')
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

ice = light_material('Projection_cobalt_rim', (.03, .20, .72), 1.0, .55)
white = light_material('Projection_cobalt_numerals', (.03, .22, .80), 1.0, .6)
blue = light_material('Projection_ice_trace', (.30, .66, 1.0), .8, 1.3)
gold = light_material('Projection_gold_marks', (.88, .62, .20), 1.0, .25)
film = light_material('Projection_white_film', (.80, .91, 1.0), .10, .45)
feather_white = light_material('Feather_white', (.55, .81, 1), .62, 1.3)
feather_blue = light_material('Feather_blue', (.12, .43, .82), .35, 1.1)
dust_blue = light_material('Dust_blue', (.15, .53, 1), .8, 1.6)
dust_white = light_material('Dust_white', (.63, .85, 1), .9, 1.8)

# Transparent faceted crystal sphere (same language as the wing-sword sapphire / thorn-bow amethyst):
# flat-shaded icosphere cuts, clear transmission with an ice-blue tint, glowing blue-white heart inside.
core_material = bpy.data.materials.new('Core_clear_crystal')
core_material.use_nodes = True
nt = core_material.node_tree
cs = nt.nodes.get('Principled BSDF')
# Stylised transparency (same idea as the in-game blend_mix crystal pass): faces looking at the camera are
# clear, grazing faces/rims thicken to ice blue; small self-light keeps it from going grey.
cs.inputs['Base Color'].default_value = (.16, .46, 1.0, 1)
cs.inputs['Roughness'].default_value = .06
cs.inputs['Specular IOR Level'].default_value = .9
cs.inputs['Coat Weight'].default_value = .6
cs.inputs['Coat Roughness'].default_value = .02
lw = nt.nodes.new('ShaderNodeLayerWeight'); lw.inputs['Blend'].default_value = .35
ramp = nt.nodes.new('ShaderNodeValToRGB')
ramp.color_ramp.elements[0].position = 0.0; ramp.color_ramp.elements[0].color = (.20, .20, .20, 1)   # facing: alpha .16
ramp.color_ramp.elements[1].position = 1.0; ramp.color_ramp.elements[1].color = (.88, .88, .88, 1)   # rim: alpha .78
nt.links.new(lw.outputs['Facing'], ramp.inputs['Fac'])
nt.links.new(ramp.outputs['Color'], cs.inputs['Alpha'])
em = nt.nodes.new('ShaderNodeMath'); em.operation = 'MULTIPLY_ADD'
em.inputs[1].default_value = .7; em.inputs[2].default_value = .08
nt.links.new(lw.outputs['Facing'], em.inputs[0])
nt.links.new(em.outputs['Value'], cs.inputs['Emission Strength'])
cs.inputs['Emission Color'].default_value = (.20, .52, 1.0, 1)
core_material.surface_render_method = 'BLENDED'
core_material.use_transparency_overlap = True
core_material.use_backface_culling = True
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=.09)
core = bpy.context.object
core.name = 'Core_clear_crystal_sphere'
for collection in list(core.users_collection):
    collection.objects.unlink(core)
model.objects.link(core)
core.parent = root
core.data.materials.append(core_material)
for polygon in core.data.polygons:
    polygon.use_smooth = False

heart_material = light_material('Core_heart_glow', (.30, .62, 1.0), 1.0, 1.6)
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=.022)
heart = bpy.context.object
heart.name = 'Core_heart'
for collection in list(heart.users_collection):
    collection.objects.unlink(heart)
model.objects.link(heart)
heart.parent = root
heart.data.materials.append(heart_material)
for polygon in heart.data.polygons:
    polygon.use_smooth = True
star_material = light_material('Core_inner_stars', (.80, .93, 1.0), 1.0, 1.6)
star_random = random.Random(5)
sv, sf = [], []
for _ in range(46):
    d = Vector((star_random.gauss(0, 1), star_random.gauss(0, 1), star_random.gauss(0, 1))).normalized()
    p = d * star_random.uniform(.035, .078)
    s = star_random.uniform(.0006, .0013)
    o = len(sv)
    sv += [tuple(p + Vector(q) * s) for q in [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)]]
    for t in [(0,2,4),(2,1,4),(1,3,4),(3,0,4),(2,0,5),(1,2,5),(3,1,5),(0,3,5)]:
        sf.append(tuple(o + i for i in t))
mesh('Core_inner_stars', sv, sf, [star_material], root)

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
    width = .030 if index == 0 else .026
    for sector, (start_degrees, stop_degrees) in enumerate(sectors):
        start, stop = math.radians(start_degrees), math.radians(stop_degrees)
        arc('Outer_luminous_edge', radius+width/2, .0016, start, stop, controller, ice)
        arc('Inner_luminous_edge', radius-width/2, .0012, start, stop, controller, ice)
        arc('Projection_film', radius, width*.96, start, stop, controller, film, depth=.0002)
        arc('Blue_secondary_trace', radius+width/2+.003, .0005, start+.04, stop-.04, controller, blue)
        # Small end marks, leaving the entire interior of each dial empty.
        for end in (start,stop):
            radial = Vector((math.sin(end),0,math.cos(end)))
            tangent = Vector((math.cos(end),0,-math.sin(end)))
            centre = radial*radius
            vertices = [tuple(centre+radial*width*.48), tuple(centre+tangent*.004),
                        tuple(centre-radial*width*.48), tuple(centre-tangent*.004)]
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
        curve.size = .026 if index == 0 else .022
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

scene.render.engine = 'BLENDER_EEVEE'
scene.eevee.use_raytracing = True
scene.eevee.taa_render_samples = 48
scene.eevee.ray_tracing_options.resolution_scale = '1'
scene.render.resolution_x = scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.render.film_transparent = False
scene.view_settings.view_transform = 'Standard'
world = bpy.data.worlds.new('Studio')
scene.world = world
world.use_nodes = True
wt = world.node_tree
bg = wt.nodes['Background']
bg.inputs['Color'].default_value = (.35, .36, .42, 1)
bg.inputs['Strength'].default_value = .4
backdrop = wt.nodes.new('ShaderNodeBackground'); backdrop.name = 'CameraBackdrop'
DARK = os.environ.get('CLOCK_DARK') == '1'
backdrop.inputs['Color'].default_value = (.016, .024, .05, 1) if DARK else (.70, .70, .73, 1)
lp = wt.nodes.new('ShaderNodeLightPath'); mix = wt.nodes.new('ShaderNodeMixShader')
wt.links.new(lp.outputs['Is Camera Ray'], mix.inputs['Fac'])
wt.links.new(bg.outputs['Background'], mix.inputs[1])
wt.links.new(backdrop.outputs['Background'], mix.inputs[2])
wt.links.new(mix.outputs['Shader'], wt.nodes['World Output'].inputs['Surface'])
for name, position, energy, colour, size in [('Key',(-1.6,-2.4,1.8),110,(1,.97,.94),2.0),
                                             ('Fill',(2.2,-1.5,.2),28,(.86,.9,1),2.5),
                                             ('Rim',(.8,2.4,1.2),200,(.62,.80,1),1.5)]:
    light = bpy.data.lights.new(name,'AREA')
    light.energy, light.color, light.size = energy, colour, size
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
glare.inputs['Strength'].default_value = .30
glare.inputs['Size'].default_value = .25
glare.inputs['Threshold'].default_value = 1.0
output = compositor.nodes.new('NodeGroupOutput')
compositor.links.new(render_layer.outputs['Image'],glare.inputs['Image'])
compositor.links.new(glare.outputs['Image'],output.inputs['Image'])
scene.compositing_node_group = compositor

meshes = [obj for obj in model.objects if obj.type=='MESH']
report = {'version':5,'core':'transparent faceted crystal + glowing heart + inner stars','core_count':1,'core_radius_m':.09,'frame_count':3,
          'frame_radii_m':radii,'frame_axis':'X','phase_degrees':[0,60,120],
          'animation_seconds':12,'preview_frames':60,'preview_duration_ms':200,
          'frame_geometry':'open edges, ticks and Roman numerals',
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
    scene.render.filepath = str(OUTPUT/(name+('_dark' if DARK else '')+'.png'))
    bpy.ops.render.render(write_still=True)
if os.environ.get('CLOCK_STILLS_ONLY')!='1':
    scene.render.resolution_x = scene.render.resolution_y = 640
    scene.cycles.samples = 8
    set_camera((.27,-3,.5))
    for frame in range(1,361,6):
        scene.frame_set(frame)
        scene.render.filepath = str(OUTPUT/'frames'/('%03d.png'%frame))
        bpy.ops.render.render(write_still=True)
print('PASS clock catalyst v5 build/export/render '+json.dumps(report))
