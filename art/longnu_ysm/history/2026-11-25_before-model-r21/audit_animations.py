"""Compare exported and unmodified Nomi tracks on the same Longnu mesh (neutral gaze)."""
import json
import re
from collections import defaultdict

import numpy as np

from build_longnu import OUT, follow_chains, nomi_model, rot_matrix


def rig(model):
    groups = {g['uuid']:g for g in model['groups']}
    cubes = {c['uuid']:c for c in model['elements']}
    nodes, owners, centers, edges, parts, labels = [], [], [], [], defaultdict(list), []

    def visit(node, parent, ancestors):
        g = groups[node['uuid']]
        index = len(nodes)
        nodes.append((parent, g))
        path = ancestors + [g['name']]
        for child in node['children']:
            if isinstance(child, dict):
                visit(child, index, path)
                continue
            c = cubes[child]
            lo, hi, origin = map(np.asarray,(c['from'],c['to'],c['origin']))
            rotation = rot_matrix(c.get('rotation',(0,0,0)))
            i = len(owners)
            owners.append(index)
            labels.append(c['name'])
            centers.append(origin + rotation @ ((hi+lo)/2-origin))
            edges.append(rotation * ((hi-lo)/2+c.get('inflate',0)))
            for family, pattern in [('shell','CoatShell'),('coat','NomiOvercoat'),('sleeve','(?:Right|Left)(?:Fore)?ArmCoat'),
                    ('cape','NomiHood'),('leg','(?:Right|Left)(?:LowerLeg|Leg|Foot)'),('skirt','NomiPleat.*|Skirt'),
                    ('bow','WaistBow'),('tail','Tail'),('pony','(?:Right|Left)SideLock'),('lock','corner_h[12]'),('face','Face')]:
                if family == 'shell' and g['name'] != 'CoatShell':
                    continue
                if family == 'tail' and c['name'].startswith('裙内尾根'):
                    continue
                if any(re.fullmatch(pattern,n) for n in path):
                    parts[family].append(i)
    for root in model['outliner']:
        visit(root,-1,[])
    return nodes, np.array(owners), np.array(centers), np.array(edges), parts, labels


def channels(anim):
    curves = {}
    for uid, tr in anim.get('animators',{}).items():
        if uid == 'effects': continue
        assert not tr.get('rotation_global') and not tr.get('quaternion_interpolation')
        by_channel = defaultdict(list)
        for k in tr.get('keyframes',[]):
            assert k['interpolation']=='linear' and len(k['data_points'])==1
            point = k['data_points'][0]
            value = [0. if point[a]=='0.4*ysm.head_yaw' else float(point[a]) for a in 'xyz']
            by_channel[k['channel']].append((k['time'],value))
        for ch, keys in by_channel.items():
            times, values = zip(*sorted(keys,key=lambda item:item[0]))
            curves[(uid,ch)] = (times,np.array(values).T)
    return curves


def world_transforms(mesh, curves, time):
    nodes, owners, centers, edges, _, _ = mesh
    world, offset = [], []
    for parent, g in nodes:
        def sample(ch, default):
            curve = curves.get((g['uuid'],ch))
            if curve is None: return default
            return np.array([np.interp(time,curve[0],axis) for axis in curve[1]])
        scale = np.asarray(sample('scale',[1,1,1]))
        linear = rot_matrix(np.add(g['rotation'],sample('rotation',0))) * np.where(scale==0,1e-5,scale)
        pivot = np.array(g['origin'])
        translation = pivot-linear@pivot+sample('position',0)
        if parent >= 0:
            translation = world[parent]@translation+offset[parent]
            linear = world[parent]@linear
        world.append(linear)
        offset.append(translation)
    assert np.isfinite(world).all() and np.isfinite(offset).all()
    return np.asarray(world),np.asarray(offset)


def world_boxes(mesh, curves, time):
    _,owners,centers,edges,_,_ = mesh
    world,offset=world_transforms(mesh,curves,time)
    by_cube = world[owners]
    return np.einsum('nij,nj->ni',by_cube,centers)+np.asarray(offset)[owners], by_cube@edges


def collisions(centers, edges, pairs, margin=0.):
    # Half-edge vectors remain valid under inherited nonuniform scale (including shear).
    extent = abs(edges).sum(axis=2)
    normals = np.cross(np.roll(edges,-1,axis=2),np.roll(edges,-2,axis=2),axisa=1,axisb=1,axisc=1)
    found = {}
    for label, (i,j) in pairs.items():
        delta = centers[i]-centers[j]
        keep = np.all(abs(delta)<extent[i]+extent[j]+margin,axis=1)
        if not np.any(keep): continue
        a,b = i[keep],j[keep]
        e,f = edges[a].transpose(0,2,1),edges[b].transpose(0,2,1)
        cross = np.cross(e[:,:,None,:],f[:,None,:,:]).reshape(-1,9,3)
        axes = np.concatenate((normals[a].transpose(0,2,1),normals[b].transpose(0,2,1),cross),axis=1)
        lengths = np.linalg.norm(axes,axis=2)
        projection = np.abs(axes@edges[a]).sum(axis=2)+np.abs(axes@edges[b]).sum(axis=2)
        penetration = projection+margin*lengths-abs(np.einsum('nij,nj->ni',axes,delta[keep]))
        depths = np.min(np.divide(penetration,lengths,out=np.full_like(lengths,np.inf),where=lengths>1e-12),axis=1)
        positive = depths>1e-5
        if positive.any():
            k = np.argmax(depths)
            found[label] = (int(positive.sum()),float(depths[k]),int(a[k]),int(b[k]))
    return found


def verify_tracks(model, source):
    exported = model['animations']
    ids = {g['name']:g['uuid'] for g in model['groups']}
    valid = set(ids.values()) | {'effects'}
    assert len(source)==91 and len(exported)==92
    assert exported[0]['name']=='longnu_reference_stance'
    assert all(a.get('animators',{}).keys() <= valid for a in exported)
    assert {g['uuid'] for g in nomi_model()['groups']} <= valid
    core = {'idle','walk','run','jump','sneak','sit'}
    secondary = {ids[name] for _,chain,_ in follow_chains() for name in chain}
    original_ids, added_ids = [], []
    mirrored = 0
    for src,dst in zip(source,exported[1:]):
        assert {k:v for k,v in src.items() if k!='animators'} == {k:v for k,v in dst.items() if k!='animators'}
        orig,full = src.get('animators',{}),dst.get('animators',{})
        from cloth_motion import driven
        for uid,track in orig.items():
            assert uid in full
            if src['name'] in core and uid!='effects' and driven(track['name']):
                assert {k:v for k,v in full[uid].items() if k!='keyframes'} == {k:v for k,v in track.items() if k!='keyframes'}
            else:
                assert full[uid]==track
        added = full.keys()-orig.keys()
        if src['name'] in core:
            assert secondary <= added
        original_ids.extend(k['uuid'] for t in orig.values() for k in t.get('keyframes',[]))
        added_ids.extend(k['uuid'] for uid in added for k in full[uid].get('keyframes',[]))
        right = [k for k in orig.get(ids['corner_h1'],{}).get('keyframes',[]) if k['channel']=='rotation']
        left = full.get(ids['corner_h2'],{}).get('keyframes',[])
        assert len(right)==len(left)
        for r,l in zip(right,left):
            assert (r['time'],r['interpolation'])==(l['time'],l['interpolation'])
            for u,v in zip(r['data_points'],l['data_points']):
                assert all(float(u[a])==sign*float(v[a]) for a,sign in zip('xyz',(1,-1,-1)))
        mirrored += len(left)
    assert len(set(added_ids))==len(added_ids) and not set(added_ids).intersection(original_ids)
    print('source frames',len(original_ids),'mirrored',mirrored,'new frames',len(added_ids))


def main():
    model = json.loads((OUT/'longnu.bbmodel').read_text())
    source = nomi_model()['animations']
    verify_tracks(model,source)
    mesh = rig(model)
    parts,labels = mesh[-2:]
    pairs = {}
    for first, others in [('coat','leg skirt bow tail pony lock'),('shell','leg skirt bow pony lock'),
                          ('cape','pony lock'),('sleeve','leg skirt bow lock pony'),('bow','leg skirt'),
                          ('tail','leg skirt'),('lock','face')]:
        for second in others.split():
            grid = np.meshgrid(parts[first],parts[second],indexing='ij')
            pairs[first+'/'+second] = tuple(idx.ravel() for idx in grid)
    print('rest',collisions(*world_boxes(mesh,{},0),pairs))
    for a,b in zip(source,model['animations'][1:]):
        if a['name'] not in ('idle','walk','run','jump','sneak','sit'): continue
        duration = a['length'] or max(k['time'] for tr in a['animators'].values() for k in tr.get('keyframes',[]))
        for version,anim in [('source',a),('export',b)]:
            summary = defaultdict(list)
            curves = channels(anim)
            for t in np.linspace(0,duration,13):
                for pair,(count,depth,i,j) in collisions(*world_boxes(mesh,curves,t),pairs).items():
                    summary[pair].append((depth,round(t,4),labels[i],labels[j],count))
            print(a['name'],version,json.dumps({k:[len(v),*max(v)] for k,v in summary.items()},ensure_ascii=False),flush=True)


if __name__=='__main__':
    main()
