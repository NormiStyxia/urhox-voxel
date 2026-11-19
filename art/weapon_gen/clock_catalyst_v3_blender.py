"""Clock catalyst v3: blue-white sphere, segmented Roman-clock orbital frames.
The earlier image sheet is only a style reference. This scene rebuilds the
object as a true spherical prop with no central plate or support rods.
"""
import bpy, math, os, sys, json, struct, random
from mathutils import Vector
from math import sin, cos, pi

args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
OUT=os.path.abspath(args[0] if args else 'art/weapon_gen/out/clock_catalyst_v3')
os.makedirs(OUT+'/frames',exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
main=bpy.data.collections.new('CLOCK_CATALYST_V3');scene.collection.children.link(main)

def material(name,color,alpha=1.0,emit=0.0):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,alpha);m.use_nodes=True
    n=m.node_tree.nodes;n.clear()
    p=n.new('ShaderNodeEmission');p.inputs[0].default_value=(*color,1);p.inputs[1].default_value=max(1.0,emit)
    out=n.new('ShaderNodeOutputMaterial');m.node_tree.links.new(p.outputs[0],out.inputs[0])
    m.diffuse_color=(*color,alpha);m.use_backface_culling=False
    return m
NAVY=material('star-metal deep blue',(.025,.07,.22),1,.10)
SILVER=material('star-metal silver edge',(.48,.69,.86),1,.18)
GOLD=material('small gold accents',(.78,.46,.10),1,.12)
WHITE=material('sphere porcelain white',(.82,.93,1),1,.08)
ICE=material('sphere ice blue',(.10,.42,.88),1,.25)
STAR=material('star grains',(.32,.72,1),.60,2.0)
FEATHER=material('feather light',(.65,.90,1),.72,2.5)
INK=material('Roman numeral blue',(.04,.20,.60),1,1.2)

def obj_empty(name,parent=None):
    o=bpy.data.objects.new(name,None);main.objects.link(o);o.parent=parent;return o
ROOT=obj_empty('ClockCatalyst_ROOT');ROOT['design']='blue-white sphere with three segmented Roman clock frames'

def mesh(name,verts,faces,mats,parent):
    me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
    ob=bpy.data.objects.new(name,me);main.objects.link(ob);ob.parent=parent
    for m in mats:me.materials.append(m)
    return ob

def tube_arc(name, center, u, v, radius, start, end, width, depth, parent, mat, steps=32):
    # flat bevelled rectangular tube along a circular arc
    verts=[];faces=[]
    for i in range(steps+1):
        a=start+(end-start)*i/steps; p=center+radius*(cos(a)*u+sin(a)*v)
        tangent=(-sin(a)*u+cos(a)*v).normalized(); radial=(p-center).normalized()
        side=tangent.cross(radial).normalized()
        for q in [-width/2,width/2]:
            for d in [-depth/2,depth/2]:verts.append(tuple(p+q*side+d*radial))
    for i in range(steps):
        b=4*i; c=4*(i+1)
        for a,b2,c2,d in [(b,c,c+1,b+1),(b+2,b+3,c+3,c+2),(b,b+2,c+2,c),(b+1,c+1,c+3,b+3)]:faces.append((a,b2,c2,d))
    return mesh(name,verts,faces,[mat],parent)

def point(center,u,v,r,a):return center+r*(cos(a)*u+sin(a)*v)

# Sphere is the stable visual core. A second smaller blue sphere gives a hard-edged blue-white field.
for name,r,mat in [('Core_white_sphere',.115,WHITE),('Core_ice_sphere',.109,ICE)]:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4,radius=r,location=(0,0,0))
    o=bpy.context.object;o.name=name
    for c in list(o.users_collection):c.objects.unlink(o)
    main.objects.link(o);o.parent=ROOT;o.data.materials.append(mat)

frames=[]
# Each frame contains two opposing 100-degree arcs. All frame planes contain X,
# so the common horizontal diameter is the actual X axis. Their phase gives depth.
for idx,phase in enumerate((0,2*pi/3,4*pi/3)):
    ctrl=obj_empty('Frame_%02d_X_axis'%idx,ROOT);ctrl.rotation_euler.x=0
    ctrl['rotation_axis']='X';ctrl['phase_deg']=idx*120
    u=Vector((1,0,0));v=Vector((0,cos(phase),sin(phase)))
    w=Vector((0,-sin(phase),cos(phase)))
    # each segment is part of an individual thin frame, with a deep blue body and a silver edge
    for seg,(a,b) in enumerate(((math.radians(25),math.radians(125)),(math.radians(205),math.radians(305)))):
        tube_arc('Frame_%02d_arc_%02d'%(idx,seg),Vector((0,0,0)),u,v,.177,.177 and a,b,.008,.006,ctrl,NAVY)
        tube_arc('Frame_%02d_edge_%02d'%(idx,seg),Vector((0,0,0)),u,v,.178,a,b,.0015,.001,ctrl,SILVER)
    # Numerals are sparse and follow the arc. They are projection marks, not a plate.
    roman=['XII','I','II','III','IV','V','VI','VII','VIII','IX','X','XI']
    for j,label in enumerate(roman):
        a=2*pi*j/12
        # only expose marks near the two arc windows, leaving the central gaps obvious
        if not ((math.radians(25)<=a<=math.radians(125)) or (math.radians(205)<=a<=math.radians(305))):continue
        cu=bpy.data.curves.new('Roman_'+label,'FONT');cu.body=label;cu.align_x='CENTER';cu.align_y='CENTER';cu.size=.014;cu.extrude=.0002
        ob=bpy.data.objects.new('Frame_%02d_%s'%(idx,label),cu);main.objects.link(ob);ob.parent=ctrl;cu.materials.append(INK)
        p=point(Vector((0,0,0)),u,v,.188,a);ob.location=p
        # face outward from the frame, keeping each numeral readable from the main view
        ob.rotation_mode='QUATERNION';ob.rotation_quaternion=Vector((0,-1,0)).rotation_difference(v*cos(a)+u*sin(a))
    frames.append(ctrl)

# Sparse rear star-sand grains and two small feather light sheets. They are independent FX.
rng=random.Random(19);fx=obj_empty('Rear_galaxy_sand',ROOT)
for i in range(54):
    a=rng.uniform(0,2*pi);rad=rng.uniform(.15,.235);x=rng.uniform(-.06,.06)
    p=Vector((x,rad*cos(a),rad*sin(a)))
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=rng.uniform(.0007,.0022),location=p)
    o=bpy.context.object
    for c in list(o.users_collection):c.objects.unlink(o)
    main.objects.link(o);o.parent=fx;o.data.materials.append(STAR)
for i,a in enumerate((math.radians(52),math.radians(235))):
    u=Vector((1,0,0));v=Vector((0,cos(a),sin(a)));w=Vector((0,-sin(a),cos(a)))
    c=Vector((.025,0,0))+v*.19
    verts=[tuple(c-w*.005),tuple(c+v*.022-w*.002),tuple(c+v*.045),tuple(c+v*.023+w*.003),tuple(c+w*.005)]
    mesh('Small_feather_light_%02d'%i,verts,[(0,1,2,3,4)],[FEATHER],fx)

# Animation is coordinated and low frequency. The frames remain sparse while the ball stays stable.
scene.frame_start=1;scene.frame_end=361;scene.render.fps=30
for i,ctrl in enumerate(frames):
    ctrl.rotation_euler.x=math.radians(i*120)
    ctrl.keyframe_insert(data_path='rotation_euler',frame=1,index=0)
    ctrl.rotation_euler.x+=2*pi
    ctrl.keyframe_insert(data_path='rotation_euler',frame=361,index=0)
    action=ctrl.animation_data.action
    curves=action.fcurves if hasattr(action,'fcurves') else [fc for layer in action.layers for strip in layer.strips for bag in strip.channelbags for fc in bag.fcurves]
    for fc in curves:
        for k in fc.keyframe_points:k.interpolation='LINEAR'

# Lighting and camera
scene.render.engine='BLENDER_WORKBENCH';scene.display.shading.light='FLAT';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_cavity=True;scene.display.shading.cavity_type='WORLD';scene.display.shading.curvature_ridge_factor=1.4
scene.display.shading.show_shadows=False;scene.render.film_transparent=True;scene.render.resolution_x=900;scene.render.resolution_y=900
cam=bpy.data.cameras.new('Camera');camera=bpy.data.objects.new('Camera',cam);main.objects.link(camera);scene.camera=camera;cam.type='ORTHO';cam.ortho_scale=.52
camera.location=(.58,-.95,.48);camera.rotation_euler=(-camera.location).to_track_quat('-Z','Y').to_euler()

meshes=[o for o in main.objects if o.type=='MESH'];tri=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes)
report={'version':'v3','core':'blue-white solid sphere','frame_count':3,'frame_segments_per_frame':2,'frame_axis':'X horizontal','frame_phases_deg':[0,120,240],'numerals':'attached to segmented arc projection','support_geometry':False,'hands':False,'rear_sand_grains':54,'feather_light_sheets':2,'triangles':tri,'animation_period_s':12}
with open(OUT+'/model-report.json','w') as f:json.dump(report,f,indent=2)
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/clock_catalyst.blend')

# Export only selected hierarchy so camera is omitted from GLB.
bpy.ops.object.select_all(action='DESELECT')
for o in main.objects:
    if o!=camera:o.select_set(True)
bpy.context.view_layer.objects.active=ROOT
bpy.ops.export_scene.gltf(filepath=OUT+'/clock_catalyst.glb',export_format='GLB',use_selection=True,export_animations=True,export_yup=True,export_force_sampling=True)

for name,pos in [('hero',(.58,-.95,.48)),('front',(0,-1.2,0)),('side',(1.2,0,0)),('top',(0,0,1.2))]:
    camera.location=pos;camera.rotation_euler=(-camera.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=OUT+'/'+name+'.png';scene.render.resolution_x=900;scene.render.resolution_y=900;bpy.ops.render.render(write_still=True)
scene.render.resolution_x=640;scene.render.resolution_y=640;camera.location=(.58,-.95,.48);camera.rotation_euler=(-camera.location).to_track_quat('-Z','Y').to_euler()
for frame in range(1,361,6):
    scene.frame_set(frame);scene.render.filepath=OUT+'/frames/%03d.png'%frame;bpy.ops.render.render(write_still=True)
print('PASS clock catalyst v3',json.dumps(report))
