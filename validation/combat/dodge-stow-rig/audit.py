"""Offline geometry + real quaternion audit. No game Runtime is launched.
Character faces are NomiVoxelData with BlockCharacter.SLENDER rest shaping.
"""
import itertools
import json
import subprocess
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from lupa.lua54 import LuaRuntime, lua_type

OUT=Path(__file__).resolve().parent
def plain(v):
    if lua_type(v)!='table': return v
    keys=list(v.keys())
    if keys and set(keys)==set(range(1,len(keys)+1)): return [plain(v[i]) for i in range(1,len(keys)+1)]
    return {str(k):plain(v[k]) for k in keys}

def lua_state(old=False):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path='scripts/?.lua;tests/combat/?.lua;'..package.path;Mock=require('weapon_mock');P=require('combat.WeaponParts');B=require('combat.WeaponBuilder')")
    if old:
        source=subprocess.check_output(['git','show','HEAD:scripts/combat/WeaponRig.lua'],text=True)
        lua.globals().old_source=source
        lua.execute("package.loaded['combat.WeaponRig']=assert(load(old_source))()")
    lua.execute("""Rig=require('combat.WeaponRig');scene=Mock.Node('audit');world=Mock.World(scene);c=Mock.Nomi(scene)
        local lift=c.node:CreateChild('SlenderLift');lift.position=Vector3(0,.1386,0)
        c.nomi.bones.body:SetParent(lift);c.nomi.bones.body.position=Vector3(0,.396,-.022)
        r=Rig.New(scene,world,c)
        function snapshot(weapon)
            r:SetActive(weapon);r:SetPose('back');r:Update(.5)
            r.visualClock=0;r.hangReady=false;r:Update(0)
            local node=r.entries[weapon].pivot
            local q=node.worldRotation;local p=node.worldPosition
            return {position={p.x,p.y,p.z},rotation={q.w,q.x,q.y,q.z}}
        end
    """)
    return lua

def rotation(q):
    w,x,y,z=q
    return np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
        [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
        [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])

lua=lua_state();old=lua_state(True)
data=plain(lua.eval("require('game.NomiVoxelData')")[0])
palette=np.array(data['palette'])*255
shape_skip={'head'}
scales={'head':.82,'hair_locks':.85,'hair_back':.85,'leg_right':1.35,'leg_left':1.35}
def shape(bone,p):
    p=np.array(p,dtype=float).copy()
    if bone not in shape_skip:
        p[0]*=.85;p[2]=-1+(p[2]+1)*.92
    return p

bones={b['name']:b for b in data['bones']}
world={}
for name,b in bones.items():
    parent=b.get('parent');owner=parent or name
    offset=(shape(owner,b['pivot'])-(shape(parent,bones[parent]['pivot']) if parent else np.zeros(3)))*data['unit']
    world[name]=(world[parent] if parent else np.zeros(3))+offset
    if name=='root': world[name]+=np.array([0,.1386,0])

def character_points(bone,points):
    local=np.array([shape(bone,np.array(p)+data['origin'])-shape(bone,bones[bone]['pivot']) for p in points])*data['unit']
    sc=scales.get(bone,1)
    local*=np.array([1,sc,1]) if bone.startswith('leg_') else sc
    return local+world[bone]

character=[]
for bone,quads in data['quads'].items():
    for direction,layer,u,v,w,h,color in quads:
        axis=(direction-1)//2;plane=layer+(direction%2==1)
        if axis==0: pts=[[plane,v,u],[plane,v+h,u],[plane,v+h,u+w],[plane,v,u+w]]
        elif axis==1: pts=[[u,plane,v],[u+w,plane,v],[u+w,plane,v+h],[u,plane,v+h]]
        else: pts=[[u,v,plane],[u+w,v,plane],[u+w,v+h,plane],[u,v+h,plane]]
        character.append((character_points(bone,pts),palette[color-1],bone))
for bone,tris in data.get('tris',{}).items():
    for tri in tris:
        character.append((character_points(bone,np.array(tri[:9]).reshape(3,3)),palette[tri[9]-1],bone))
char_lo=np.array([p.min(axis=0) for p,_,_ in character]);char_hi=np.array([p.max(axis=0) for p,_,_ in character])

corners=np.array(list(itertools.product([-.5,.5],repeat=3)))
faces=[[0,1,3,2],[4,5,7,6],[0,1,5,4],[2,3,7,6],[0,2,6,4],[1,3,7,5]]
colors=np.array([p['rgb'] for p in plain(lua.globals().P.ColorPresets)])
def geometry(bp,pose,weapon):
    q=rotation(pose['rotation']);pos=np.array(pose['position']);sc=np.array([1.3,1.25,1]) if weapon=='sword' else np.ones(3)
    polygons=[];lows=[];highs=[]
    for c in plain(bp.geometry.cells):
        vertices=((corners+np.array([c['x'],c['y'],c['z']]))*.03*sc)@q.T+pos
        lows.append(vertices.min(axis=0));highs.append(vertices.max(axis=0))
        channel=c['channel'];index=bp.config.colors['primary' if channel=='dark' else channel]
        color=colors[index-1]*(.38 if channel=='dark' else 1)
        for face in faces: polygons.append((vertices[face],color,'weapon'))
    return polygons,np.array(lows),np.array(highs)

poses={'before':{},'after':{}}
for weapon in ['sword','bow']:
    poses['before'][weapon]=plain(old.globals().snapshot(weapon))
    poses['after'][weapon]=plain(lua.globals().snapshot(weapon))
    q=rotation(poses['after'][weapon]['rotation'])
    print(weapon,'pivot(m)',poses['after'][weapon]['position'],'Y axis',q[:,1].tolist(),'Z axis',q[:,2].tolist())
    if weapon=='sword': assert q[1,1]<-.96
    else: assert abs(np.degrees(np.arccos(q[1,1]))-35)<1e-7 and q[2,2]<-.99

rows=[]
for weapon in ['sword','bow']:
    p,b=lua.globals().P,lua.globals().B
    slots=plain(p.Slots[weapon]);options=[[v['id'] for v in plain(p.GetOptions(weapon,s))] for s in slots]
    for ids in itertools.product(*options):
        config=p.DefaultWeapon(weapon);config.weapon=weapon
        for slot,ident in zip(slots,ids): config.parts[slot]=ident
        bp=b.Compile(config);_,lo,hi=geometry(bp,poses['after'][weapon],weapon)
        clearance=float('inf');lag_clearance=float('inf')
        pivot=np.array(poses['after'][weapon]['position'])
        for low,high in zip(lo,hi):
            gap=np.maximum(0,np.maximum(char_lo-high,low-char_hi))
            clearance=min(clearance,float(np.sqrt((gap*gap).sum(axis=1)).min()))
            # Conservative full 5deg rotation envelope, +12cm lateral/vertical
            # spring lag +2cm bob and at most 2.5cm inward lag. Character rests.
            radius=np.linalg.norm(np.maximum(abs(low-pivot),abs(high-pivot)))
            turn=2*radius*np.sin(np.radians(2.5))
            wide_lo=low-np.array([.12,.14,.12])-turn
            wide_hi=high+np.array([.12,.14,.025])+turn
            gap=np.maximum(0,np.maximum(char_lo-wide_hi,wide_lo-char_hi))
            lag_clearance=min(lag_clearance,float(np.sqrt((gap*gap).sum(axis=1)).min()))
        rows.append({'weapon':weapon,'parts':ids,'min':lo.min(axis=0).tolist(),'max':hi.max(axis=0).tolist(),
            'rest_surface_aabb_gap':clearance,'rest_character_lag_envelope_gap':lag_clearance})
    subset=[r for r in rows if r['weapon']==weapon]
    print(weapon,'all combinations',len(subset),'min rest surface AABB gap(m)',min(r['rest_surface_aabb_gap'] for r in subset),
        'min floor y',min(r['min'][1] for r in subset),'max y',max(r['max'][1] for r in subset),
        'min lag envelope gap',min(r['rest_character_lag_envelope_gap'] for r in subset))
assert all(r['rest_surface_aabb_gap']>0 and r['min'][1]>0 and r['rest_character_lag_envelope_gap']>0 for r in rows)

PAPER=(238,230,210);INK=(44,57,59)
def text(d,xy,s,size=16): d.text(xy,s,fill=INK,font=ImageFont.truetype('/System/Library/Fonts/STHeiti Medium.ttc',size))
def panel(d,polygons,cx,cy,side=False,scale=190):
    axes=(2,1,0) if side else (0,1,2)
    for points,color,kind in sorted(character+polygons,key=lambda t:float(t[0][:,axes[2]].mean()),reverse=not side):
        rgb=color if kind=='weapon' else color*.35+np.array(PAPER)*.65
        d.polygon([(cx+p[axes[0]]*scale,cy-p[axes[1]]*scale) for p in points],fill=tuple(int(x) for x in rgb))
    d.line((cx-100,cy,cx+100,cy),fill=(160,160,145))

im=Image.new('RGB',(1200,610),PAPER);d=ImageDraw.Draw(im)
text(d,(20,14),'背挂轮廓 · 实际体素/人物网格离线正投影（非引擎渲染）',24)
text(d,(20,55),'修长诺米静止姿态；旧/新同尺度；每栏只有一把武器。',16)
for col,(version,weapon,title) in enumerate([('before','sword','原：剑尖朝上'),('after','sword','新：剑柄朝上 / 尖向下'),('before','bow','原：弓横挂'),('after','bow','新：弓斜 35° / 弦向内')]):
    c=lua.globals().P.DefaultWeapon(weapon);c.weapon=weapon
    polys,_,_=geometry(lua.globals().B.Compile(c),poses[version][weapon],weapon)
    text(d,(col*300+15,95),title,18);panel(d,polys,col*300+150,535)
text(d,(20,573),'人物颜色淡化用于轮廓审查；武器=当前色板；真实光照、披风动态与镜头遮挡待 Web。',16)
im.save(OUT/'back-comparison.png')
im=Image.new('RGB',(900,610),PAPER);d=ImageDraw.Draw(im)
text(d,(20,14),'新背挂侧向关系 · 非引擎渲染',24)
text(d,(20,54),'左=人物后方 -Z，右=前方 +Z。静止表面间距是保守 AABB 估计，不是动态穿模验收。',15)
for i,weapon in enumerate(['sword','bow']):
    c=lua.globals().P.DefaultWeapon(weapon);c.weapon=weapon
    polys,_,_=geometry(lua.globals().B.Compile(c),poses['after'][weapon],weapon)
    text(d,(i*450+60,105),weapon+' / 右侧 +X',18);panel(d,polys,i*450+270,530,True,245)
im.save(OUT/'side-clearance.png')
(OUT/'geometry.json').write_text(json.dumps({'poses':poses,'combinations':rows},ensure_ascii=False,indent=2)+chr(10))
print('PASS 72 combinations: point-down sword / 35deg bow / string inward / positive rest surface gap / above floor')
print('PASS projections: back-comparison.png, side-clearance.png; includes actual SLENDER character quads/triangles')
