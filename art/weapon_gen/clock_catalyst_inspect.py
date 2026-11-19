"""Inspect the Mivo source and render it before articulated mesh cleanup."""
import bpy, json, os
from mathutils import Vector
OUT = os.path.abspath('art/weapon_gen/out/clock_catalyst')
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=OUT+'/source/mivo_clock_source.glb')
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
report = []
for o in meshes:
    report.append(dict(name=o.name, vertices=len(o.data.vertices), faces=len(o.data.polygons),
                       bounds=[list(o.matrix_world@Vector(p)) for p in o.bound_box],
                       materials=[m.name for m in o.data.materials]))
with open(OUT+'/source/inspection.json','w') as f: json.dump(report,f,indent=2)
points = [o.matrix_world@Vector(p) for o in meshes for p in o.bound_box]
lo = Vector([min(p[i] for p in points) for i in range(3)])
hi = Vector([max(p[i] for p in points) for i in range(3)])
center = (lo+hi)/2
span = max(hi-lo)
scene=bpy.context.scene
scene.render.engine='CYCLES'; scene.cycles.samples=16
scene.render.resolution_x=800;scene.render.resolution_y=800;scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('World'); scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.5,.5,.5,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.8
scene.view_settings.view_transform='Standard'
cam=bpy.data.cameras.new('SourceCamera');co=bpy.data.objects.new('SourceCamera',cam);scene.collection.objects.link(co)
co.location=center+Vector((.5,-3,.35))*span
co.rotation_euler=(center-co.location).to_track_quat('-Z','Y').to_euler()
cam.type='ORTHO';cam.ortho_scale=span*1.3;scene.camera=co
scene.render.filepath=OUT+'/source/source_preview.png'
bpy.ops.render.render(write_still=True)
print('SOURCE_REPORT',json.dumps(report))
