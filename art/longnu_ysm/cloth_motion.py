"""Bake the fitted skirt, coat and accessories in hip space on Longnu's six locomotion clips."""
import math
import re
import uuid

import numpy as np
from scipy.spatial.transform import Rotation
from build_longnu import rot_matrix
from audit_animations import channels

CORE = {'run','walk','jump','idle','sneak','sit'}


# Local offsets fitted to the full clip; both coat halves share the same correction.
FIT = {'walk': {'Tail': [0.3255, -0.3255, 0.3255], 'WaistBow': [0.0, 0.0, -1.0789]},
 'idle': {'Tail': [0.0, -0.1703, 0.1703], 'WaistBow': [0.0, 0.0, -0.0457]},
 'run': {'NomiOvercoat': [-0.5877, 0.9903, 0.0],
         'NomiWaistFollow': [0.0, 0.0708, 0.0],
         'Tail': [0.0, -0.5185, 0.5185],
         'WaistBow': [0.0, 0.0, -1.4955]},
 'jump': {'Tail': [0.0, -0.4785, -0.4785], 'WaistBow': [0.3567, -0.3567, 0.3567]},
 'sneak': {'Tail': [0.0, -0.9185, 0.0], 'WaistBow': [0.0, 0.0, -2.3753]},
 'sit': {'NomiOvercoat': [0.0, 0.0, 0.9079],
         'NomiWaistFollow': [0.0, -0.7011, 0.7011],
         'Tail': [0.0, -1.0194, -1.0194],
         'WaistBow': [0.6489, 0.0, -0.6489]}}


def driven(name):
    return (name in ('Tail','WaistBow','NomiUniformBell','NomiOvercoat','NomiWaistFollow','Skirt') or
            name.startswith(('NomiPleat','NomiCoat','RibbonTail','InnerRibbonTail')))


def affine(linear, origin, displacement=(0,0,0)):
    out = np.eye(4)
    out[:3,:3] = linear
    out[:3,3] = origin-linear@origin+displacement
    return out


def apply(point, matrix):
    return matrix[:3,:3]@point+matrix[:3,3]


def retarget(model):
    groups = {g['uuid']:g for g in model['groups']}
    order = []
    def visit(node,parent):
        g=groups[node['uuid']]; order.append((g,parent))
        for child in node['children']:
            if isinstance(child,dict):visit(child,g['name'])
    visit(model['outliner'][0],None)
    ids = {g['name']:g['uuid'] for g,parent in order}
    for anim in model['animations']:
        if anim['name'] not in CORE:continue
        curves=channels(anim); tracks=anim['animators']
        duration=anim['length'] or max(k['time'] for tr in tracks.values() for k in tr.get('keyframes',[]))
        baked={}
        for time in np.linspace(0,duration,33):
            def sample(name,channel,default):
                c=curves.get((ids[name],channel))
                return np.array([np.interp(time,c[0],axis) for axis in c[1]]) if c else np.array(default)
            hips=[sample(side+'Leg','rotation',(0,0,0))[0] for side in ('Left','Right')]
            knees=[sample(side+'LowerLeg','rotation',(0,0,0))[0] for side in ('Left','Right')]
            pleat=max(sample('NomiPleatSwing'+str(n)+'_'+str(j),'rotation',(0,0,0))[0] for n in (0,10,11) for j in (0,1))
            fore=max(0,*hips); aft=min(0,*hips)
            # A normal stride lifts the front with the thigh; the back also clears the flexed knee.
            split=(max(hips)-min(hips))/2
            mid=sum(hips)/2
            pivot=np.array([0.,19.30,0.]); wave=math.sin(time/duration*math.tau)
            spread=math.sin(math.radians(split)); flex=max(0,-min(knees)-40)/100
            skirt_z=1.10+1.66*spread+.29*flex
            coat_z=1.05+1.58*spread+.29*flex
            skirt_r=rot_matrix((mid,0,0)); coat_r=rot_matrix((mid-.9*flex,0,0))
            skirt=affine(skirt_r@np.diag([1.085,1.-.16*flex,skirt_z]),pivot,(0,.25+.43*flex,0))
            coat=affine(coat_r@np.diag([1.085,1.-.24*flex,coat_z]),pivot,(0,.18+.46*flex,0))
            # Evaluate the body first: the jacket and waist live on different branches.
            source_world={}; local_source={}
            for g,parent in order:
                name=g['name'];o=np.array(g['origin']);r=sample(name,'rotation',[0,0,0]);p=sample(name,'position',[0,0,0]);sc=sample(name,'scale',[1,1,1])
                local=affine(rot_matrix(g['rotation']+r)*sc,o,p);local_source[name]=local
                source_world[name]=source_world[parent]@local if parent else local
            leg=source_world['Leg']; world={};
            for g,parent in order:
                name=g['name'];o=np.array(g['origin']);par=world[parent] if parent else np.eye(4)
                if not driven(name):
                    world[name]=par@local_source[name];continue
                r=np.zeros(3);p=np.zeros(3);sc=np.ones(3);goal=None
                if name=='NomiWaistFollow':goal=leg@skirt
                elif name=='NomiOvercoat':goal=leg@coat
                elif name.startswith('NomiPleatRoot') or name.startswith('NomiPleatSwing'):
                    front=-o[2]/max(2.7,abs(o[2]));r[0]=front*split*.065
                elif re.fullmatch(r'NomiCoat[LR][0-3](Hip|Hem|Tat[0-2])',name):
                    rear=name[9] in '23'; gain=1 if name.endswith('Hip') else .40 if name.endswith('Hem') else .17
                    r[0]=gain*((aft*.14-flex*2) if rear else fore*.095)
                elif name=='WaistBow':
                    anchor=apply(o+np.array([0.,.06,-.07]),source_world['UpperBody'])
                    goal=leg@affine(skirt_r,o)
                    goal[:3,3]+=anchor-apply(o,goal)
                elif 'RibbonTail' in name:
                    tier=int(name[-1]); clearance=max(0,fore-mid,pleat*.54)
                    r[0]=clearance*(1.05,.065,.035,.012)[tier]+(.75+.35*wave if tier==0 else .3*wave)
                    r[2]=(-1.0 if name.startswith('Ribbon') else -.6) if tier==0 else 0
                    if anim['name']=='sit' and tier==0:
                        r[0]-=5
                        if name.startswith('Ribbon'):
                            r[2]+=5
                elif name=='Tail':
                    outlet=np.array([.35,14.5,4.]); anchor=apply(outlet,coat);anchor[2]+=.55*spread+.50*flex;anchor[1]-=.50*flex
                    angle=min(0,aft*.72)-flex*8
                    goal=leg@affine(rot_matrix((angle,0,0)),outlet,anchor-outlet)
                if goal is not None:
                    target=np.linalg.solve(par,goal);sc=np.linalg.norm(target[:3,:3],axis=0)
                    rot=Rotation.from_matrix(target[:3,:3]/sc).as_euler('xyz',degrees=True)
                    r=rot-np.array(g['rotation']);p=apply(o,target)-o
                p=p+FIT[anim['name']].get(name,(0,0,0))
                local=affine(rot_matrix(np.add(g['rotation'],r))*sc,o,p);world[name]=par@local
                for ch,value in [('rotation',r),('position',p),('scale',sc)]:
                    baked.setdefault((name,ch),[]).append(value)
        for name in {k[0] for k in baked}:
            uid=ids[name]; tr=tracks.setdefault(uid,{'name':name,'type':'bone'});tr['keyframes']=[]
            for channel,neutral in [('rotation',0.),('position',0.),('scale',1.)]:
                values=np.asarray(baked[name,channel]);
                if np.allclose(values,neutral,atol=1e-8):continue
                constant=np.allclose(values,values[0],atol=1e-8)
                for i,v in enumerate(values[:1] if constant else values):
                    tr['keyframes'].append({'channel':channel,'time':round(duration*i/32,7),'color':-1,
                        'uuid':str(uuid.uuid5(uuid.NAMESPACE_URL,f"longnu/cloth/{anim['uuid']}/{name}/{channel}/{i}")),
                        'interpolation':'linear','data_points':[{a:f'{b:.6f}' for a,b in zip('xyz',v)}]})
