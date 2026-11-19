"""Articulated clock catalyst. Blender Z-up; exported glTF Y-up, metres.
Three nested circles share a horizontal diameter LINE; a holographic dial floats inside.
Manual hard-surface rebuild of the Mivo source: its sheet-to-3D mesh fused
three views into three props, so it is retained under source/, not shipped.
Run: Blender -b -P this_file -- [output_directory]
"""
import bpy, math, os, sys, json, struct
from mathutils import Vector
from math import sin, cos, pi
ARGS=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
OUT=os.path.abspath(ARGS[0] if ARGS else 'art/weapon_gen/out/clock_catalyst_v2')
os.makedirs(OUT,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
SC=bpy.context.scene
MODEL=bpy.data.collections.new('CLOCK_CATALYST');SC.collection.children.link(MODEL)

def mat(name,color):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    n=m.node_tree.nodes;n.clear();e=n.new('ShaderNodeEmission');e.inputs[0].default_value=(*color,1)
    out=n.new('ShaderNodeOutputMaterial');m.node_tree.links.new(e.outputs[0],out.inputs[0]);return m
NAVY=mat('Ink • midnight blue',(.025,.055,.16))
BLUE=mat('Dial • cobalt',(.035,.22,.65))
SKY=mat('Dial • sky blue',(.19,.58,.94))
WHITE=mat('Dial • porcelain white',(.90,.96,1))
PALE=mat('Dial • ice blue shadow',(.46,.72,.91))
GOLD=mat('Ring • warm gold',(.90,.59,.16))
GOLD_LIGHT=mat('Ring • pale gold bevel',(1,.85,.42))
GOLD_DARK=mat('Ring • ochre side',(.42,.23,.065))

def projection_mat(name,color,alpha,strength):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,alpha);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=1
    p.inputs['Alpha'].default_value=alpha
    p.inputs['Emission Color'].default_value=(*color,1)
    p.inputs['Emission Strength'].default_value=strength
    m.surface_render_method='DITHERED';m.use_backface_culling=False
    return m
HOLO_FILL=projection_mat('Projection • transparent blue field',(.045,.34,.8),.075,.65)
HOLO_BLUE=projection_mat('Projection • luminous cyan blue',(.08,.48,1),.87,1.3)
HOLO_WHITE=projection_mat('Projection • blue white light',(.5,.86,1),.92,1.5)
HOLO_SCAN=projection_mat('Projection • faint scanlines',(.12,.54,1),.16,.8)

def link(ob):
    for c in list(ob.users_collection):c.objects.unlink(ob)
    MODEL.objects.link(ob);return ob
def empty(name,parent=None):
    o=bpy.data.objects.new(name,None);MODEL.objects.link(o);o.parent=parent;return o
ROOT=empty('ClockCatalyst_ROOT')
ROOT['description']='Floating clock armillary; no handle; three shared-axis meridians'
ROOT['axis']='Rings: horizontal +X; dial: Blender +Z / glTF +Y';ROOT['units']='metres'
def mesh(name,v,f,mats,ids=None,parent=ROOT):
    d=bpy.data.meshes.new(name);d.from_pydata(v,[],f);d.update()
    o=bpy.data.objects.new(name,d);MODEL.objects.link(o);o.parent=parent
    for m in mats:d.materials.append(m)
    if ids:
        for p,i in zip(d.polygons,ids):p.material_index=i
    return o

def ring(name,r,w,depth,parent,metal=True,segments=128):
    # Rectangular radial cross section with four chamfers: all true meshes.
    bevel=min(w,depth)*.19
    cross=[(-w/2+bevel,-depth/2),(w/2-bevel,-depth/2),
           (w/2,-depth/2+bevel),(w/2,depth/2-bevel),
           (w/2-bevel,depth/2),(-w/2+bevel,depth/2),
           (-w/2,depth/2-bevel),(-w/2,-depth/2+bevel)]
    v=[((r+q)*sin(2*pi*i/segments),y,(r+q)*cos(2*pi*i/segments))
       for i in range(segments) for q,y in cross]
    f=[];ids=[]
    for i in range(segments):
        for j in range(8):
            f.append((8*i+j,8*((i+1)%segments)+j,8*((i+1)%segments)+(j+1)%8,8*i+(j+1)%8))
            ids.append([0,1,2,2,0,1,2,1][j] if metal else [0,1,2,1,0,1,2,1][j])
    return mesh(name,v,f,[GOLD,GOLD_LIGHT,GOLD_DARK] if metal else [WHITE,PALE,BLUE],ids,parent)

def cylinder(name,r,depth,loc,parent,material,axis='Z',verts=64):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=depth,location=loc)
    o=link(bpy.context.object);o.name=name;o.parent=parent;o.data.materials.append(material)
    if axis=='Y':o.rotation_euler.x=pi/2
    return o

PIVOTS=[]
for i,(r,angle) in enumerate(((.238,0),(.224,65),(.210,-65))):
    p=empty(['01_OUTER_MERIDIAN','02_MIDDLE_MERIDIAN','03_INNER_MERIDIAN'][i],ROOT)
    p['radius_m']=r;p['rotation_axis']='X';p['rest_angle_deg']=angle
    p.rotation_euler.x=math.radians(angle);PIVOTS.append(p)
    ring('Gold_meridian_'+str(i+1),r,.009,.009,p)
    # Very fine inset stripe gives a drawn gold outline without reflective metal.
    for sy in [-1,1]:
        stripe=ring('Meridian_blue_inlay_'+str(i+1)+'_'+str(sy),r,.0009,.0005,p,False)
        stripe.location.y=sy*.0047
        for m in range(3):stripe.data.materials[m]=NAVY

DIAL=empty('04_DIAL_SPIN',ROOT);DIAL['rotation_axis']='Z'
DIAL['description']='Unsupported translucent projected clock turns about its vertical diameter'

def patch(name,points,material,parent):
    return mesh(name,points,[tuple(range(len(points)))],[material],parent=parent)
def face_ring(name,r,w,y,material,parent):
    o=ring(name,r,w,.0007,parent,False)
    o.location.y=y
    for i in range(3):o.data.materials[i]=material
    return o

for side in [-1]:
    # One two-sided projected surface, no backing disk, rim, or support.
    # Back view naturally mirrors the projection rather than superimposing two glyph sets.
    face=empty('Holographic_face',DIAL)
    patch('Transparent_projection_field',[(.145*sin(2*pi*i/128),0,.145*cos(2*pi*i/128))
          for i in range(128)],HOLO_FILL,face)
    face_ring('Outer_light_rule',.139,.0015,-.001,HOLO_WHITE,face)
    face_ring('Inner_light_rule',.103,.0008,-.001,HOLO_BLUE,face)
    face_ring('Inner_ice_rule',.096,.0005,-.001,HOLO_SCAN,face)
    # Fine interrupted light arcs and faint scanlines make the dial read as a projection.
    for k in range(12):
        a0=2*pi*k/12+.035;a1=2*pi*(k+1)/12-.035
        v=[];f=[]
        for j in range(13):
            a=a0+(a1-a0)*j/12
            for r in [.150,.151]:v.append((r*sin(a),-.001,r*cos(a)))
        for j in range(12):f.append((2*j,2*j+1,2*j+3,2*j+2))
        mesh('Segmented_light_halo',v,f,[HOLO_BLUE],parent=face)
    for i in range(-16,17):
        z=i*.008;half=math.sqrt(max(0,.143**2-z*z))
        patch('Projection_scanline',[(-half,-.0003,z), (half,-.0003,z),
              (half,-.0003,z+.00025),(-half,-.0003,z+.00025)],HOLO_SCAN,face)
    # Crisp readable hour and minute marks.
    for i in range(60):
        a=2*pi*i/60;r0=.131 if i%5==0 else .135
        width=.0013 if i%5==0 else .00065
        r1=.138;y=-.0016
        pts=[]
        for r,t in [(r0,-width),(r1,-width),(r1,width),(r0,width)]:
            pts.append((r*sin(a)+t*cos(a),y,r*cos(a)-t*sin(a)))
        patch('Hour_tick' if i%5==0 else 'Minute_tick',pts,HOLO_WHITE,face)
    roman=['XII','I','II','III','IV','V','VI','VII','VIII','IX','X','XI']
    for i,label in enumerate(roman):
        a=2*pi*i/12
        cu=bpy.data.curves.new('Roman_'+label,'FONT');cu.body=label
        cu.align_x='CENTER';cu.align_y='CENTER';cu.size=.018
        cu.extrude=0;cu.resolution_u=2
        ob=bpy.data.objects.new('Numeral_'+label,cu);MODEL.objects.link(ob);ob.parent=face
        ob.location=(.116*sin(a),-.0019,.116*cos(a));ob.rotation_euler=(pi/2,0,0)
        cu.materials.append(HOLO_WHITE)
    # Two counter-clockwise chasing arrows; flat geometry, not a texture.
    for k in range(2):
        start=math.radians(30)+pi*k;end=start+math.radians(130)
        v=[];f=[]
        for j in range(41):
            a=start+(end-start)*j/40
            for r in [.046,.054]:v.append((r*cos(a),-.0024,r*sin(a)))
        for j in range(40):f.append((2*j,2*j+1,2*j+3,2*j+2))
        mesh('Reverse_time_arc',v,f,[HOLO_BLUE],parent=face)
        u=Vector((cos(end),0,sin(end)));t=Vector((-sin(end),0,cos(end)))
        c=u*.050+Vector((0,-.0025,0))
        patch('Reverse_time_arrow',[tuple(c+u*.011),tuple(c-u*.011),tuple(c+t*.019)],HOLO_BLUE,face)
    # Small celestial four-point mark within the reverse-time motif.
    patch('Dial_center_star',[(0,-.0028,.018),(.004,-.0028,.004),(.014,-.0028,0),
          (.004,-.0028,-.004),(0,-.0028,-.018),(-.004,-.0028,-.004),
          (-.014,-.0028,0),(-.004,-.0028,.004)],HOLO_WHITE,face)

# Bake numeral curves so GLB keeps the projected glyph geometry.
for o in list(MODEL.objects):
    if o.type=='FONT':
        bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
        bpy.ops.object.convert(target='MESH')

# Collapse decorative meshes into one mesh for each independently moving part.
# This keeps exported draw-node count low while preserving editable materials.
controllers=PIVOTS+[DIAL,ROOT]
groups={p:[] for p in controllers}
for o in list(MODEL.objects):
    if o.type!='MESH':continue
    ancestor=o.parent
    while ancestor not in controllers:ancestor=ancestor.parent
    groups[ancestor].append(o)
for p,objects in groups.items():
    if not objects:continue
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.join()
    o=bpy.context.object;o.name=p.name+'_MESH'
    world=o.matrix_world.copy();o.parent=p;o.matrix_world=world
for o in list(MODEL.objects):
    if o.type=='EMPTY' and o not in controllers:bpy.data.objects.remove(o,do_unlink=True)

# Linear independent rotations; all parts return to the rest pose at frame 241.
SC.render.fps=30;SC.frame_start=1;SC.frame_end=241
for p,turns,axis in [(PIVOTS[0],1,0),(PIVOTS[1],-1,0),(PIVOTS[2],2,0),(DIAL,1,2)]:
    start=p.rotation_euler[axis]
    p.keyframe_insert(data_path='rotation_euler',frame=1,index=axis)
    p.rotation_euler[axis]=start+turns*2*pi
    p.keyframe_insert(data_path='rotation_euler',frame=241,index=axis)
    action=p.animation_data.action
    if hasattr(action,'fcurves'):curves=action.fcurves
    else:curves=[fc for layer in action.layers for strip in layer.strips for bag in strip.channelbags for fc in bag.fcurves]
    for fc in curves:
        for key in fc.keyframe_points:key.interpolation='LINEAR'
SC.frame_set(1)

# Cycles preview: unlit solid palette and alpha-blended emissive projection.
SC.render.engine='CYCLES';SC.cycles.samples=24
SC.cycles.transparent_max_bounces=16
SC.render.resolution_x=1000;SC.render.resolution_y=1000;SC.render.resolution_percentage=100
SC.render.film_transparent=True;SC.render.image_settings.file_format='PNG'
SC.world=bpy.data.worlds.new('PreviewWorld');SC.world.color=(.2,.2,.2)
SC.view_settings.view_transform='Standard'
cam=bpy.data.cameras.new('Preview_Camera');co=bpy.data.objects.new('Preview_Camera',cam);SC.collection.objects.link(co)
SC.camera=co;cam.type='ORTHO';cam.ortho_scale=.60
def camera(pos):
    co.location=pos;co.rotation_euler=(-co.location).to_track_quat('-Z','Y').to_euler()
camera((.4,-3,.65))
for o in MODEL.objects:o.select_set(True)
co.select_set(False);bpy.context.view_layer.objects.active=ROOT

# Validate analytic sweep separation; independently rotating meridians occupy
# disjoint radial shells. No physical support geometry exists.
ring_gap=min(.238-.009/2-math.hypot(.224+.009/2,.009/2),
             .224-.009/2-math.hypot(.210+.009/2,.009/2))
dial_gap=.210-.009/2-.1511
meshes=[o for o in MODEL.objects if o.type=='MESH']
triangles=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes)
report={'source':'Mivo Tripo task 6afc7d23f861de608444b904; manually rebuilt articulated topology',
        'meridian_count':3,'meridian_radii_m':[.238,.224,.210],
        'meridian_angles_deg':[0,65,-65],'common_axis':'X horizontal, through origin',
        'dial_diameter_m':.302,'overall_diameter_m':.485,
        'dial_material':'translucent emissive projection','support_geometry':False,
        'minimum_ring_sweep_gap_m':ring_gap,'minimum_dial_sweep_gap_m':dial_gap,
        'triangles':triangles,'mesh_objects':len(meshes),'animation_seconds':8,
        'parts':{'outer':'+1 X turn / 8s','middle':'-1 X turn / 8s','inner':'+2 X turns / 8s','dial':'+1 Z turn / 8s'}}
assert ring_gap>.004 and dial_gap>.025
assert all(tuple(p.location)==(0,0,0) for p in PIVOTS+[DIAL])
with open(OUT+'/model-report.json','w') as f:json.dump(report,f,indent=2)
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/clock_catalyst.blend')
bpy.ops.export_scene.gltf(filepath=OUT+'/clock_catalyst.glb',export_format='GLB',
    use_selection=True,export_animations=True,export_animation_mode='SCENE',
    export_force_sampling=True,export_frame_range=True,export_yup=True)

# Some Blender exporter versions emit one clip per object even in SCENE mode.
# Merge their independent samplers into one synchronized glTF animation clip.
path=OUT+'/clock_catalyst.glb'
with open(path,'rb') as f:raw=f.read()
json_len=struct.unpack_from('<I',raw,12)[0]
gltf=json.loads(raw[20:20+json_len]);tail=raw[20+json_len:]
clips=gltf.get('animations',[])
if len(clips)>1:
    loop={'name':'Clock_Loop_8s','channels':[],'samplers':[]}
    for clip in clips:
        offset=len(loop['samplers']);loop['samplers'].extend(clip['samplers'])
        for channel in clip['channels']:
            channel['sampler']+=offset;loop['channels'].append(channel)
    gltf['animations']=[loop]
elif clips:clips[0]['name']='Clock_Loop_8s'
payload=json.dumps(gltf,separators=(',',':')).encode('utf8')
payload+=b' '*((-len(payload))%4)
with open(path,'wb') as f:
    f.write(struct.pack('<III',0x46546c67,2,20+len(payload)+len(tail)))
    f.write(struct.pack('<II',len(payload),0x4e4f534a));f.write(payload);f.write(tail)
if os.environ.get('CLOCK_EXPORT_ONLY')=='1':
    print('PASS clock_catalyst build/export: '+json.dumps(report));sys.exit(0)

for name,pos in [('hero',(.4,-3,.65)),('front',(0,-3,0)),('side',(3,0,0)),
                 ('top',(0,-.00001,3)),('back',(0,3,0))]:
    camera(pos);SC.render.filepath=OUT+'/'+name+'.png';bpy.ops.render.render(write_still=True)
# Render a loop from the actual animated model, not AI video.
SC.render.resolution_x=640;SC.render.resolution_y=640;SC.cycles.samples=12
camera((.4,-3,.65));os.makedirs(OUT+'/frames',exist_ok=True)
for frame in range(1,241,3):
    SC.frame_set(frame);SC.render.filepath=OUT+'/frames/%03d.png'%frame
    bpy.ops.render.render(write_still=True)
SC.frame_set(1)
print('PASS clock_catalyst build/export/render: '+json.dumps(report))
