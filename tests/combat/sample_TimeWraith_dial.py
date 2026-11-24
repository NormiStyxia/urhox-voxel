"""Render the shipped clock ink and actual FX triangles at six Lua actor timestamps.
Run python3 tests/combat/sample_TimeWraith_dial.py from the worktree root.
Requires Chrome (set CHROME_BIN if needed), Lupa 5.4, Pillow and numpy.
"""
import base64
import io
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

import numpy as np
from lupa.lua54 import LuaRuntime
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
os.chdir(ROOT)
OUT = ROOT / 'validation/enemy-roles/time-wraith-dial.png'
L = LuaRuntime(unpack_returned_tuples=True)
L.execute('''
T=dofile('tests/combat/enemy_support.lua'); A=require('combat.enemies.actors.TimeWraith')
local noop=function()end
Variant=function(v)return v end;Color=function(...)return {...}end;Quaternion=function(a)return a or 0 end
Vector2=function(x,y)return {x=x,y=y}end
Material={new=function() return {SetTechnique=noop, SetCullMode=noop,
    SetSurfaceShader=function(m,s)m.shader=s;return true end,
    SetSurfaceTexture=function(m,k,v)m[k]=v;return true end,
    SetShaderParameter=function(m,k,v)m[k]=v end}end}
cache={GetResource=function(_,kind,path)return path end}; TRIANGLE_LIST=0; CULL_NONE=0
function node()
    return {enabled=true,scale=Vector3(1,1,1),rotation=0,CreateChild=function()return node()end,
    CreateComponent=function() return {verts={},BeginGeometry=noop,Commit=noop,DefineNormal=noop,DefineTexCoord=noop,SetMaterial=noop,
    DefineVertex=function(g,v)g.verts[#g.verts+1]=v end}end}
end
terrain,combat=T.Fixture();e=A.New(nil,nil,terrain,combat,Vector3.ZERO);e.scene=node();e.aggro=true;e.attackIndex=1;e:StartAttack()
''')
G=L.globals(); e=G.e
L.execute('''
local field=require('combat.enemies.actors.TimeWraithField'); local original=cache.GetResource
for _,failure in ipairs({'texture','shader','sampler'}) do
    local new=Material.new
    cache.GetResource=function(self,kind,path)
        if failure=='texture' and kind=='Texture2D' then return nil end
        return original(self,kind,path)
    end
    Material.new=function()
        local m=new()
        if failure=='shader' then m.SetSurfaceShader=function() return false end end
        if failure=='sampler' then m.SetSurfaceTexture=function() return false end end
        return m
    end
    local f=field.New(node()); assert(not f.floor.ink)
    field.Draw(f,Vector3.ZERO,'active',1);assert(f.floor.step>0 and f.ticks.step>0 and f.dust.step>0)
    field.Draw(f,nil,nil,0);assert(not f.root.enabled)
    Material.new=new;cache.GetResource=original
end
''')
frames=[(.18,'First impression'),(.72,'Copper plate'),(1.20,'Sweep begins'),(3.00,'Cold imprint'),(4.56,'Outer teeth lift'),(4.77,'Spindle remains')]
fields=[]; layers=[]; prev=0
for t,_ in frames:
    G.T.Tick(e,t-prev,G.combat.pos);prev=t; ink=e.fieldFx.floor.ink
    fields.append([ink.ink_phase,ink.phase_progress,ink.hand_turn]); polys=[]
    for name in ['rim','ticks','hand','dust','gold']:
        layer=e.fieldFx[name];n=layer.node; a=math.radians(n.rotation);c,s=math.cos(a),math.sin(a)
        verts=np.array([[v.x*n.scale.x,v.y*n.scale.y,v.z*n.scale.z] for v in layer.geom.verts.values()]);x,y,z=verts.T
        transformed=np.stack((x*c+z*s,y,-x*s+z*c),axis=1).reshape(-1,3,3)
        color=np.array(list(layer.mat.MatDiffColor.values()))
        for tri in transformed:polys.append((tri,tuple((color*255).astype(int))))
    layers.append(polys)

# Compile the runtime fragment body unmodified; map the three SurfaceShader
# built-ins and binding declarations to ES 3.0. Read back actual WebGL texels.
source=(ROOT/'assets'/ink.shader).read_text(); body=source[source.index('void fragment()'):].replace('void fragment()', 'void main()')
body=body.replace('ALBEDO = pigment;', 'frag.rgb = pigment;').replace('ALPHA =', 'frag.a =')
frag='''#version 300 es
precision highp float; in vec2 UV; out vec4 frag; uniform sampler2D dial_atlas; uniform float ink_phase,phase_progress,hand_turn;
'''+body
atlas=Image.open(ROOT/'assets'/ink.dial_atlas); assert atlas.mode=='RGBA' and atlas.size==(256,128) and 12<=len(atlas.getcolors())<=17
html=r'''<!doctype html><canvas width=128 height=128></canvas><pre></pre><script>
const canvas=document.querySelector('canvas'), out=document.querySelector('pre');
try {const gl=canvas.getContext('webgl2',{premultipliedAlpha:false,preserveDrawingBuffer:true});
 const prog=gl.createProgram();
 function shader(kind,text){const sh=gl.createShader(kind);gl.shaderSource(sh,text);gl.compileShader(sh);if(!gl.getShaderParameter(sh,gl.COMPILE_STATUS))throw gl.getShaderInfoLog(sh);gl.attachShader(prog,sh);}
 shader(gl.VERTEX_SHADER, '#version 300 es\nout vec2 UV;void main(){vec2 p=vec2(float((gl_VertexID<<1)&2),float(gl_VertexID&2));UV=vec2(p.x,1.-p.y);gl_Position=vec4(p*2.-1.,0.,1.); }');
 shader(gl.FRAGMENT_SHADER,FRAGMENT);gl.linkProgram(prog);if(!gl.getProgramParameter(prog,gl.LINK_STATUS))throw gl.getProgramInfoLog(prog);gl.useProgram(prog);
 const raw=Uint8Array.from(atob(ATLAS),c=>c.charCodeAt(0));gl.bindTexture(gl.TEXTURE_2D,gl.createTexture());
 gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,256,128,0,gl.RGBA,gl.UNSIGNED_BYTE,raw);
 for(const key of [gl.TEXTURE_MIN_FILTER,gl.TEXTURE_MAG_FILTER])gl.texParameteri(gl.TEXTURE_2D,key,gl.NEAREST);
 let images=[];for(const frame of FRAMES){['ink_phase','phase_progress','hand_turn'].forEach((k,i)=>gl.uniform1f(gl.getUniformLocation(prog,k),frame[i]));gl.drawArrays(gl.TRIANGLES,0,3); images.push(canvas.toDataURL().split(',')[1]);}out.textContent=JSON.stringify(images);
}catch(e){out.textContent='ERROR '+e;}</script>'''.replace(',FRAGMENT)',','+json.dumps(frag)+')').replace('atob(ATLAS)','atob('+json.dumps(base64.b64encode(atlas.tobytes()).decode())+')').replace('of FRAMES','of '+json.dumps(fields))
chrome=os.environ.get('CHROME_BIN') or shutil.which('chromium') or '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
with tempfile.TemporaryDirectory(prefix='dial-gl-') as tmp:
    page=Path(tmp)/'sample.html';page.write_text(html)
    proc=subprocess.run([chrome,'--headless','--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader','--disable-background-networking','--user-data-dir='+tmp+'/profile','--dump-dom',page.as_uri()],capture_output=True,text=True,timeout=35,check=True)
    value=re.search(r'<pre>(.*?)</pre>',proc.stdout,re.S)[1]; assert not value.startswith('ERROR'),value
    plates=[Image.open(io.BytesIO(base64.b64decode(p))).convert('RGBA') for p in json.loads(value)]
assert sum(plates[1].getchannel('A').histogram()[1:])>sum(plates[0].getchannel('A').histogram()[1:])
assert np.count_nonzero(np.asarray(plates[2])!=np.asarray(plates[3]))>3000
assert np.count_nonzero(np.asarray(plates[5])[:,:,3]) < np.count_nonzero(np.asarray(plates[4])[:,:,3])*.5
W,H=490,405; scale=70; centre=np.array([W*.5,251]); slope=.68; lift=(1-slope**2)**.5
sheet=Image.new('RGB',(W*3,H*2));fontfile='/System/Library/Fonts/Helvetica.ttc'
try: font=ImageFont.truetype(fontfile,18)
except OSError: font=ImageFont.load_default()
for i,((t,label),plate,polys) in enumerate(zip(frames,plates,layers)):
    tile=Image.new('RGBA',(W,H),(33,42,45,255));d=ImageDraw.Draw(tile)
    for j in range(-6,7):
        x=centre[0]+j*scale;z=centre[1]+j*scale*slope
        d.line((x,0,x,H),fill=(39,49,52));d.line((0,z,W,z),fill=(39,49,52))
    dia=2*2.8*scale;h=round(dia*slope); floor=plate.resize((round(dia),h),Image.Resampling.NEAREST)
    tile.alpha_composite(floor,(round(centre[0]-dia/2),round(centre[1]-h/2-lift*.037*scale)))
    tile=tile.convert('RGB');d=ImageDraw.Draw(tile,'RGBA')
    for vs,rgba in sorted(polys,key=lambda k:k[0][:,1].mean()*slope-k[0][:,2].mean()*lift):
        xy=[(round(centre[0]+x*scale),round(centre[1]-(z*slope+y*lift)*scale)) for x,y,z in vs];d.polygon(xy,fill=rgba)
    d.text((16,12),f'{t:.2f} s   {label}',font=font,fill=(244,235,209));sheet.paste(tile,(i%3*W,i//3*H))
OUT.parent.mkdir(parents=True,exist_ok=True);sheet.save(OUT);print('PASS WebGL2 fragment compile, real atlas upload, six phase readbacks:',OUT)
