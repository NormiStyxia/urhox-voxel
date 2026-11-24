#!/usr/bin/env python3
"""Reproducible role/geometry sampler for the five enemy roles.

Environment: Python 3 + Lupa(Lua 5.4) + Pillow; no UrhoX Runtime, physics
world, remote build or game frame. Mock scene/world only exercises real actor,
model, warning, hurt-shape and effect transform code.
"""
from pathlib import Path
import json, math
from lupa.lua54 import LuaRuntime
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'validation'/'enemy-roles'
OUT.mkdir(parents=True,exist_ok=True)

LUA=r'''
package.path='scripts/?.lua;tests/?.lua;'..package.path
local H=require('combat.actor_roles_support')
local T=H.T
local S=require('combat.enemies.EnemyBase').State
local function snap(e,name,label)
    local parts={}
    for _,h in ipairs(e:GetHurtShapes()) do
        parts[#parts+1]={id=h.id,x=h.center.x,y=h.center.y,z=h.center.z,r=h.radius,enabled=h.enabled}
    end
    return {name=name,label=label,state=e.state,t=e.stateTime,ax=e.position.x,ay=e.position.y,az=e.position.z,
        warning={visible=e.warning.visible,kind=e.warning.kind,radius=e.warning.radius,step=e.warning.step},
        parts=parts,thread=e.thread and {active=e.thread.active,range=e.thread.range,travel=e.thread.travel},
        optics=e.optics and {enabled=e.optics.root.enabled,radius=e.optics.radius,beam=e.beamLength},
        core=e.PartEnabled and e:PartEnabled({id='core'}) or nil,
        field=e.field and true or nil, domainStage=e.fieldStage,
        fault=e.fault and {active=e.fault.active,sections=#e.fault.sections} or nil, floor=e.floorY}
end
local function sample(name,idx,player)
    local e,mod,combat=H.newVisual(name)
    local a=e.config.attacks[idx]
    e:SetActive(true);e.aggro=true;e.attackIndex=idx-1;e.attack=a;e:Face(player);e:SetState(S.TELEGRAPH)
    local out={name=name,attack=a.name,range=a.range,warning=a.warning,
        telegraph=a.telegraph,duration=a.duration,recover=a.recover,frames={}}
    T.Tick(e,a.telegraph*.80,player);out.frames[#out.frames+1]=snap(e,name,'telegraph')
    T.Tick(e,a.telegraph*.20+.04,player);out.frames[#out.frames+1]=snap(e,name,'active')
    T.Tick(e,.20,player);out.frames[#out.frames+1]=snap(e,name,'recover')
    e:Destroy()
    return out
end
return {
 sample('WoodSpirit',1,Vector3(0,0,1.2)),
 sample('NestWeaver',1,Vector3(0,0,2.2)),
 sample('RockColossus',2,Vector3(0,0,1.5)),
 sample('RuinConstruct',2,Vector3(0,0,1.6)),
 sample('TimeWraith',2,Vector3(0,0,1.2)),
}
'''

def conv(v):
    if hasattr(v,'items'):
        d={k:conv(x) for k,x in v.items()}
        if d and all(isinstance(k,int) for k in d):
            return [d[k] for k in sorted(d)]
        return d
    return v

lua=LuaRuntime(unpack_returned_tuples=True)
data=conv(lua.execute(LUA))
(OUT/'role_samples_current.json').write_text(json.dumps(data,ensure_ascii=False,indent=2))

FONT='/System/Library/Fonts/STHeiti Medium.ttc'
def font(sz):
    try:return ImageFont.truetype(FONT,sz)
    except:return ImageFont.load_default()

W,H=440,360
sheet=Image.new('RGB',(W*5,H),(23,29,36)); d=ImageDraw.Draw(sheet)
roles={'WoodSpirit':'木灵 · 地面近战','NestWeaver':'织巢虫 · 飞行/拍翼','RockColossus':'岩甲巨兽 · 分部位/柱','RuinConstruct':'构装体 · 光束/开甲','TimeWraith':'时蚀 · 领域(待接)'}
pending={}

def arena(frame,box,item):
    x0,y0,x1,y1=box; cx,cy=(x0+x1)//2,(y0+y1)//2; scale=min(x1-x0,y1-y0)/7.0
    d.rectangle(box,outline=(70,78,86))
    for r in (1,1.85,2.25,3.6):
        d.ellipse((cx-r*scale,cy-r*scale,cx+r*scale,cy+r*scale),outline=(50,58,66))
    # actor / player
    ax=cx+frame['ax']*scale; ay=cy+frame['az']*scale
    px=cx+0*scale; py=cy+2.0*scale
    d.ellipse((ax-5,ay-5,ax+5,ay+5),fill=(220,90,60))
    d.ellipse((px-4,py-4,px+4,py+4),fill=(90,170,235))
    w=frame['warning']
    if w['visible']:
        col=(210,60,50)
        if w['kind']=='fault_strip':
            rr=item['range']*scale
            d.rectangle((ax-12,ay,ax+12,ay+rr),outline=col,width=2)
        elif w['kind']=='ring':
            rr=w['radius']*scale
            d.ellipse((ax-rr,ay-rr,ax+rr,ay+rr),outline=col,width=2)
        elif w['kind']=='fan':
            rr=item['range']*scale
            d.arc((ax-rr,ay-rr,ax+rr,ay+rr),start=240,end=300,fill=col,width=3)
        else:
            rr=item['range']*scale
            d.line((ax,ay,ax,ay+rr),fill=col,width=3)
    for p in frame['parts']:
        if p['enabled'] and p['r']>0:
            xx=cx+p['x']*scale; yy=cy+p['z']*scale; rr=max(2,p['r']*scale)
            d.ellipse((xx-rr,yy-rr,xx+rr,yy+rr),outline=(240,180,70),width=1)

for i,item in enumerate(data):
    name=item['name']; ox=i*W; d.rectangle((ox,0,ox+W-1,H-1),outline=(45,52,60))
    d.text((12,10),roles.get(name,name),font=font(18),fill=(238,235,225))
    d.text((12,34),f"{item['attack']}  range={item['range']}  warn={item['warning']}",font=font(12),fill=(170,180,190))
    f0=item['frames'][0]; f1=item['frames'][1]; f2=item['frames'][2]
    for j,(label,fr) in enumerate([('telegraph',f0),('active',f1),('recover',f2)]):
        bx=ox+12+j*139; by=62
        d.text((bx,by-14),label,font=font(11),fill=(160,170,180)); arena(fr,(bx,by,bx+128,by+150),item)
    d.text((12,226),f"state={f1['state']}  alt={f1['ay']-f1.get('floor',0):.2f}m  hitshapes={len(f1['parts'])}",font=font(11),fill=(190,198,206))
    if f1.get('thread'):
        d.text((12,244),f"thread active={f1['thread']['active']} travel={f1['thread']['travel']:.2f}",font=font(11),fill=(190,198,206))
    if f1.get('optics'):
        d.text((12,244),f"optics={f1['optics']['enabled']} radius={f1['optics']['radius']} beam={f1['optics']['beam'] or 0:.2f}",font=font(11),fill=(190,198,206))
        d.text((12,262),f"core open={f1.get('core')}",font=font(11),fill=(190,198,206))
    # timeline
    total=item['telegraph']+item['duration']+item['recover']; x=12; y=300; ww=W-24
    for label,val,col in [('T',item['telegraph'],(220,90,60)),('A',item['duration'],(240,180,70)),('R',item['recover'],(90,170,235))]:
        w2=ww*val/total; d.rectangle((x,y,x+w2,y+12),fill=col); d.text((x+3,y-2),label,font=font(10),fill=(20,20,20)); x+=w2
    d.text((12,320),f"budget sample only · mock scene/world · no UrhoX frame",font=font(10),fill=(140,150,160))
    if name in pending:
        d.rectangle((12,338,W-12,354),fill=(90,45,35)); d.text((16,340),pending[name],font=font(11),fill=(255,230,210))

sheet.save(OUT/'role_samples_current.png')
(OUT/'ROLE_SAMPLES_CURRENT.md').write_text('''# Enemy role samples (current reviewer sample)

- `role_samples_current.png`: top-down telegraph/active/recover geometry for the five actors, hurt-shape circles and timing bars.
- `role_samples_current.json`: exact sampled transforms, warning kinds, hurt shapes, thread/beam/field flags.

Environment: Python 3 + Lupa Lua 5.4 + Pillow; no UrhoX Runtime, physics world, remote build or game frame. Mock scene/world only constructs real actors/effect nodes. TimeWraith field scale is source-wired to Nomi run/gravity and CombatMoves attack/draw clocks; this sample is geometry-only, not a dynamic frame. Re-run: `python3 tests/combat/actor_role_samples.py` from `/private/tmp/ruins-enemy-roles`.
''')
print('wrote',OUT/'role_samples_current.png')
