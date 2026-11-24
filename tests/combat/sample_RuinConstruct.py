"""CPU geometry evidence, run from the repo root with python3 -B. No engine/GPU.
Evaluates the actual actor, FX node transforms, UVs, material exposure and RGBA atlas.
Orthographic CPU composition omits GPU lighting and approximates the narrow pilot light.
"""
from pathlib import Path
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from lupa.lua54 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
package.path='scripts/?.lua;tests/?.lua;'..package.path
local T=require('combat.enemy_support')
local model=require('combat.enemies.models.RuinConstruct').Build()
local C=require('combat.enemies.actors.RuinConstruct'); local FX=require('combat.enemies.actors.RuinConstructFX')
local noop=function()end
Color=function(r,g,b,a)return {r,g,b,a or 1} end; Variant=function(x)return x end
Vector2=function(x,y)return {x=x,y=y} end
Quaternion=function(a,v)return {degrees=a,axis=v} end
Material={new=function()return {SetTechnique=noop,SetCullMode=noop,SetSurfaceShader=function(_,path)return path=='Shaders/BLGL/RuinConstructOptics.shader' end,
    SetSurfaceTexture=function(m,k,v)m[k]=v;return true end,SetShaderParameter=function(m,k,v)m[k]=v end} end}
cache={GetResource=function(_,kind,path)if kind=='Texture2D' then return path end end}
local function node(name)
    local n={name=name,enabled=true,children={},verts={},uvs={}}
    function n:CreateChild(id)local c=node(id);self.children[#self.children+1]=c;return c end
    function n:LookAt(p) self.aim=p end
    function n:CreateComponent(type)
        self.box=type=='StaticModel';return {BeginGeometry=noop,Commit=noop,DefineNormal=noop,SetModel=noop,
            DefineTexCoord=function(_,v)self.uvs[#self.uvs+1]=v end,
            DefineVertex=function(_,p)self.verts[#self.verts+1]=p end,SetMaterial=function(_,m)self.mat=m end}
    end
    return n
end
function sample(t)
    getmetatable(Vector3.ZERO).LengthSquared=function(v)return v.x*v.x+v.y*v.y+v.z*v.z end
    local terrain,combat=T.Fixture();local e=C.New(nil,nil,terrain,combat,Vector3.ZERO,'sample')
    local scene=node('scene');local fx=FX.New(scene);e.optics=fx
    e.world={RaycastSingle=function(_,r,d)
        local z=r.direction.z;local n=z>0 and (4.0-r.origin.z)/z or -1
        return {hit=n>=0 and n<=d,distance=n,position=r.origin+r.direction*n,normal=Vector3(0,0,-1)}
    end};local target=Vector3(0,0,8);e.aggro=true;e.lastTarget=target;e:Face(target);e.attackIndex=1;e:StartAttack()
    T.Tick(e,t,target)
    local poses={}
    for _,p in ipairs(model.parts) do local v={x=0,y=0,z=0,pitch=0,yaw=0,roll=0,sx=1,sy=1,sz=1}
        C.Config.posePart(e,p.id,v);poses[p.id]=v end
    return model,poses,e.poseY,scene
end
''')

def vec(v, default=(0, 0, 0)):
    return np.array([v.x, v.y, v.z]) if v is not None else np.array(default)

def rotation(x, y, z):
    x,y,z=np.radians([x,y,z]);c=np.cos;s=np.sin
    return (np.array([[c(y),0,s(y)],[0,1,0],[-s(y),0,c(y)]]) @
            np.array([[1,0,0],[0,c(x),-s(x)],[0,s(x),c(x)]]) @
            np.array([[c(z),-s(z),0],[s(z),c(z),0],[0,0,1]]))

corners=np.array([[i&1,(i>>1)&1,(i>>2)&1] for i in range(8)])
faces=[((-1,0,0),[0,2,6,4]),((1,0,0),[1,5,7,3]),((0,-1,0),[0,4,5,1]),
       ((0,1,0),[2,3,7,6]),((0,0,-1),[0,1,3,2]),((0,0,1),[4,6,7,5])]

def frame(t, wide):
    model,pose,offset,scene=lua.globals().sample(t)
    fx=scene.children[1]
    view=np.array([.92,.20,.35]) if wide else np.array([.12,.12,1.])
    view/=np.linalg.norm(view);right=np.cross(view,[0,1,0]);right/=np.linalg.norm(right);up=np.cross(right,view)
    center=np.array([0,1.23,1.65 if wide else 0]);scale=89 if wide else 108
    polygons=[]
    def face(vertices, rgba, texture=None):
        rel=vertices-center
        xy=np.column_stack([235+scale*(rel@right),174-scale*(rel@up)])
        polygons.append(((rel@view).mean(),[tuple(p) for p in xy],tuple(rgba),texture))
    for part in model.parts.values():
        a=pose[part.id];rot=rotation(a.pitch,a.yaw,a.roll);pivot=np.array(list(part.pivot.values()))
        shift=np.array([a.x,a.y+offset,a.z]);sz=model.size
        cells={tuple(c[i] for i in (1,2,3)):c[4] for c in part.cells.values()}
        for xyz,idx in cells.items():
            mat=model.palette[idx];rgb=np.array(list(mat.rgb.values()));base=np.array(xyz)
            vertices=((base+corners)*sz-pivot)@rot.T+pivot+shift
            for normal,ids in faces:
                norm=rot@normal
                if norm@view<=0 or tuple(base+normal) in cells: continue
                gain=.53+.44*max(0,norm@[-.30,.72,.58])+.3*mat.emission
                face(vertices[ids],[*np.minimum(255,rgb*gain).astype(int),255])
    active=list((node,vec(fx.position)) for node in fx.children.values()) if fx.enabled else []
    active.extend((n,np.zeros(3)) for n in list(scene.children.values())[1:])
    swatches={}
    for n,origin in active:
        if not n.enabled: continue
        axis=vec(n.rotation.axis)*n.rotation.degrees if n.rotation else [0,0,0]
        rot=rotation(*axis)
        if n.aim:
            direction=vec(n.aim)-vec(n.position)
            rot=rotation(0,math.degrees(math.atan2(direction[0],direction[2])),0)@rot
        def transform(v):return (v*vec(n.scale,(1,1,1)))@rot.T+vec(n.position)+origin
        if n.mat.optics_tex:
            stamps=int(n.mat.stamp),int(n.mat.exposure)
            tile=atlas[stamps[0]*64:(stamps[0]+1)*64,stamps[1]*64:(stamps[1]+1)*64]
            by,bx=np.mgrid[:64,:64]
            brushed=tile.copy();brushed[:,:,3]*=(((bx*5+by*11+by//3)%19)/19 < n.mat.coverage)
            swatches[stamps[0]]=(Image.fromarray(brushed),stamps[1])
            vertices=transform(np.array([vec(v) for v in n.verts.values()]))
            uvs=np.array([(v.x,v.y) for v in n.uvs.values()])
            for j in range(0,len(vertices),3):
                face(vertices[j:j+3],(),(uvs[j:j+3],tile,n.mat.runs or 1,n.mat.coverage))
            continue
        color=n.mat.MatDiffColor;rgba=[int(255*color[i]) for i in (1,2,3,4)]
        if n.box:
            vertices=transform(corners-.5)
            for norm,ids in faces:
                if view@(rot@norm)>0:face(vertices[ids],rgba)
        else:
            vertices=transform(np.array([vec(v) for v in n.verts.values()]))
            for j in range(0,len(vertices),3):face(vertices[j:j+3],rgba)
    image=Image.new('RGB',(470,324),(25,31,39));d=ImageDraw.Draw(image,'RGBA')
    for _,polygon,color,tex in sorted(polygons,key=lambda p:p[0]):
        if tex is None: d.polygon(polygon,fill=color);continue
        uv,tile,runs,coverage=tex
        a,b,c=np.array(polygon)
        x0,y0=np.maximum(0,np.floor(np.minimum(a,np.minimum(b,c))).astype(int))
        x1,y1=np.minimum(image.size,np.ceil(np.maximum(a,np.maximum(b,c))).astype(int)+1)
        if x1<=x0 or y1<=y0:continue
        matrix=np.column_stack((b-a,c-a))
        if abs(np.linalg.det(matrix))<.01:continue
        yy,xx=np.mgrid[y0:y1,x0:x1];ab=np.stack((xx+.5-a[0],yy+.5-a[1]),axis=-1)@np.linalg.inv(matrix).T
        inside=(ab[:,:,0]>=0)&(ab[:,:,1]>=0)&(ab.sum(axis=2)<=1)
        coords=np.clip(uv[0]+ab@np.stack((uv[1]-uv[0],uv[2]-uv[0])),0,.99999)
        u=((coords[:,:,0]*runs%1)*64).astype(int);v=(coords[:,:,1]*64).astype(int)
        pixels=tile[v,u].copy();pixels[:,:,3]*=inside&(((u*5+v*11+v//3)%19)/19<coverage)
        patch=Image.fromarray(pixels);image.paste(patch,(x0,y0),patch)
    return image,swatches

atlas=np.array(Image.open("assets/Textures/fx/RuinConstructOptics.png").convert("RGBA"))
sheet=Image.new('RGB',(1410,940),(17,22,28));d=ImageDraw.Draw(sheet)
font=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',19) if Path('/System/Library/Fonts/Helvetica.ttc').exists() else ImageFont.load_default()
for i,(t,label,wide) in enumerate([(.39,'Gilt relief / outer sweep',False),(1.10,'Inner seal / locked line',True),
                                   (1.29,'Charge packets',True),(1.59,'Wall overload',True),
                                   (1.91,'Open core / hot vent',False),(2.27,'Open core / cold vent',False)]):
    x,y=i%3*470,i//3*470;scene_image,swatches=frame(t,wide);sheet.paste(scene_image,(x,y+40));d.text((x+12,y+10),f'{t:.2f} s   {label}',font=font,fill=(220,229,235))
    # Nearest texel enlargement of the actual active stamp and exposure.
    ids=([0,1],[0,1],[2,3],[3,4],[5],[5])[i]
    labels=['Outer seal','Inner seal','Charge','Corona','Wall scar','Vent']
    for j,row in enumerate(ids):
        if row not in swatches:continue
        tile,index=swatches[row];tile=tile.resize((84,84),Image.Resampling.NEAREST);sx=x+14+j*221
        sheet.paste(tile,(sx,y+372),tile);d.text((sx+90,y+400),f'{labels[row]}\n{index+1}/8',font=font,fill=(195,207,215))
out=Path(__file__).with_name('RuinConstruct-actions.png');sheet.save(out);print(out)
