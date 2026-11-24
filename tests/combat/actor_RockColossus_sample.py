"""Run from the worktree with Python 3, lupa.lua54, numpy, Pillow and Chrome/Chromium (CHROME_BIN may override its path)."""
from pathlib import Path
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from lupa.lua54 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
model, fault, create, pose = lua.execute('''
package.path='scripts/?.lua;tests/?.lua;'..package.path
local T=require('combat.enemy_support')
local A=require('combat.enemies.actors.RockColossus')
local F=require('combat.enemies.actors.RockColossusFault')
return require('combat.enemies.models.RockColossus').Build(),F,
function(stage,age)
    local terrain,combat=T.Fixture()
    local e=A.New(nil,nil,terrain,combat,Vector3.ZERO)
    if stage~='idle' then
        local target=Vector3(0,0,5)
        e.attackIndex=stage=='sweep' and 0 or 1;e:Face(target);e:StartAttack()
        if stage=='warning' then T.Tick(e,age,target)
        else T.Tick(e,e.attack.telegraph+age,target) end
    end
    return e
end,
function(e,id)
    local p={x=0,y=0,z=0,pitch=0,yaw=0,roll=0,sx=1,sy=1,sz=1}
    e.config.posePart(e,id,p);return p
end''')


def xyz(t):
    return [t[1], t[2], t[3]]


def rotation(pitch, yaw, roll):
    a,b,c=np.deg2rad([pitch,yaw,roll]); ca,cb,cc=np.cos([a,b,c]); sa,sb,sc=np.sin([a,b,c])
    return (np.array([[cb,0,sb],[0,1,0],[-sb,0,cb]]) @ np.array([[1,0,0],[0,ca,-sa],[0,sa,ca]])
            @ np.array([[cc,-sc,0],[sc,cc,0],[0,0,1]]))


faces=[(0,-1),(0,1),(1,-1),(1,1),(2,-1),(2,1)]
parts={}
palette=np.array([xyz(p.rgb) for p in model.palette.values()])
for part in model.parts.values():
    cells={tuple(xyz(c)):c[4]-1 for c in part.cells.values()}; polys=[]; normals=[]; colors=[]
    for pos,index in cells.items():
        for axis,sign in faces:
            off=list(pos);off[axis]+=sign
            if tuple(off) in cells: continue
            pts=[]
            for u,v in [(0,0),(1,0),(1,1),(0,1)]:
                pt=list(pos);pt[axis]+=int(sign>0);pt[(axis+1)%3]+=u;pt[(axis+2)%3]+=v;pts.append(pt)
            n=[0,0,0];n[axis]=sign;polys.append(pts);normals.append(n);colors.append(palette[index])
    parts[part.id]=(np.array(xyz(part.pivot)),np.array(polys)*model.size,np.array(normals),np.array(colors))


def font(size):
    for path in ['/System/Library/Fonts/Supplemental/Arial.ttf','/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf']:
        if Path(path).exists(): return ImageFont.truetype(path,size)
    return ImageFont.load_default()


import base64
import io
import json
import os
import re
import shutil
import subprocess
import tempfile

# The art in these frames is evaluated by the shipping fragment bodies in WebGL2.
# The harness supplies a small orthographic scene and a single directional light.
W,H=740,500
stages=[('warning',.12,'Fracture starts'),('warning',.55,'Brush crosses the fault'),('warning',1.05,'Locked warning'),
        ('fault',.34,'First beds erupt'),('fault',.77,'Strata and ejecta'),('fault',1.39,'Embers clear')]
viewYaw,tilt=np.deg2rad([54,25]);camera=np.array([np.sin(viewYaw)*np.cos(tilt),np.sin(tilt),np.cos(viewYaw)*np.cos(tilt)])
right=np.array([-np.cos(viewYaw),0,np.sin(viewYaw)]);up=np.cross(right,camera)

def pack(pts,normals,uv,col):
    pts=np.asarray(pts).reshape(-1,3);count=len(pts)
    clip=np.stack([2*(pts@right*72+225)/W-1,1-2*(355-pts@up*72)/H,-pts@camera*.06],axis=-1)
    return np.column_stack((clip,np.broadcast_to(normals,(count,3)),np.broadcast_to(uv,(count,2)),np.broadcast_to(col,(count,3))))

def batch(program,vertices,uniforms=None):
    data=np.vstack(vertices).astype('<f4');return dict(program=program,count=len(data),vertices=base64.b64encode(data.tobytes()).decode(),uniforms=uniforms or {})

order=[0,1,2,0,2,3];frames=[]
for stage,time,label in stages:
    e=create(stage,time);solid=[];wall=[];transparent=[]
    # The neutral slate receiver provides scene depth for warnings and particles.
    solid.append(pack(np.array([[-10,-.025,-10],[-10,-.025,12],[10,-.025,12],[10,-.025,-10]])[order],[0,1,0],[0,0],[.27,.29,.30]))
    for name,(pivot,verts,normals,col) in parts.items():
        p=pose(e,name);rot=rotation(p.pitch,p.yaw,p.roll);n=normals@rot.T;keep=n@camera>0
        v=(verts[keep]-pivot)@rot.T+pivot+[p.x,p.y+e.poseY,p.z]
        solid.append(pack(v[:,order],np.repeat(n[keep],6,axis=0),[0,0],np.repeat(col[keep]/255,6,axis=0)))
    for i,s in e.fault.sections.items():
        if not s.valid:continue
        rock=[];ground=[]
        for tri in fault.Mesh(i).values():
            slot=tri[1];marker=slot==5
            if (marker and s.ash>=1) or (not marker and s.height<=0):continue
            local=np.array([xyz(tri[k]) for k in (2,3,4)],dtype=float);normal=np.cross(local[1]-local[0],local[2]-local[0]);normal/=np.linalg.norm(normal)
            uvs=np.array([fault.UV(slot,tri[k],*normal) for k in (2,3,4)])
            verts=local*[1,s.height if not marker else 1,1]+[s.x,s.y+(.045 if marker else 0),s.z]
            n=np.cross(verts[1]-verts[0],verts[2]-verts[0]);n/=np.linalg.norm(n)
            (ground if marker else rock).append(pack(verts,n,uvs,[1,1,1]))
        if rock:wall.append(batch(2,rock,{'bed':i-1,'heat':s.heat}))
        if ground:transparent.append(batch(1,ground,{'bed':i-1,'plume':0,'brush':s.brush,'ash':s.ash}))
        if s.spraySize>0:
            uv=np.array([[0,0],[1,0],[1,1],[0,1]])[order];side=1 if i%2 else -1;rot=rotation(0,side*32,0)
            verts=np.column_stack(((uv[:,0]-.5)*2,1-uv[:,1],np.zeros(6)))*s.spraySize@rot.T+[s.x+s.sprayX,s.y+s.sprayY,s.z+.35]
            transparent.append(batch(1,[pack(verts,camera,uv,[1,1,1])],{'bed':i-1,'plume':1,'brush':0,'ash':s.sprayFade}))
    for v in e.particles.slots.values():
        if v.active:
            pos=np.array([v.x,v.y,v.z]);verts=np.array([pos+right*a*v.sx+up*b*v.sy for a,b in [(-1,-1),(-1,1),(1,1),(1,-1)]])[order]
            solid.append(pack(verts,camera,[0,0],[.60,.55,.47]))
    frames.append([batch(0,solid)]+wall+transparent);e.Destroy(e)

assets=Path('assets'); atlas=Image.open(assets/fault.Atlas);assert atlas.mode=='RGBA' and atlas.size==(192,160)
sources=['void fragment(){ALBEDO=colorIn*colorIn;}']
sources.extend((assets/'Shaders/BLGL'/f'{name}.shader').read_text() for name in ['RockFaultInk','RockFaultStrata'])
inputs=dict(sources=sources,atlas=base64.b64encode(atlas.tobytes()).decode(),frames=frames)
js=Path('tests/combat/rock_fault_capture.js').read_text()
chrome=os.environ.get('CHROME_BIN') or shutil.which('chromium') or shutil.which('google-chrome') or '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
Path('.tmp').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(dir='.tmp') as tmp:
    root=Path(tmp).resolve();page=root/'capture.html'
    (root/'inputs.js').write_text('const inputs='+json.dumps(inputs));(root/'draw.js').write_text(js)
    page.write_text(f'<canvas width="{W}" height="{H}"></canvas><pre></pre><script>window.onerror=(e)=>document.querySelector("pre").textContent=e</script><script src="inputs.js"></script><script src="draw.js"></script>')
    result=subprocess.run([chrome,'--headless=new','--disable-background-networking','--no-first-run','--disable-extensions','--enable-unsafe-swiftshader','--use-angle=swiftshader','--user-data-dir='+str(root/'profile'),'--dump-dom',page.as_uri()],capture_output=True,text=True,check=True,timeout=65)
    output=re.search(r'<pre>(.*?)</pre>',result.stdout,re.S).group(1)
    if not output.startswith('['):raise RuntimeError(output+' '+result.stderr[-300:])
    images=json.loads(output)
canvas=Image.new('RGB',(W*2,(H+40)*3),(38,41,43));draw=ImageDraw.Draw(canvas)
for i,(raw,(stage,time,label)) in enumerate(zip(images,stages)):
    x,y=i%2*W,i//2*(H+40);canvas.paste(Image.open(io.BytesIO(base64.b64decode(raw))),(x,y))
    draw.text((x+14,y+H+8),f'{label}     {stage}  {time:.2f} s',font=font(18),fill=(238,232,215))
out=Path('validation/enemy-roles/RockColossus-fault-ink.png');out.parent.mkdir(parents=True,exist_ok=True);canvas.save(out);print(out)
