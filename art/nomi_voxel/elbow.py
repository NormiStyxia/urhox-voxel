"""Opt-in rigid elbow stage, AFTER approved-head / garment colour finishing.
Never reads an exported mesh as generation input and never edits the legacy output.
All positions below are authoring units; origin offsets are applied only at export.
"""
import json
from collections import defaultdict
import numpy as np
from refine import OFFSET, quad_points
from review_mesh import triangles
from voxelize import HERE, ROOT, export_lua

EPS = 1e-8


def clip(points, y, upper):
    """Sutherland-Hodgman; preserves winding and clips crossing triangles too."""
    result = []
    for a, b in zip(points, np.roll(points, -1, axis=0)):
        da, db = (a[1]-y), (b[1]-y)
        ina, inb = (da >= -EPS, db >= -EPS) if upper else (da <= EPS, db <= EPS)
        if ina:
            result.append(a)
        if ina != inb:
            p = a + (b-a)*da/(da-db)
            p[1] = y
            result.append(p)
    unique = []
    for p in result:
        if not unique or np.linalg.norm(p-unique[-1]) > EPS:
            unique.append(p)
    if len(unique)>1 and np.linalg.norm(unique[0]-unique[-1])<EPS:
        unique.pop()
    return np.asarray(unique)


def section(mesh, y):
    edges = []
    for p, c in mesh:
        hits = []
        for a, b in zip(p, np.roll(p, -1, axis=0)):
            if min(a[1], b[1]) < y < max(a[1], b[1]):
                hits.append(a+(b-a)*(y-a[1])/(b[1]-a[1]))
        if len(hits)==2:
            edges.append((hits[0], hits[1], c))
    return edges


def loops_from_edges(edges):
    key = lambda p: tuple(np.round(p, 8))
    graph = defaultdict(set)
    for a,b,_ in edges:
        a,b=key(a),key(b)
        graph[a].add(b); graph[b].add(a)
    # The approved wedge mesh has zero-area dangling face extensions at corners.
    # They do not bound a volume. Keep those exterior faces unchanged, but do not
    # turn a dangling line into an invented cap surface.
    leaves=[p for p,neighbors in graph.items() if len(neighbors)<2]
    while leaves:
        p=leaves.pop()
        if p not in graph: continue
        for neighbor in graph.pop(p):
            graph[neighbor].discard(p)
            if len(graph[neighbor])<2: leaves.append(neighbor)
    assert graph and all(len(v)==2 for v in graph.values()), 'elbow section is not closed'
    loops=[]
    pending=set(graph)
    while pending:
        first=min(pending); loop=[first]; prev=None; current=first
        while True:
            nxt=next(p for p in sorted(graph[current]) if p!=prev)
            if nxt==first: break
            assert nxt in pending, 'self-intersecting section'
            loop.append(nxt); prev,current=current,nxt
        pending.difference_update(loop)
        loops.append(np.asarray(loop))
    # Current sleeve is one solid cross-section. Fail instead of silently filling holes.
    assert len(loops)==1, 'multiple contours need explicit hole-aware cap support'
    return loops[0]


def cap_triangles(loop):
    """Ear clipping in XZ, keeping all boundary corners; rejects invalid contours."""
    def cross(a,b,c):
        return (b[0]-a[0])*(c[2]-a[2])-(b[2]-a[2])*(c[0]-a[0])
    pts=list(loop)
    # Remove collinear segmentation produced by adjacent input triangles.
    changed=True
    while changed and len(pts)>3:
        changed=False
        for i in range(len(pts)):
            if abs(cross(pts[i-1],pts[i],pts[(i+1)%len(pts)]))<EPS:
                pts.pop(i); changed=True; break
    area=sum(a[0]*b[2]-b[0]*a[2] for a,b in zip(pts,pts[1:]+pts[:1]))
    if area<0: pts.reverse()
    out=[]
    while len(pts)>3:
        for i,b in enumerate(pts):
            a,c=pts[i-1],pts[(i+1)%len(pts)]
            if cross(a,b,c)<=EPS: continue
            others=[p for j,p in enumerate(pts) if j not in ((i-1)%len(pts),i,(i+1)%len(pts))]
            if any(min(cross(a,b,p),cross(b,c,p),cross(c,a,p))>=-EPS for p in others): continue
            out.append(np.array([a,b,c]));pts.pop(i);break
        else: raise AssertionError('cannot triangulate cap')
    out.append(np.array(pts))
    # XZ counterclockwise gives -Y: upper arm bottom cap.
    return out


def measure(q,pal,t):
    mesh=triangles(q,t); report={}
    for side in ('right','left'):
        name='arm_'+side
        arm=[(p,c) for b,p,c in mesh if b==name]
        allp=np.concatenate([p for p,_ in arm])
        skin=np.concatenate([p for p,c in arm if pal[c][0]>150 and pal[c][0]>pal[c][2]*1.12 and p[:,1].max()<=36])
        # Measured cuff upper edge and sleeve top, NOT the shoulder-pivot/hand midpoint.
        cuff=float(skin[:,1].max()); top=float(allp[:,1].max())
        # Put cut inside a voxel row to avoid coplanar face ownership ambiguity.
        # Tie goes toward the hand; preserves every old face at the same position.
        y=float(np.ceil((cuff+top)/2)-.5)
        edges=section(arm,y); loop=loops_from_edges(edges)
        lo,hi=loop.min(0),loop.max(0)
        pivot=(lo+hi)/2
        report[side]={'cuff_skin_top_y':cuff,'sleeve_top_y':top,'cut_y':y,
                      'skin_bounds':[skin.min(0).tolist(),skin.max(0).tolist()],
                      'arm_bounds':[allp.min(0).tolist(),allp.max(0).tolist()],
                      'section_bounds':[lo.tolist(),hi.tolist()], 'pivot':pivot.tolist(),
                      'section_vertices':loop.tolist()}
    return report


def split(q,pal,t,bones):
    info=measure(q,pal,t); qs=[];ts=[];caps=[]; newbones=[]
    for bone in bones:
        newbones.append(bone)
        if bone[0].startswith('arm_'):
            side=bone[0][4:]
            newbones.append(('forearm_'+side,bone[0],info[side]['pivot']))
    for row in q:
        b,d,layer,u,v,w,h,c=row
        if not b.startswith('arm_'):
            qs.append(row);continue
        y=info[b[4:]]['cut_y']; lower='forearm_'+b[4:]
        if d in ('py','ny'):
            plane=layer+(d=='py')
            qs.append(((b if plane>y else lower),)+tuple(row[1:]));continue
        for owner,start,end in ((lower,v,min(v+h,y)),(b,max(v,y),v+h)):
            if end-start>EPS:
                qs.append((owner,d,layer,u,start,w,end-start,c))
    for b,pts,c in t:
        if not b.startswith('arm_'):
            ts.append((b,pts,c));continue
        p=np.asarray(pts)-OFFSET;y=info[b[4:]]['cut_y']
        for upper,owner in ((True,b),(False,'forearm_'+b[4:])):
            poly=clip(p,y,upper)
            for i in range(1,len(poly)-1):
                tri=poly[[0,i,i+1]]
                if np.linalg.norm(np.cross(tri[1]-tri[0],tri[2]-tri[0]))>EPS:
                    ts.append((owner,(tri+OFFSET).tolist(),c))
    for side,m in info.items():
        b='arm_'+side
        # Cap uses an existing sleeve colour; original palette and exterior RGB stay identical.
        edges=section([(p,c) for name,p,c in triangles(q,t) if name==b],m['cut_y'])
        lengths=defaultdict(float)
        for a,z,c in edges: lengths[c]+=float(np.linalg.norm(z-a))
        color=max(sorted(lengths),key=lengths.get)
        m['cap_color_index']=int(color)
        for tri in cap_triangles(np.array(m['section_vertices'])):
            for owner,p in ((b,tri),('forearm_'+side,tri[::-1])):
                caps.append((owner,(p+OFFSET).tolist(),color))
    ts.extend(caps)
    return qs,pal,ts,newbones,info,caps


def generate(q,pal,t,bones):
    qs,pal,ts,bs,info,caps=split(q,pal,t,bones)
    out=export_lua(qs,pal,ts,bs,ROOT/'scripts/game/NomiVoxelDataElbow.lua')
    dest=HERE/'elbow_preview';dest.mkdir(exist_ok=True)
    (dest/'measurements.json').write_text(json.dumps({'measurement':info,'caps':caps},indent=2)+'\n')
    print('wrote',out)
    print(json.dumps(info,indent=2))
