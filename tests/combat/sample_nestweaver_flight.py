"""From the repository root: python3 tests/combat/sample_nestweaver_flight.py.
Pose and silk transforms come from the real Lua 5.4 actor. Offline orthographic
body rasterization uses NumPy/Pillow. Silk uses the real BLGL fragment and PNG
through Chrome WebGL2/SwiftShader. Set CHROME_BIN to a local Chrome binary.
"""
import base64
import json
import math
import os
import re
import shutil
import subprocess
import tempfile
import runpy
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from lupa.lua54 import LuaRuntime

root = Path(__file__).resolve().parents[2]
render = runpy.run_path(str(root / 'art/enemy-turnarounds/render_enemy_models.py'))
model = render['load_model']('NestWeaver')
print('model (cells / unique / parts)', render['validate']('NestWeaver', model))
lua = LuaRuntime(unpack_returned_tuples=True)
frames = render['lua_to_python'](lua.execute('''
package.path='scripts/?.lua;tests/?.lua;'..package.path
local T=require('combat.enemy_support'); local C=require('combat.enemies.actors.NestWeaver')
local model=require('combat.enemies.models.NestWeaver').Build()
local terrain,combat=T.Fixture(); local e=C.New(nil,nil,terrain,combat,Vector3.ZERO,'sample')
local views={}; local far=Vector3(0,0,5); local near=Vector3(0,0,1.2)
local function snap()
    local poses={}; for _,part in ipairs(model.parts) do
        local p={x=0,y=0,z=0,pitch=0,yaw=0,roll=0,sx=1,sy=1,sz=1}
        C.Config.posePart(e,part.id,p); poses[part.id]=p
    end
    local t=e.thread; local thread=nil
    if t.node.enabled or t.endNode.enabled then
        local fxNode=t.endNode.enabled and t.endNode or t.node
        local scale=fxNode.scale; local pos=fxNode.position
        thread={dir={t.fx,t.fy,t.fz},center={pos.x,pos.y,pos.z},length=scale.z,width=scale.x,groups={}}
        for name,g in pairs(t.fxMesh.groups) do
            if g.enabled then thread.groups[name]={g.radial,g.depth,g.z,g.roll,g.age} end
        end
    end
    views[#views+1]={poses=poses,root={e.position.x,e.position.y,e.position.z},yaw=e.yaw,thread=thread}
end
e.thread.node={};e.thread.endNode={};e:Face(far); e.lastTarget=far;e:StartAttack()
for _,dt in ipairs({.14,.42,.28,.29,.20,.16}) do T.Tick(e,dt,far);snap() end
return views
'''))


def rotation(axis, angle):
    a = math.radians(angle)
    axes = [i for i in range(3) if i != axis]
    if axis == 1:
        axes.reverse()
    matrix = np.eye(3)
    matrix[np.ix_(axes, axes)] = [[math.cos(a), -math.sin(a)], [math.sin(a), math.cos(a)]]
    return matrix


normal_dirs = np.concatenate((np.eye(3), -np.eye(3)))
meshes = []
for part in model['parts']:
    cells = {tuple(c[:3]): c[3] for c in part['cells']}
    faces, normals, slots = [], [], []
    for xyz, slot in cells.items():
        for normal in normal_dirs:
            if tuple(xyz + normal) not in cells:
                faces.append(render['face_geometry'](xyz, normal, model['size']))
                normals.append(normal)
                slots.append(slot)
    meshes.append((part['id'], np.array(part['pivot']), np.array(faces), np.array(normals), slots))

font_path='/System/Library/Fonts/Supplemental/Arial.ttf'
def font(size):
    try: return ImageFont.truetype(font_path,size)
    except OSError: return ImageFont.load_default()

# Read the same quad batches that are committed to UrhoX CustomGeometry.
fx_batches=render['lua_to_python'](lua.eval("require('combat.enemies.actors.NestWeaverSilk').batches"))
def silk_faces(thread):
    direction=np.array(thread['dir']); center=np.array(thread['center'])
    lateral=np.cross([0,1,0],direction)
    lateral/=np.linalg.norm(lateral); up=np.cross(direction,lateral)
    axes=np.array([lateral,up,direction])
    result=[]
    for batch in fx_batches:
        group=thread['groups'].get(batch['group'])
        if not group: continue
        radial,depth,z,roll,age=group
        vertices=np.array(batch['quads'])*[radial,radial,depth]
        vertices=vertices@rotation(2,roll).T+[0,0,z]
        vertices*= [thread['width'],thread['width'],thread['length']]
        world=vertices@axes+center
        result.append((world,batch,age))
    return result

W,H=540,380
sheet=Image.new('RGB',(W*2,H*3)); gpu_frames=[]
names=['01  Mouth / first bristles','02  Gathering / layered brush','03  Locked / amber guides','04  Release / counter-twisted fibres','05  Contact / cut ends','06  Fall / pixel erosion']
for n,frame in enumerate(frames):
    panel=Image.new('RGB',(W,H),(27,33,41)); draw=ImageDraw.Draw(panel,'RGBA')
    camera=np.array([.77,.40,.56]); camera/=np.linalg.norm(camera)
    right=np.cross(camera,[0,1,0]); right/=np.linalg.norm(right); up=np.cross(right,camera)
    basis=np.stack([right,-up]);thread=frame['thread'];focus=np.array(thread['center']);offset=np.array([250,205]);scale=300
    if n<2: focus-=np.array(thread['dir'])*thread['length']*.5;scale=195
    if n==2: focus=np.array([0,0,0]);scale=50;offset=np.array([178,286])
    if n==3: scale=270
    if n==5: focus=np.array(frames[4]['thread']['center'])
    def project(v):return (v-focus)@basis.T*scale+offset
    for t in range(-4,9):
        for a,b in [((t,0,-3),(t,0,8)),((-4,0,t),(4,0,t))]:
            draw.line([tuple(project(np.array(a))),tuple(project(np.array(b)))],fill=(44,51,58))
    origin=np.array(frame['root']); yaw=rotation(1,frame['yaw']);ordered=[]
    for identifier,pivot,faces,normals,slots in meshes:
        p=frame['poses'][identifier];rot=rotation(1,p['yaw'])@rotation(0,p['pitch'])@rotation(2,p['roll'])
        world=((faces-pivot)*[p['sx'],p['sy'],p['sz']])@rot.T+pivot+[p['x'],p['y'],p['z']]
        world=world@yaw.T+origin; normals=normals@rot.T@yaw.T
        for i in np.flatnonzero(normals@camera>.001):
            m=model['palette'][slots[i]-1]
            color=render['shade'](m['rgb'],m['roughness'],m['metallic'],m['emission'],normals[i],[-.48,1,.66],[.42,.43,.44],-camera)
            ordered.append((world[i].mean(axis=0)@camera,project(world[i]),color))
    for _,pts,color in sorted(ordered,key=lambda a:a[0]): draw.polygon([tuple(v) for v in pts],fill=color)
    sheet.paste(panel,(W*(n%2),H*(n//2)))
    material=[]; geom=[]
    for quads,batch,age in silk_faces(thread):
        mat=len(material);material.append([batch['color'],batch['cut'],batch['rate'],batch['backing'],age])
        for pts in quads:
            xy=project(pts)
            if max(xy[:,0])<0 or min(xy[:,0])>W or max(xy[:,1])<0 or min(xy[:,1])>H:continue
            geom.append([float(pts.mean(axis=0)@camera),mat,xy.round(3).tolist()])
    gpu_frames.append([material,sorted(geom)])

# Compile the actual BLGL fragment as GLSL ES 3.0, supplying only the UrhoX
# built-ins. The shader itself samples the shipped PNG and runs the brush clock.
shader=(root/'assets/Shaders/BLGL/NestWeaverSilk.shader').read_text()
frag=shader[shader.index('uniform sampler2D'):].replace(' : filter_nearest, repeat_disable','')
frag=re.sub(r'(uniform (?:vec4|float) \w+) = [^;]+;',r'\1;',frag)
frag=frag.replace('void fragment()', 'void main()').replace('ALBEDO=color; ALPHA=alpha;','pixel=vec4(color,alpha);')
frag='#version 300 es\nprecision highp float; in vec2 UV; out vec4 pixel;\n'+frag
atlas=Image.open(root/'assets/Textures/fx/NestWeaverSilk.png').convert('RGBA')
html=r"""<canvas id=c width=540 height=380></canvas><pre id=result></pre><script>
try {
const gl=c.getContext('webgl2',{antialias:false,preserveDrawingBuffer:true,premultipliedAlpha:true});
function compile(t,s){const a=gl.createShader(t);gl.shaderSource(a,s);gl.compileShader(a);if(!gl.getShaderParameter(a,gl.COMPILE_STATUS))throw Error(gl.getShaderInfoLog(a));return a;}
const prog=gl.createProgram();gl.attachShader(prog,compile(gl.VERTEX_SHADER,'#version 300 es\nlayout(location=0) in vec4 v;out vec2 UV;void main(){gl_Position=vec4(v.xy,0,1); UV=v.zw;}'));
gl.attachShader(prog,compile(gl.FRAGMENT_SHADER,FRAG));gl.linkProgram(prog);if(!gl.getProgramParameter(prog,gl.LINK_STATUS))throw Error(gl.getProgramInfoLog(prog));gl.useProgram(prog);
gl.bindTexture(gl.TEXTURE_2D,gl.createTexture());gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,64,128,0,gl.RGBA,gl.UNSIGNED_BYTE,Uint8Array.from(atob(ATLAS),x=>x.charCodeAt(0)));
gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.NEAREST);
gl.bindBuffer(gl.ARRAY_BUFFER,gl.createBuffer());gl.enableVertexAttribArray(0);gl.vertexAttribPointer(0,4,gl.FLOAT,false,0,0);
gl.enable(gl.BLEND);gl.blendFuncSeparate(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA,gl.ONE,gl.ONE_MINUS_SRC_ALPHA);const uni=k=>gl.getUniformLocation(prog,k),images=[];
for(const [mats,geom] of FRAMES){gl.clearColor(0,0,0,0);gl.clear(gl.COLOR_BUFFER_BIT);
 for(const [d,i,quad] of geom){const [color,cut,rate,back,age]=mats[i];gl.uniform4fv(uni('silk_tint'),color);for(const [key,val] of Object.entries({cut,rate,backing:back,brush_age:age}))gl.uniform1f(uni(key),val);
 const data=[];for(const k of [0,1,2,0,2,3])data.push(2*quad[k][0]/540-1,1-2*quad[k][1]/380,k>=2?1:0,k===1||k===2?1:0);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(data),gl.STREAM_DRAW);gl.drawArrays(gl.TRIANGLES,0,6);}
 images.push(c.toDataURL().split(',')[1]);}result.textContent=JSON.stringify(images);
}catch(e){result.textContent='ERROR '+e.message;}</script>"""
html=html.replace('compile(gl.FRAGMENT_SHADER,FRAG)','compile(gl.FRAGMENT_SHADER,'+json.dumps(frag)+')').replace('atob(ATLAS)','atob('+json.dumps(base64.b64encode(atlas.tobytes()).decode())+')').replace('of FRAMES','of '+json.dumps(gpu_frames,separators=(',',':')))
chrome=os.getenv('CHROME_BIN') or shutil.which('chromium') or '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
with tempfile.TemporaryDirectory() as tmp:
    page=Path(tmp)/'silk.html';page.write_text(html)
    run=subprocess.run([chrome,'--headless','--disable-extensions','--no-first-run','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--user-data-dir='+tmp+'/profile','--dump-dom',page.as_uri()],capture_output=True,text=True,timeout=75,check=True)
    payload=re.search(r'<pre id="result">([^<]*)</pre>',run.stdout).group(1)
    if not payload.startswith('['):raise RuntimeError(payload or 'WebGL2 sampler produced no frames')
    import io
    for n,encoded in enumerate(json.loads(payload)):
        ink=Image.open(io.BytesIO(base64.b64decode(encoded))).convert('RGBA');assert ink.getchannel('A').getbbox()
        xy=(W*(n%2),H*(n//2));sheet.paste(ink,xy,ink)
        d=ImageDraw.Draw(sheet,'RGBA');x,y=xy;d.rectangle((x,y,x+W,y+36),fill=(24,31,39,235));d.text((x+12,y+5),names[n],font=font(19),fill=(242,230,210))
out=root/'validation/enemy-roles/NestWeaver-flight.png';out.parent.mkdir(parents=True,exist_ok=True);sheet.save(out);print(out)
