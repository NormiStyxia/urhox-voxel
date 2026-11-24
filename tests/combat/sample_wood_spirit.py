"""Run from the worktree root with Python 3, Lupa Lua 5.4, NumPy and Pillow."""
from pathlib import Path
import math
import runpy
import sys

import numpy as np
from lupa.lua54 import LuaRuntime
from PIL import Image, ImageDraw, ImageFont

studio = runpy.run_path('art/enemy-turnarounds/render_enemy_models.py')
model = studio['load_model']('WoodSpirit')
sample, fx = LuaRuntime(unpack_returned_tuples=True).execute('''
package.path='scripts/?.lua;tests/?.lua;'..package.path
local T=require('combat.enemy_support'); local W=require('combat.enemies.actors.WoodSpirit')
local model=require('combat.enemies.models.WoodSpirit').Build()
return function(index,t,evade)
    local terrain,combat=T.Fixture();local e=W.New(nil,nil,terrain,combat,Vector3.ZERO,'sample')
    local target=Vector3(0,0,index==1 and 1.0 or 2.2)
    e:Face(target);e.aggro=true
    if index==0 then e:SetState(W.State.CHASE);T.Tick(e,t,Vector3(0,0,8))
    else
        e.attackIndex=index-1;e.lastTarget=target;e:StartAttack()
        local lock=e.attack.telegraph-.12
        T.Tick(e,math.min(lock,t),target)
        T.Tick(e,math.max(0,t-lock),evade and Vector3(1.4,0,2.2) or target)
    end
    local poses={}
    for _,part in ipairs(model.parts) do
        local p={x=0,y=0,z=0,pitch=0,yaw=0,roll=0,sx=1,sy=1,sz=1}
        W.Config.posePart(e,part.id,p);poses[part.id]=p
    end
    return e,poses
end,require('combat.enemies.actors.WoodSpiritFX')
''')


def rotation(pitch, yaw, roll):
    a,b,c = np.radians([pitch,yaw,roll]); ca,cb,cc = np.cos([a,b,c]); sa,sb,sc = np.sin([a,b,c])
    return np.array([[cb,0,sb],[0,1,0],[-sb,0,cb]]) @ np.array([[1,0,0],[0,ca,-sa],[0,sa,ca]]) @ np.array([[cc,-sc,0],[sc,cc,0],[0,0,1]])


def vector(a):
    return np.array(a) / np.linalg.norm(a)


axes = np.vstack((np.eye(3),-np.eye(3)))

def mesh(cells, size):
    faces=[]
    for coord,slot in cells.items():
        for n in axes:
            if tuple(coord+n) not in cells:
                faces.append((np.array(studio['face_geometry'](coord,n,size)),n,slot))
    return faces

parts=[(p['id'],np.array(p['pivot']),mesh({tuple(c[:3]):c[3] for c in p['cells']},model['size'])) for p in model['parts']]
chip=mesh({(0,0,0):1},1)
camera=vector([.85,.34,.69]);right=vector(np.cross(camera,[0,1,0]));up=np.cross(right,camera)
light=vector([.28,.9,.55]); ambient=(.25,.22,.21)
fontpath=Path('/System/Library/Fonts/Supplemental/Arial.ttf')
font=ImageFont.truetype(str(fontpath),19) if fontpath.exists() else ImageFont.load_default()
small=ImageFont.truetype(str(fontpath),14) if fontpath.exists() else ImageFont.load_default()
# CPU evaluation of the shipped phase shader, over texels read from its PNG atlas.
# Returns straight RGBA, matching blend_mix. No filtering before quantization.
atlas=np.asarray(Image.open(Path('assets')/fx.Atlas).convert('RGBA'),dtype=float)/255
assert atlas.shape==(128,64,4) and len(np.unique(atlas.reshape(-1,4),axis=0))==8
row,col=np.indices((64,64)); u=(col+.5)/64; v=(row+.5)/64

def reference_brush(impact,phase):
    raw=atlas[64*impact:64*impact+64]
    grain=(col*3+(row//2)*5)%11/11
    distance=np.hypot(2*u-1,2*v-1) if impact else v
    edge=math.floor(min(1,max(0,phase))*24)/24*1.85+.08
    reveal=distance+grain*.07<=edge
    rim=np.abs(edge-distance)<.12
    wipe=grain*.65+distance*.35+.01>=(phase-.63)/.37
    gain=.68*rim[:,:,None]
    color=raw[:,:,:3]*(1-gain)+np.array([1,.81,.42])*gain
    alpha=raw[:,:,3]*reveal*wipe*(.98 if impact else .86)
    shoulder=np.abs(u-.5)*1.7+np.abs(v-.52)*.65
    band=.5*(shoulder>=.34)+.5*(shoulder>=.62)
    soil=(1-impact)*(.37+.19*band+.08*(phase>=.78))
    clay=(1-band[:,:,None])*np.array([.83,.25,.12])+band[:,:,None]*np.array([.65,.10,.08])
    opacity=alpha+soil*(1-alpha)
    rgb=(color*alpha[:,:,None]+clay*soil[:,:,None]*(1-alpha[:,:,None]))/np.maximum(.001,opacity[:,:,None])
    return np.uint8(np.round(np.dstack((rgb,opacity))*255))

gpu=None
if sys.platform=='darwin':
    from wood_spirit_gpu_sample import BrushGPU
    gpu=BrushGPU(np.uint8(atlas*255))

def brush(impact,phase):
    reference=reference_brush(impact,phase)
    if not gpu: return reference
    result=gpu.render(impact,phase)
    assert np.max(np.abs(result.astype(int)-reference.astype(int)))<=1
    return result

W,H=480,330
sheet=Image.new('RGB',(W*3,H*2),'white')
shots=[('Soil lifts',2,.26,False),('Root impression',2,.56,False),('Broken brush clears',2,.82,False),
       ('Headbutt / resin flash',1,.63,False),('Forefeet / bark crest',2,1.48,True),('Impact erodes',2,1.595,True)]
def render_shot(attack,t,evade,terrain=None,dist=None):
    actor,poses=sample(attack,t,evade); im=Image.new('RGB',(W,H),(244,240,227)); d=ImageDraw.Draw(im)
    center=np.array([0,0,actor.position.z]); base=np.array([150 if actor.warning.visible else 206,209 if actor.warning.visible else 225]);scale=103
    if dist:
        pitch=math.radians(12); direction=vector([.85,0,.69]); forward=math.cos(pitch)*direction+[0,math.sin(pitch),0]
        vertical=np.cross(right,forward); eye=center+direction*dist+[0,1.65+5*math.sin(pitch),0]
        focal=270/(2*math.tan(math.radians(55)/2))
        def project(v):
            rel=np.asarray(v)-eye; depth=-rel@forward
            return np.array([W/2,135])+np.stack((rel@right,-rel@vertical),axis=-1)*focal/depth[...,None]
        # Crop around the same actor/footprint without changing perspective or apparent size.
        shift=np.array([W/2,155])-project(center+[0,0,.7]); raw_project=project
        def project(v): return raw_project(v)+shift
        yy,xx=np.indices((H,W)); rays=(-forward+(xx[:,:,None]-W/2-shift[0])*right/focal
                                       -(yy[:,:,None]-135-shift[1])*vertical/focal)
        points=eye+rays*((.041-eye[1])/np.minimum(-.015,rays[:,:,1]))[:,:,None]
        x,z=points[:,:,0]-center[0],points[:,:,2]-center[2]
        noise=np.sin(x*3.1+z*.9)*2+np.sin(x*.9-z*4.3)*1.8+np.sin(np.floor(x*7)*4+np.floor(z*7)*8)*2
        ground=np.clip(np.array(terrain)+noise[:,:,None],0,255).astype('uint8')
        im=Image.fromarray(ground); d=ImageDraw.Draw(im)
    else:
        def project(v): return base+np.stack(((v-center)@right,-(v-center)@up),axis=-1)*scale
    for grid in ([] if dist else np.arange(-3,4,.5)):
        for p,q in (([grid,0,-3],[grid,0,6]),([-3,0,grid],[3,0,grid])):
            d.line([tuple(project(p)),tuple(project(q))],fill=(228,222,208))
    if actor.warning.visible:
        sections=fx.SoilSections(actor.attack)
        rim=[(s[2],s[1]) for s in sections.values()]
        boundary=[tuple(project(center+[x,.041,z])) for x,z in rim+[(-x,z) for x,z in reversed(rim)]]
        tile=brush(0,actor.woodFX.phase)
        radius=actor.attack.hitRange+.32
        # Inverse-map ground pixels into the same planar UVs as soilSurface.
        if not dist:
            yy,xx=np.indices((H,W)); start=project(center+[0,.041,0])
            basis=np.stack(([right[0],-up[0]],[right[2],-up[2]]),axis=1)*scale
            x,z=np.linalg.solve(basis,np.stack((xx-start[0],yy-start[1])).reshape(2,-1)).reshape(2,H,W)
        tex=tile[np.clip((z/actor.attack.range*64).astype(int),0,63),np.clip(((.5+x/(2*radius))*64).astype(int),0,63)].copy()
        mask=Image.new('L',(W,H));ImageDraw.Draw(mask).polygon(boundary,fill=255)
        tex[:,:,3]=np.where(np.asarray(mask)>0,tex[:,:,3],0)
        im.paste(Image.fromarray(tex),mask=Image.fromarray(tex[:,:,3]))
        for layer,quads in fx.RimQuads(actor.attack).items():
            col=tuple(round(fx.RimColors[layer][i]*255) for i in (1,2,3))
            for q in quads.values():
                points=[tuple(project(center+[v[1],.055,v[2]])) for v in q.values()]
                d.polygon(points,fill=col)
    polys=[]
    def emit(faces,pivot,rot,sc,origin,override=None):
        for verts,normal,slot in faces:
            n=rot@normal
            if n@camera < .001: continue
            v=((verts-pivot)*sc)@rot.T+origin
            p=model['palette'][(override or slot)-1]
            color=studio['shade'](p['rgb'],p['roughness'],p['metallic'],p['emission'],n,light,ambient,-camera)
            polys.append((v.mean(axis=0)@camera,[tuple(q) for q in project(v)],color))
    for name,pivot,faces in parts:
        p=poses[name];emit(faces,pivot,rotation(p.pitch,p.yaw,p.roll),[p.sx,p.sy,p.sz],pivot+center+[p.x,p.y+actor.poseY,p.z])
    chips=[s for s in actor.woodFX.slots.values() if s.alive]
    for s in chips:
        emit(chip,np.array([.5,.5,.5]),rotation(s.angle,s.yaw,s.angle*.4),[s.width,s.height,s.depth],np.array([s.x,s.y,s.z]),s.palette)
    for stamp in actor.woodFX.stamps.values():
        if not stamp.active: continue
        tile=brush(1,stamp.age/stamp.life)
        rot=rotation(stamp.pitch,stamp.yaw,0)
        for y,x in np.argwhere(tile[:,:,3]>0):
            quad=np.array([[(x+dx)/64-.5,0,(y+dy)/64-.5] for dx,dy in ((0,0),(0,1),(1,1),(1,0))])
            verts=(quad*stamp.scale)@rot.T+[stamp.x,stamp.y,stamp.z]
            polys.append((verts.mean(axis=0)@camera,[tuple(q) for q in project(verts)],tuple(map(int,tile[y,x]))))
    alpha_draw=ImageDraw.Draw(im,'RGBA')
    for _,points,rgb in sorted(polys,key=lambda f:f[0]):alpha_draw.polygon(points,fill=rgb)
    state,clock=actor.state,actor.stateTime
    actor.Destroy(actor)
    if not dist:
        inset=Image.fromarray(tile).resize((112,112),Image.Resampling.NEAREST)
        d.rectangle((W-126,8,W-9,126),fill=(220,214,197)); im.paste(inset,(W-123,11),inset)
    return im,state,clock,len(chips)

for idx,(label,attack,t,evade) in enumerate(shots):
    im,state,clock,chips=render_shot(attack,t,evade);d=ImageDraw.Draw(im)
    d.rectangle([0,276,W,329],fill=(246,243,235))
    d.text((15,280),label,font=font,fill=(48,43,36)); d.text((15,306),f'{state.lower()}  {clock:.2f} s    |    {chips} chips',font=small,fill=(95,84,68))
    sheet.paste(im,(idx%3*W,idx//3*H))
out=Path('validation/enemy-roles/WoodSpirit-actions.png');out.parent.mkdir(exist_ok=True,parents=True);sheet.save(out);print(out)

# 480x270 perspective samples reduced by half with a box filter to test minification.
# Swatches are controlled backgrounds, not captures of the terrain renderer.
reads=[('Pounce / imprint',2,.56),('Pounce / release',2,.86),('Headbutt / release',1,.44)]
thumb=Image.new('RGB',(110+6*240,54+3*135+28),(248,245,235)); draw=ImageDraw.Draw(thumb)
for j,(name,color) in enumerate([('Light sand',(230,214,177)),('Grass',(104,139,81)),('Shadow',(52,63,66))]):
    draw.text((9,109+135*j),name,font=small,fill=(52,48,40))
    for i,(label,attack,t) in enumerate(reads):
        for k,dist in enumerate((5.5,10.5)):
            left=110+(i*2+k)*240
            if j==0:
                draw.text((left+5,6),label,font=font,fill=(52,48,40))
                draw.text((left+5,31),f'{dist} m   |   {t:.2f} s',font=small,fill=(75,65,56))
            im,_,_,_=render_shot(attack,t,False,color,dist)
            thumb.paste(im.crop((0,0,480,270)).resize((240,135),Image.Resampling.BOX),(left,54+j*135))
draw.text((110,463),'12 deg pitch  /  55 deg FOV  /  eye 2.69 m  /  240 x 135 per view',font=small,fill=(55,48,40))
readability=out.with_name('WoodSpirit-readability.png');thumb.save(readability);print(readability)
if gpu: gpu.close()
