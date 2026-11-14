"""CPU geometry inspection only. Not a Web screenshot or engine shader render."""
from pathlib import Path
from lupa.lua54 import LuaRuntime
from PIL import Image, ImageDraw
import json
from volume_preview_renderer import np, norm, sky, mesh, render
lua=LuaRuntime(unpack_returned_tuples=True)
header=Path('validation/sky-fx/check.lua').read_text().split("local settings=require",1)[0]
cloud=lua.execute(header+"local c=require('ruins.SkyClouds').New(node('Preview'),24,true,true);for i=1,5000 do if not c.baking then break end;c:StepBake()end;assert(c.ready and not c.fallback);return c")
shapes=cloud['shapes'];root=Path('validation/sky-fx')
canvas=sky(1440,1920)
views=[(0,.08,1),(.55,-.65,1),(.55,1.25,1)]
for index in range(1,7):
    s=shapes[index];p,_,_,_=mesh(s);radius=np.linalg.norm(p,axis=1).max();scale=min(105,165/radius)
    for col,view in enumerate(views):
        v=norm(view);up=np.cross(v,norm((v[2],0,-v[0])))
        yproj=p@up;middle=(yproj.max()+yproj.min())*.5
        render(canvas,s,view,(col*480+240,(index-1)*310+182+middle*scale),scale)
im=Image.fromarray(np.uint8(np.clip(canvas,0,1)*255));draw=ImageDraw.Draw(im)
draw.text((16,12),'CPU baked meshes / interpolated field-gradient normals / NOT engine or Web evidence',fill='white')
for col,label in enumerate(['SIDE','BELOW','ABOVE']):draw.text((col*480+210,32),label,fill='white')
report=[]
for index in range(1,7):
    s=shapes[index];vs,tris=len(s['vertices']),len(s['indices'])//3
    draw.text((18,(index-1)*310+60),f"{index}. {s['name']}  {vs} vertices / {tris} triangles",fill='white')
    report.append(dict(shape=s['name'],vertices=vs,triangles=tris))
im.save(root/'volume-shapes.png')

canvas=sky(1600,900)
for index,cx,cy,size,fog in [(8,150,620,65,.68),(11,520,635,80,.72),(8,930,610,80,.62),(11,1400,620,95,.65)]:
    render(canvas,shapes[index],(0,.05,1),(cx,cy),size,fog,yaw=.12)
for index,cx,cy,size,fog,yaw in [(4,1280,455,96,.23,-.2),(3,760,440,105,.16,.15),(1,350,450,104,.12,-.3),(6,1060,225,70,.28,.1)]:
    render(canvas,shapes[index],(.12,.03,1),(cx,cy),size,fog,yaw=yaw)
for index,cx in [(14,180),(17,700),(14,1280)]:render(canvas,shapes[index],(.1,.5,1),(cx,870),115,.62,stretch=(1,.65,1))
im=Image.fromarray(np.uint8(np.clip(canvas,0,1)*255));draw=ImageDraw.Draw(im)
draw.text((20,20),'CPU SCENE STUDY - actual baked meshes + smooth normals + approximate distance fog',fill='white')
draw.text((20,40),'NOT a Web screenshot; no engine exposure, real depth intersections or transparent batch sorting',fill='white')
im.save(root/'volume-scene-preview.png')
(root/'volume-shape-counts.json').write_text(json.dumps(dict(shapes=report,total_triangles=cloud['triangleCount'],slices=cloud['bakeSlices']),indent=2))
print(json.dumps(dict(shapes=report,total_triangles=cloud['triangleCount'],slices=cloud['bakeSlices'])))
