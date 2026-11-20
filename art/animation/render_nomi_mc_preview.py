import bpy, json, math, os
from mathutils import Vector
ROOT='/Users/xd/Desktop/体素test'
OUT=os.path.join(ROOT,'art/animation/out'); os.makedirs(OUT,exist_ok=True)
G=json.load(open(os.path.join(ROOT,'art/nomi_ysm/nomi.geo.json')))['minecraft:geometry'][0]
# clear
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
# materials

def mat(name,color):
 m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); return m
skin=mat('Nomi navy',(0.08,0.16,0.28)); cloth=mat('Nomi coat',(0.18,0.32,0.52)); hair=mat('Nomi hair',(0.04,0.06,0.12)); boot=mat('Boots',(0.035,0.045,0.06)); ground=mat('Ground',(0.035,0.045,0.06))
materials={'head':skin,'hair':hair,'hair_shell':hair,'hair_back':hair,'braid':hair,'body':cloth,'cloak':cloth,'skirt':cloth,'leg_right':boot,'leg_left':boot,'arm_right':cloth,'arm_left':cloth}
bones={}
for b in G['bones']:
 o=bpy.data.objects.new(b['name'],None); bpy.context.collection.objects.link(o); o.empty_display_type='PLAIN_AXES'; o.empty_display_size=.05
 p=b.get('parent'); o.parent=bones.get(p); pv=b['pivot']; pp=next((x['pivot'] for x in G['bones'] if x['name']==p),[0,0,0]); o.location=((pv[0]-pp[0])/16,(pv[1]-pp[1])/16,-(pv[2]-pp[2])/16); bones[b['name']]=o
# cubes local to bone pivot
for b in G['bones']:
 par=bones[b['name']]
 for c in b.get('cubes',[]):
  org=c['origin']; sz=c['size']; inf=c.get('inflate',0)
  bpy.ops.mesh.primitive_cube_add(size=1)
  o=bpy.context.object; o.name=b['name']+'_cube'; o.parent=par
  o.location=((org[0]+sz[0]/2-b['pivot'][0])/16,(org[1]+sz[1]/2-b['pivot'][1])/16,-(org[2]+sz[2]/2-b['pivot'][2])/16)
  o.dimensions=((sz[0]+2*inf)/16,(sz[1]+2*inf)/16,(sz[2]+2*inf)/16); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
  o.data.materials.append(materials.get(b['name'],cloth))
# animation: MC-inspired contra-body walk, hip drop, easing
fps=24; frames=48; root=bones['root']; body=bones['body']; rr=bones['leg_right']; rl=bones['leg_left']; ar=bones['arm_right']; al=bones['arm_left']; head=bones['head']; cloak=bones.get('cloak')
def key(o,frame,loc=None,rot=None):
 if loc is not None: o.location=loc; o.keyframe_insert('location',frame=frame)
 if rot is not None: o.rotation_mode='XYZ'; o.rotation_euler=rot; o.keyframe_insert('rotation_euler',frame=frame)
for f in range(1,frames+1):
 t=(f-1)/(frames-1); ph=t*math.tau; s=math.sin(ph); c=math.cos(ph)
 # angular walk, torso counter-rotates hips, root drops at stride extremes
 key(root,f,loc=(0,0.018*(1-abs(s)),0),rot=(0,0.025*c,0))
 key(body,f,rot=(math.radians(5+2*abs(s)),math.radians(-5*c),math.radians(2*s)))
 key(rr,f,rot=(math.radians(28*s),0,0)); key(rl,f,rot=(math.radians(-28*s),0,0))
 key(ar,f,rot=(math.radians(-22*s),0,math.radians(5))); key(al,f,rot=(math.radians(22*s),0,math.radians(-5)))
 key(head,f,rot=(math.radians(-2+1.5*c),math.radians(3*c),0))
 if cloak: key(cloak,f,rot=(math.radians(7+5*max(0,-s)),0,math.radians(2*s)))
# ground
bpy.ops.mesh.primitive_plane_add(size=20,location=(0,0,0)); pl=bpy.context.object; pl.data.materials.append(ground)
# camera/light
bpy.ops.object.camera_add(location=(0,1.35,5.5)); cam=bpy.context.object; bpy.context.scene.camera=cam
def track(obj,pt): obj.rotation_euler=(Vector(pt)-obj.location).to_track_quat('-Z','Y').to_euler()
track(cam,(0,1.0,0)); cam.data.lens=58
bpy.ops.object.light_add(type='AREA', location=(2,4,3)); bpy.context.object.data.energy=700; bpy.context.object.data.shape='DISK'; bpy.context.object.data.size=4
bpy.ops.object.light_add(type='AREA', location=(-3,2,1)); bpy.context.object.data.energy=350; bpy.context.object.data.size=3
scene=bpy.context.scene; scene.render.engine='BLENDER_EEVEE'; scene.render.resolution_x=320; scene.render.resolution_y=400; scene.render.resolution_percentage=100; scene.render.fps=fps
scene.render.image_settings.file_format='PNG'; scene.render.film_transparent=False; scene.world.color=(0.012,0.018,0.03)
scene.render.filepath=os.path.join(OUT,'frame_'); scene.frame_start=1; scene.frame_end=frames
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'nomi_mc_walk.blend'))
for f in range(1,frames+1): scene.frame_set(f); scene.render.filepath=os.path.join(OUT,f'frame_{f:03d}.png'); bpy.ops.render.render(write_still=True)
