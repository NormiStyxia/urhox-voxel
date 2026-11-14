"""Independent exported-mesh checks and offline previews; no engine invocation.
Run using the temporary environment described in art/nomi_voxel/README.md.
"""
import json, sys
from collections import Counter, defaultdict
from pathlib import Path
import numpy as np
from shapely.geometry import Polygon
from shapely.ops import unary_union
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'art/nomi_voxel'))
from review_mesh import read_lua, triangles, shape, sheet, world_tris
from refine import OFFSET
from PIL import Image, ImageDraw

DEST=ROOT/'art/nomi_voxel/elbow_preview'
old=read_lua(ROOT/'scripts/game/NomiVoxelData.lua')
new=read_lua(ROOT/'scripts/game/NomiVoxelDataElbow.lua')
meta=json.loads((DEST/'measurements.json').read_text())
measure=meta['measurement']
q,p,t,b=old; nq,npal,nt,nb=new
assert np.array_equal(p,npal), 'palette changed'
assert b==[row for row in nb if not row[0].startswith('forearm_')], 'old pivots changed'
for side in ('right','left'):
    assert next(row for row in nb if row[0]=='forearm_'+side)[1]=='arm_'+side
old_other=([v for v in q if not v[0].startswith('arm_')],[v for v in t if not v[0].startswith('arm_')])
new_other=([v for v in nq if not v[0].startswith(('arm_','forearm_'))],[v for v in nt if not v[0].startswith(('arm_','forearm_'))])
assert old_other==new_other,'head, hair, clothing or legs changed'

def key(b,pts,c):
    return (b,tuple(np.round(np.array(pts).ravel(),7)),c)
cap_count=Counter(key(b,p,c) for b,p,c in meta['caps'])
exterior=[];cap_export=[]
for bone,pts,c in nt:
    k=key(bone,pts,c)
    if cap_count[k]:
        cap_count[k]-=1;cap_export.append((bone,np.array(pts)-OFFSET,c))
    else: exterior.append((bone,pts,c))
assert not any(cap_count.values()), 'exported cap missing'

# Exact half-cell multiset: splits at .5 preserve every unit-face quadrant and RGB.
def cells(quads):
    out=Counter()
    for bone,d,l,u,v,w,h,c in quads:
        bone=bone.replace('forearm_','arm_')
        for x in range(round(u*2),round((u+w)*2)):
            for y in range(round(v*2),round((v+h)*2)):
                out[(bone,d,l,x,y,c)]+=1
    return out
assert cells(q)==cells(nq),'per-voxel exterior face coverage or color changed'

# Clipped triangles have different triangulation. Compare oriented coloured planar
# unions and summed area separately (union alone would hide duplicate triangles).
def planes(tris):
    groups=defaultdict(list);areas=defaultdict(float)
    for bone,pts,c in tris:
        bone=bone.replace('forearm_','arm_')
        pts=np.array(pts,float)
        normal=np.cross(pts[1]-pts[0],pts[2]-pts[0]); length=np.linalg.norm(normal)
        assert length>1e-8
        normal/=length;axis=int(np.argmax(abs(normal)))
        k=(bone,c,tuple(np.round(normal,6)),round(float(normal@pts[0]),6))
        poly=Polygon(np.delete(pts,axis,axis=1));groups[k].append(poly);areas[k]+=poly.area
    return {k:unary_union(v) for k,v in groups.items()},areas
op,oa=planes(t);ep,ea=planes(exterior)
assert op.keys()==ep.keys(),'triangle plane/color changed'
max_error=0
for k in op:
    error=op[k].symmetric_difference(ep[k]).area
    max_error=max(max_error,error)
    assert error<1e-7 and abs(oa[k]-ea[k])<1e-7, ('triangle coverage differs',k,error)

# Caps must have the correct outward normal and fill the measured contour without holes.
cap_metrics={}
for side,m in measure.items():
    contour=Polygon(np.array(m['section_vertices'])[:,[0,2]])
    for prefix,sign in [('arm_',-1),('forearm_',1)]:
        rows=[pts for bone,pts,c in cap_export if bone==prefix+side]
        assert rows
        for pts in rows:
            assert np.allclose(pts[:,1],m['cut_y'])
            assert np.cross(pts[1]-pts[0],pts[2]-pts[0])[1]*sign>0
        covered=unary_union([Polygon(pts[:,[0,2]]) for pts in rows])
        assert contour.symmetric_difference(covered).area<1e-7
        assert abs(sum(Polygon(pts[:,[0,2]]).area for pts in rows)-contour.area)<1e-7
    cap_metrics[side]={'area_authoring_units2':contour.area,'uncovered_area':0}

# Ray/solid sampling independent of the generator. Deduplicate same hit distances
# to avoid diagonal/shared-face double hits; original non-manifold wedge tails
# are retained, so this is a sampled coverage diagnostic, not a manifold proof.
def inside(points, mesh):
    mesh=np.asarray(mesh);a=mesh[:,0];e1=mesh[:,1]-a;e2=mesh[:,2]-a
    direction=np.array([.137,.219,1.]);direction/=np.linalg.norm(direction)
    h=np.cross(direction,e2);det=np.einsum('ij,ij->i',e1,h)
    valid=abs(det)>1e-9;inv=np.zeros_like(det);inv[valid]=1/det[valid]
    result=[]
    for point in points:
        s=point-a;u=np.einsum('ij,ij->i',s,h)*inv
        cross=np.cross(s,e1);v=cross@direction*inv;dist=np.einsum('ij,ij->i',e2,cross)*inv
        hits=dist[valid&(u>=-1e-8)&(v>=-1e-8)&(u+v<=1+1e-8)&(dist>1e-8)]
        result.append(len(np.unique(np.round(hits,7)))%2==1)
    return np.array(result)

def rotation(angle):
    r=np.radians(-angle);c,s=np.cos(r),np.sin(r)
    return np.array([[1,0,0],[0,c,-s],[0,s,c]])

rest_mesh=triangles(nq,nt)
bend=[]
for side,m in measure.items():
    pivot=shape('arm_'+side,m['pivot'])
    upper=np.array([shape(bone,pts) for bone,pts,_ in rest_mesh if bone=='arm_'+side])
    lower=np.array([shape(bone,pts) for bone,pts,_ in rest_mesh if bone=='forearm_'+side])
    # 0.5 authoring units = 11 mm grid, spherical neighbourhood around hinge.
    offsets=np.array([(x,y,z) for x in np.arange(-2.25,2.5,.5) for y in np.arange(-2.25,2.5,.5)
                     for z in np.arange(-2.25,2.5,.5) if x*x+y*y+z*z<2.5**2])
    probes=pivot+offsets
    base=inside(probes,upper)|inside(probes,lower)
    palm=shape('arm_'+side,[19 if side=='right' else -19,33,-.75])
    radius=np.linalg.norm(palm-pivot)
    rim=shape('arm_'+side,m['section_vertices'])
    for angle in (0,45,90,120):
        rot=rotation(angle);bent=(lower-pivot)@rot.T+pivot
        coverage=inside(probes,upper)|inside(probes,bent)
        hand=(palm-pivot)@rot.T+pivot
        assert abs(np.linalg.norm(hand-pivot)-radius)<1e-10
        assert angle==0 or hand[2]>palm[2], 'elbow bends backwards'
        rim_separation=np.linalg.norm((rim-pivot)@rot.T-(rim-pivot),axis=1)
        bend.append({'side':side,'degrees':angle,'probes':int(base.sum()),
                     'vacated_rest_volume_probes':int((base&~coverage).sum()),
                     'max_matching_rim_separation_m':float(rim_separation.max()*.022),
                     'hand_radius_error_m':float(abs(np.linalg.norm(hand-pivot)-radius)*.022),
                     'pivot_displacement_m':0})

# Same complete character, same camera, just forearm rotations. Software preview
# follows SLENDER shape/scale/lift; it does not simulate runtime lighting or PBR.
for angle in (0,45,90,120):
    mesh=[]
    for bone,pts,c in rest_mesh:
        world=shape(bone,pts)
        pv=shape(bone,next(pv for name,_,pv in nb if name==bone))
        if bone.startswith('forearm_'):
            world=(world-pv)@rotation(angle).T+pv
        else:
            sc={'head':.82,'hair_locks':.85,'hair_back':.85}.get(bone,1)
            world=(world-pv)*sc+pv
        mesh.append(((world+OFFSET+(0,6.3,0)).tolist(),npal[c]))
    sheet(mesh,[(0,0),(65,5),(90,0),(180,0)],DEST/f'bend_{angle:03}.png',scale=6)
images=[Image.open(DEST/f'bend_{a:03}.png') for a in (0,45,90,120)]
canvas=Image.new('RGB',(images[0].width, sum(im.height+25 for im in images)),(45,45,45))
draw=ImageDraw.Draw(canvas);y=0
for angle,im in zip((0,45,90,120),images):
    draw.text((12,y+5),f'Elbow {angle} degrees / offline geometry, no engine lighting',fill='white')
    canvas.paste(im,(0,y+25));y+=im.height+25
canvas.save(DEST/'contact_sheet.png')
report={'static_external_surface_equal':True,'non_arm_rows_exact':True,'palette_exact':True,
        'half_cell_faces':sum(cells(q).values()),'original_tris':len(t),
        'max_triangle_symmetric_difference':max_error,'cap_coverage':cap_metrics,'bend_sampling':bend,
        'limitation':'Capped rigid cuts remain in contact at hinge, but form an outside bend notch. Vacated probes and rim separation are diagnostics, not a no-gap pass; engine/Web rendering unverified.'}
(DEST/'checks.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
