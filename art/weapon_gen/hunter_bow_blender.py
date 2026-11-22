"""Build the common Hunter Bow from its three-view. Run with Blender -b -P this_file.

Blender -b --factory-startup -P art/weapon_gen/hunter_bow_blender.py rebuilds
and renders the native scene. Standalone Python accepts measure, export, topology,
lua, compare, or raster. Raster is a separate CPU proof of the packed asset.
"""
import json
import math
import sys
from collections import Counter
from pathlib import Path

import numpy as np
try:
    import bpy
except ModuleNotFoundError:
    bpy = None
    from PIL import Image
else:
    import OpenImageIO as oiio
    from mathutils import Vector

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = HERE / 'out/hunter_bow'
PACKED = ROOT / 'assets/model/forge-blades/HunterBow.mesh.json'
INTERMEDIATE = OUT / 'hunter_bow_game.json'
REFERENCE = ROOT / 'art/weapons_2d/rarity/hunter_bow_1_threeview_v1.png'
# Load only the existing format helpers, without creating a __pycache__ in the art tree.
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE))
from thornbow_export import orient

# Pixel coordinates use the left elevation's native scale. Each column is independently
# registered by its physical height and the grip's midpoint. No horizontal stretch.
CROPS = {'left': (580, 1060), 'front': (1136, 1616), 'right': (1780, 2260)}
SECTION = [(-1, 0), (-.74, -.74), (-.27, -.982), (-.15, -1), (.70, -.77),
           (1, 0), (.70, .77), (-.15, 1), (-.27, .982), (-.74, .74)]
GRIP_Y = 769
GRIP_X = 772.5
TOP, BASE = 74, 1424
SPAN = BASE - TOP


def read_image(path):
    if bpy is None:
        return np.asarray(Image.open(path))
    src = oiio.ImageInput.open(str(path))
    if src is None:
        raise OSError(f'Could not read {path}')
    try:
        return src.read_image(format=oiio.UINT8)
    finally:
        src.close()


def outline(row):
    # Bridge light reflections inside a panel. A separated bowstring stays independent.
    pixels = np.flatnonzero(row)
    groups = np.split(pixels, np.flatnonzero(np.diff(pixels) > 9) + 1)
    return [(g[0], g[-1] + 1) for g in groups if len(g)]


def measure():
    rgb = read_image(REFERENCE).astype(float)
    fg = (rgb.mean(2) < 203) | (np.ptp(rgb, axis=2) > 18)
    views = {}
    for name, (x0, x1) in CROPS.items():
        mask = fg[:, x0:x1].copy()
        rows = np.flatnonzero(mask.any(axis=1))
        top, bottom = int(rows[0]), int(rows[-1] + 1)
        span = bottom - top
        edges = np.empty((len(rows), 2))
        string_rows = []
        for i, y in enumerate(rows):
            groups = outline(mask[y])
            # For the measurement mask fill enclosed light pixels only BETWEEN outline edges.
            for a, b in groups:
                mask[y, a:b] = True
            a, b = max(groups, key=lambda ab: ab[1]-ab[0])
            edges[i] = [a + x0, b + x0]
            if name != 'front' and .2 < (y-top)/span < .8:
                wire = groups[-1] if name == 'left' else groups[0]
                if wire[1] - wire[0] < 9:
                    string_rows.append((y, x0 + sum(wire)/2, wire[1]-wire[0]))
        grip = float(edges[round((GRIP_Y-TOP)/SPAN*span)].mean())
        views[name] = dict(rows=rows, edges=edges, top=top, span=span, grip=grip, mask=mask)
        if string_rows:
            y, x, width = np.array(string_rows).T
            views[name]['wire'] = np.polyfit(y, x, 1)
            views[name]['wire_width'] = float(np.median(width))
        print(f'{name}: sheet bounds y=[{top},{bottom}), grip x={grip:.2f}, height={span}px')
    for y in (75, 155, 250, 400, 550, 625, 769, 865, 975, 1150, 1300, 1422):
        print('landmark', y, {name: tuple(np.round(edge(v,y), 2)) for name,v in views.items()})
    return views


def edge(v, y):
    row = v['top'] + (y-TOP)/SPAN * v['span']
    return np.array([np.interp(row, v['rows']+.5, side) for side in v['edges'].T])


def side_range(y):
    ends = []
    for name in ('left','right'):
        v = views[name]
        a = (edge(v,y)-v['grip']) * SPAN / v['span']
        ends.append(a if name=='left' else -a[::-1])
    return np.mean(ends, axis=0) + GRIP_X


def front_range(y):
    v = views['front']
    # The front camera looks along +X, so image right is Blender -Y.
    return -(edge(v,y)-v['grip'])[::-1] * SPAN/v['span']


def point(x, depth, y):
    return ((x-GRIP_X)/SPAN, depth/SPAN, (GRIP_Y-y)/SPAN)


# Weights are per surface. Alpha follows the ribbon around each cross-section, so
# a single longitudinal grain coordinate bends with the recurve and survives export.
# name: (RGB weights, submask, Blender display sRGB, roughness)
SPEC = {'wood': ((1,0,0),0,'624438',.67), 'bone': ((0,1,0),0,'D5B69A',.59),
        'leather': ((0,0,0),0,'503832',.82), 'flax': ((0,0,1),1,'998578',.88)}
NAMES = list(SPEC)
TURN_COUNT = 5
WRAP_START, WRAP_END = 682, 855
UPPER = (220,242,265,290,318,347,370,393,415,437,460,484,506,529,535,552,565,580,600,608)
LOWER = (930,949,968,980,998,1018,1040,1065,1090,1112,1135,1160,1185,1210,1233,1255,1273)


def linear(value):
    x = value/255
    return x/12.92 if x<.04045 else ((x+.055)/1.055)**2.4


def materials():
    """Four procedural dielectric materials. No Image data is created or sampled."""
    result=[]
    for name,(_,_,hexcolor,rough) in SPEC.items():
        mat = bpy.data.materials.new('Hunter / '+name)
        color = np.array([linear(c) for c in bytes.fromhex(hexcolor)])
        mat.diffuse_color=(*color,1)
        mat.use_nodes=True
        tree=mat.node_tree
        nodes=tree.nodes
        def node(kind,label,x,y):
            n=nodes.new(kind); n.label=label; n.location=(x,y); return n
        def connect(value,socket):
            if isinstance(value,(float,int)):
                socket.default_value=value
            else:
                tree.links.new(value,socket)
        def scalar(op,a,b,label,x,y):
            n=node('ShaderNodeMath',label,x,y); n.operation=op
            connect(a,n.inputs[0]); connect(b,n.inputs[1]); return n.outputs[0]
        attr=node('ShaderNodeAttribute','Swept grain coordinate',-1100,340)
        attr.attribute_name='grain'
        uv=node('ShaderNodeUVMap','Physical height',-1100,100);uv.uv_map='SubmaskHeight'
        split=node('ShaderNodeSeparateXYZ','Height along bow',-900,100);connect(uv.outputs[0],split.inputs[0])
        rates={'wood':(9.5,4.5,20,.065),'bone':(7,8,16,.028),'leather':(21,102,38,.042),'flax':(7,325,9,.018)}
        lateral,axial,lamina,depth=rates[name]
        width=scalar('MULTIPLY',attr.outputs['Fac'],lateral,'Across fibre',-860,520)
        length=scalar('MULTIPLY',split.outputs['Y'],axial,'Along fibre',-720,180)
        coords=node('ShaderNodeCombineXYZ','Material coordinates',-500,440)
        connect(width,coords.inputs[0]);connect(length,coords.inputs[1])
        noise=node('ShaderNodeTexNoise',{'wood':'Long fibre runout','bone':'Ivory striae','leather':'Hide pores','flax':'Spun fibre'}[name],-280,550)
        connect(coords.outputs[0],noise.inputs['Vector']);noise.inputs['Scale'].default_value=1.5
        noise.inputs['Detail'].default_value=3.0;noise.inputs['Roughness'].default_value=.51
        noise.inputs['Distortion'].default_value=.18 if name=='wood' else .12
        phase=scalar('MULTIPLY',attr.outputs['Fac'],lamina,'Growth layers',-500,-50)
        flow=scalar('MULTIPLY',noise.outputs['Fac'],3.1,'Grain drift',-65,300)
        if name=='flax':
            phase=scalar('ADD',phase,length,'Cord twist',-270,-40)
        phase=scalar('ADD',phase,flow,'Follow the sweep',125,120)
        wave=scalar('SINE',phase,0,'Undulating layers',315,120)
        wave=scalar('MULTIPLY',wave,.19,'Veneer contrast',495,120)
        field=scalar('MULTIPLY',noise.outputs['Fac'],.64,'Fibre detail',335,440)
        field=scalar('ADD',field,wave,'Pores and layers',690,370)
        field=scalar('ADD',field,.17,'Pigment',865,370)
        ramp=node('ShaderNodeValToRGB','Pigment through the material',1055,430)
        connect(field,ramp.inputs[0]);ramp.color_ramp.interpolation='EASE'
        for e,k in zip(ramp.color_ramp.elements,{'wood':(.46,1.45),'bone':(.76,1.11),'leather':(.59,1.16),'flax':(.63,1.22)}[name]):
            e.color=(*np.minimum(1,color*k),1)
        bump=node('ShaderNodeBump','Micro-relief',1055,0)
        bump.inputs['Distance'].default_value=depth*.001;bump.inputs['Strength'].default_value=.29
        connect(field,bump.inputs['Height'])
        bsdf=nodes['Principled BSDF'];bsdf.location=(1320,400)
        connect(ramp.outputs[0],bsdf.inputs['Base Color']);connect(bump.outputs[0],bsdf.inputs['Normal'])
        bsdf.inputs['Roughness'].default_value=rough
        bsdf.inputs['IOR'].default_value={'bone':1.55,'wood':1.47,'leather':1.43,'flax':1.46}[name]
        bsdf.inputs['Specular IOR Level'].default_value=.32 if name=='bone' else .21
        bsdf.inputs['Metallic'].default_value=0
        nodes['Material Output'].location=(1640,400)
        result.append(mat)
    return result


class Loft:
    def __init__(self):
        self.verts, self.faces, self.ids, self.last, self.grain = [], [], [], [], []

    def face(self, indices, material):
        tris = [indices] if len(indices)==3 else [indices[:3], (indices[0],indices[2],indices[3])]
        for tri in tris:
            self.faces.append(tri)
            self.ids.append(NAMES.index(material))

    def ring(self, coords, material):
        # Stations go from top to bottom. Caps terminate in a single vertex.
        ring = list(range(len(self.verts),len(self.verts)+len(coords)))
        self.verts.extend(coords)
        if len(coords)==len(SECTION):self.grain.extend((u+1)/2 for u,v in SECTION)
        else:self.grain.extend(i/max(1,len(coords)-1) for i in range(len(coords)))
        if self.last:
            count = max(len(self.last),len(ring))
            for k in range(count):
                j = (k+1)%count
                if len(self.last)==1:
                    face = (self.last[0],ring[k],ring[j])
                elif len(ring)==1:
                    face = (self.last[j],self.last[k],ring[0])
                else:
                    face = (self.last[j],self.last[k],ring[k],ring[j])
                self.face(face,material[k] if isinstance(material, list) else material)
        self.last = ring

    def object(self,name):
        self.name = name
        self.normals = corner_normals(self.verts,self.faces,self.ids)
        if bpy is None:
            return self
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.verts, [], self.faces)
        mesh.update()
        for material in mats:
            mesh.materials.append(material)
        for face, index in zip(mesh.polygons,self.ids):
            face.material_index = index
            face.use_smooth = True
        mesh.normals_split_custom_set(self.normals.reshape(-1,3).tolist())
        attr=mesh.attributes.new('grain','FLOAT','POINT')
        for i,val in enumerate(self.grain):attr.data[i].value=val
        uv=mesh.uv_layers.new(name='SubmaskHeight')
        for face in mesh.polygons:
            submask=SPEC[NAMES[face.material_index]][1]
            for loop in face.loop_indices:
                vi=mesh.loops[loop].vertex_index
                uv.data[loop].uv=(submask,self.verts[vi][2]+(BASE-GRIP_Y)/SPAN)
        ob = bpy.data.objects.new(name,mesh)
        bpy.context.collection.objects.link(ob)
        return self


def section(y, tilt=0, inset=1, shape=SECTION):
    coords = []
    for u,v in shape:
        if 686 < y < 855:
            row = y + tilt*(u*.72+v*.62)
        else:
            row = y + tilt*u
        a,b = side_range(row)
        l,r = front_range(row)
        coords.append(point((a+b)/2 + u*(b-a)/2*inset, (r+l)/2 + v*(r-l)/2*inset, row))
    return coords


def cap_stations(bottom=False):
    # These horn ferules terminate in two lips. Their side and spine seams occur at
    # different heights; a horizontal cut would erase the fork against the bowstring.
    if bottom:
        apex, mid1, mid2, ridge, direction = BASE, 1405, 1372, 1327, -1
    else:
        apex, mid1, mid2, ridge, direction = TOP, 97, 124, 181, 1
    cap = [([point(side_range(apex).mean(),0,apex)],'bone')]
    for y in sorted({mid1,mid2,(mid1+mid2)/2, (1350 if bottom else 148)}, reverse=bottom):
        cap.append((section(y),'bone'))
    for advance,scale,mat in [(0,1,'bone'),(4,.97,'bone')]:
        ring = []
        for u,v in SECTION:
            y = ridge+direction*(advance+23*(2*abs(u)**1.2-1))
            # Sample the common silhouette at this vertex's actual height. This keeps
            # the lip outside the wood, even where the limb bends sharply into the cap.
            a,b = side_range(y)
            l,r = front_range(y)
            # Keep a projecting seat for the cord where the outline forks.
            horn = 29 * max(0,u)**2 if not bottom else 0
            ring.append(point((a+b)/2+u*(b-a)/2*scale+horn,(l+r)/2+v*(r-l)/2*scale,y))
        cap.append((ring,mat))
    return cap


def winding(loft):
    # Model the strip and the exposed mandrel as a sewn, continuous outer skin.
    # Each circumferential edge advances one full pitch per revolution. Connecting
    # the last column to the first column one turn later gives an actual helical
    # crest, beveled edges and an exposed leather bed, all in one manifold shell.
    sides=len(SECTION)
    start=list(loft.last)
    bands=[(0,.951),(.12,.951),(.20,1.024),(.66,1.026),(.80,.986),(.88,.951)]
    pitch=(WRAP_END-WRAP_START)/(TURN_COUNT+1)
    strips=[]
    for turn in range(TURN_COUNT):
        for fraction,radius in bands:
            row=[]
            for j,(u,v) in enumerate(SECTION):
                phase=j/sides
                # Bowed lap seams: a cut leather edge dips over the broad face,
                # then climbs around the back. Periodic offsets close at the stitch.
                wave=math.sin(math.tau*phase+.65*turn)
                y=WRAP_START+pitch*(turn+fraction+phase)+2.4*wave
                roll=radius + .012*wave if .16<fraction<.70 else radius
                row.append(len(loft.verts))
                loft.verts.append(section(y,inset=roll,shape=[(u,v)])[0])
                loft.grain.append(.15+.72*fraction+.05*wave)
            strips.append(row)
    # At the two tuck ends the strip merges with the grip under the binding collars.
    end=[len(loft.verts)+j for j in range(sides)]
    loft.verts.extend(section(WRAP_END+1));loft.grain.extend(j/sides for j in range(sides))
    for j in range(sides):
        k=(j+1)%sides
        left=[start[j]]+[row[j] for row in strips]+[end[j]]
        right=[start[k]]+[row[k] for row in strips]+[end[k]]
        if k:
            for a,b,c,d in zip(left,left[1:],right,right[1:]):loft.face((c,a,b,d),'leather')
        else:
            # The slit of the unrolled cylinder joins the next turn, with triangular
            # fans closing the partial revolution above and below the wrap.
            n=len(bands)
            loft.face((right[0],left[0],right[1]),'leather')
            for h in range(n-1):loft.face((right[h+1],left[0],right[h+2]),'leather')
            for h in range(len(strips)-n+1):
                loft.face((right[n+h],left[h],left[h+1],right[n+h+1]),'leather')
            for h in range(len(strips)-n+1,len(left)-1):loft.face((right[-1],left[h],left[h+1]),'leather')
    loft.last=end


def swept_limb(loft, landmarks):
    """Nonuniform Catmull–Rom through both measured profiles, in metres.

    The four traces are section centre (side/depth), side radius and spine radius.
    Heights stay monotone through a recurve. Measuring the section in the horizontal
    datum plane avoids inflating projected thickness at the very steep outer elbows.
    Each measured span is sampled by arc length without rounding off its landmarks.
    """
    height = np.asarray(landmarks, dtype=float)
    trace = []
    for y in height:
        a,b = side_range(y)
        l,r = front_range(y)
        trace.append([(a+b)/2, (l+r)/2, (b-a)/2, (r-l)/2])
    trace = np.asarray(trace)
    tangent = np.gradient(trace, height, axis=0, edge_order=2)
    count = 0
    for i, span in enumerate(np.diff(height)):
        def cross_section(t):
            t2,t3 = t*t,t*t*t
            return ((2*t3-3*t2+1)*trace[i] + (t3-2*t2+t)*span*tangent[i]
                    + (-2*t3+3*t2)*trace[i+1] + (t3-t2)*span*tangent[i+1])
        t = np.linspace(0,1,12)
        centres = np.array([cross_section(u)[:2] for u in t])
        distances = np.r_[0,np.cumsum(np.sqrt(np.sum(np.diff(centres,axis=0)**2,axis=1)+(span*np.diff(t))**2))]
        subdivisions = max(1,math.ceil(distances[-1]/22))
        for arc in np.linspace(0,distances[-1],subdivisions+1)[0 if i==0 else 1:]:
            u = np.interp(arc,distances,t)
            row = height[i]+span*u
            cx,cy,rx,ry = cross_section(u)
            loft.ring([point(cx+sx*rx,cy+sy*ry,row) for sx,sy in SECTION],'wood')
            count += 1
    print('SPLINE',len(landmarks),'landmarks ->',count,'stations;',len(SECTION),'section edges')


def corner_normals(vertices, faces, materials):
    """Angle-weight each corner in its own material and bevel smoothing fan."""
    positions = np.asarray(vertices)[faces]
    cross = np.cross(positions[:,1]-positions[:,0],positions[:,2]-positions[:,0])
    unit = cross/np.linalg.norm(cross,axis=1)[:,None]
    neighbors = [[] for _ in vertices]
    for f,ids in enumerate(faces):
        for c,v in enumerate(ids):
            a=positions[f,(c+1)%3]-positions[f,c]
            b=positions[f,(c+2)%3]-positions[f,c]
            weight=math.atan2(np.linalg.norm(np.cross(a,b)),np.dot(a,b))
            neighbors[v].append((f,weight))
    result=np.empty((len(faces),3,3))
    # The cut horn keeps planar highlight breaks. The leather and wood soften
    # around each bevel, preserving the shoulder of the leather lap and nock.
    angles={'wood':48,'leather':40,'bone':17,'flax':58}
    for f,ids in enumerate(faces):
        threshold=math.cos(math.radians(angles[NAMES[materials[f]]]))
        for c,v in enumerate(ids):
            n=sum(weight*unit[j] for j,weight in neighbors[v]
                  if materials[j]==materials[f] and unit[j]@unit[f]>=threshold)
            result[f,c]=n/np.linalg.norm(n)
    return result


def bow_body():
    loft=Loft()
    for coords,mat in cap_stations():loft.ring(coords,mat)
    swept_limb(loft, UPPER)
    for y,slope,mat in [(622,-9,'wood'),(633,-16,'bone'),(646,-18,'bone'),(652,-16,'bone'),(668,-9,'leather'),(678,-2,'leather')]:
        loft.ring(section(y,slope),mat)
    winding(loft)
    for y,slope,mat in [(864,6,'leather'),(875,13,'leather'),(880,15,'bone'),(892,16,'bone'),(900,14,'bone'),(916,8,'wood')]:
        loft.ring(section(y,slope),mat)
    swept_limb(loft, LOWER)
    caps=cap_stations(True)
    for i in range(len(caps)-1,-1,-1):loft.ring(caps[i][0],'wood' if i==len(caps)-1 else caps[i+1][1])
    return loft.object('Body')


def flax():
    loft = Loft()
    # Fit both independently measured string lines. Endpoints enter the inner nocks.
    for y in (201,1314):
        centres, widths = [],[]
        for name,sign in [('left',1),('right',-1)]:
            v = views[name]
            row = v['top'] + (y-TOP)/SPAN*v['span']
            centres.append(sign*(np.polyval(v['wire'], row)-v['grip'])*SPAN/v['span'])
            widths.append(v['wire_width']*SPAN/v['span'])
        cx = np.mean(centres)+GRIP_X
        radius = np.mean(widths)*.5
        coords = [point(cx+radius*math.cos(i*math.tau/8),radius*math.sin(i*math.tau/8),y) for i in range(8)]
        if not loft.verts:
            loft.ring([point(cx,0,y)],'flax')
        loft.ring(coords,'flax')
    loft.ring([point(cx,0,y)],'flax')
    return loft.object('String')


def game(v):
    return [v[1],v[2],-v[0]]


def pack(rows):
    scale=(10000,)*3+(1000,)*3+(100,)*5+(10000,)*2
    lookup,verts,indices={},[],[]
    for row in orient(rows):
        key=tuple(round(x*k) for x,k in zip(row,scale))
        if key not in lookup:
            lookup[key]=len(lookup)+1
            verts.extend(key)
        indices.append(lookup[key])
    return dict(triangles=len(indices)//3,v=verts,i=indices)


def export(objects):
    data = {'parts': {'body': [], 'crystal': [], 'string': []},'stats': {}}
    for ob in objects:
        rows = data['parts'][ob.name.lower()]
        coords = np.asarray(ob.verts)
        for tri,material,normals in zip(ob.faces,ob.ids,ob.normals):
            co = coords[list(tri)]
            weights,mask,_,_=SPEC[NAMES[material]]
            for index,p,n in zip(tri,co,normals):
                rows.append([*game(p),*game(n),*weights,ob.grain[index],0,mask,p[2]+(BASE-GRIP_Y)/SPAN])
        data['stats'][ob.name] = len(rows)//3
    INTERMEDIATE.write_text(json.dumps(data,separators=(',',':'),allow_nan=False)+chr(10))
    parts = {name:pack(rows) for name,rows in data['parts'].items()}
    xyz = np.array(parts['body']['v']+parts['string']['v']).reshape(-1,13)[:,:3]/10000
    lo,hi = xyz.min(axis=0).tolist(),xyz.max(axis=0).tolist()
    string_z = np.array(parts['string']['v']).reshape(-1,13)[:,2].mean()/10000
    model = dict(formatVersion=1,vertexStride=13,name='hunter_bow',scale=10000,nscale=1000,
                 height=round(hi[1]-lo[1],4),bounds=dict(min=lo,max=hi),
                 sockets=dict(grip=[0,0,0],top=[0,hi[1],0],bottom=[0,lo[1],0],stringZ=round(string_z,4)),
                 uvScale=10000,**parts)
    PACKED.write_text(json.dumps(model,separators=(',',':'),allow_nan=False)+chr(10))
    print('EXPORT', data['stats'],model['bounds'],model['sockets'])


def setup_scene():
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 16
    sc.cycles.seed = 0
    sc.cycles.use_denoising = False
    sc.render.film_transparent = True
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.image_settings.file_format = 'PNG'
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = 'Standard'
    sc.world = bpy.data.worlds.new('Softbox studio')
    sc.world.use_nodes = True
    sc.world.node_tree.nodes['Background'].inputs[0].default_value = (.72,.70,.68,1)
    sc.world.node_tree.nodes['Background'].inputs[1].default_value = .82
    def aimed(name,data,loc,target):
        ob = bpy.data.objects.new(name,data)
        bpy.context.collection.objects.link(ob)
        ob.location = Vector(loc)
        ob.rotation_euler = (Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
        return ob
    for label,position,power,size in [('Key',(-1.2,-1.5,1.9),65,1.7),('Fill',(-.8,1.5,1.4),52,1.8),('Edge',(1.1,.3,1.2),28,1.5)]:
        light = bpy.data.lights.new(label,'AREA')
        light.energy,light.shape,light.size = power,'DISK',size
        aimed(label,light,position,(0,0,0))
    cameras = {}
    for name in [*CROPS,'iso']:
        camera = bpy.data.cameras.new(name)
        if name in CROPS:
            v = views[name]
            direction = {'left':(0,-1,0),'front':(-1,0,0),'right':(0,1,0)}[name]
            cx = (sum(CROPS[name])/2-v['grip'])/v['span']
            cz = (GRIP_Y-TOP)/SPAN-(768-v['top'])/v['span']
            target = Vector((cx if name=='left' else -cx if name=='right' else 0, -cx if name=='front' else 0, cz))
            height = 1536/v['span']
        else:
            target,direction,height = Vector((.04,0,.015)),(-.70,-1.1,.30),1.10
        camera.type,camera.ortho_scale,camera.sensor_fit = 'ORTHO',height,'VERTICAL'
        cameras[name] = aimed('View '+name,camera,target+Vector(direction)*3,target)
    return cameras


def render():
    sc = bpy.context.scene
    cams = setup_scene()
    for name,cam in cams.items():
        sc.camera = cam
        sc.render.resolution_x = 600 if name=='iso' else CROPS[name][1]-CROPS[name][0]
        sc.render.resolution_y = 1536
        sc.render.filepath = str(OUT / f'preview_{name}.png')
        bpy.ops.render.render(write_still=True)
    sc.render.filepath = '//preview_iso.png'
    for area in bpy.context.screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective = 'CAMERA'
            area.spaces.active.shading.color_type = 'MATERIAL'
            area.spaces.active.overlay.show_overlays = False
    # Blender's temporary render buffer is not a scene texture. Only allow that
    # buffer, both here and after reopening the saved project.
    assert all(im.type in ('RENDER_RESULT','COMPOSITING') for im in bpy.data.images)
    assert all(not any(n.type=='TEX_IMAGE' for n in m.node_tree.nodes) for m in mats)
    bpy.context.preferences.filepaths.save_version = 0
    path=str(OUT/'hunter_bow.blend')
    bpy.ops.wm.save_as_mainfile(filepath=path)
    bpy.ops.wm.open_mainfile(filepath=path)
    images=[im for im in bpy.data.images if im.type not in ('RENDER_RESULT','COMPOSITING')]
    assert not images,images
    print('REOPEN PASS: images=',len(images),'engine=',bpy.context.scene.render.engine)
    for ob in bpy.context.scene.objects:
        if ob.type=='MESH':
            assert ob.data.has_custom_normals and ob.data.uv_layers.get('SubmaskHeight')
            print('native mesh',ob.name,len(ob.data.polygons),'custom smooth normals, UV present')


def fibre_noise(coords):
    grid=np.floor(coords)
    f=coords-grid
    u=f*f*(3-2*f)
    def hashed(x,y):
        n=np.sin((grid[:,0]+x)*127.1+(grid[:,1]+y)*311.7)*43758.5453
        return n-np.floor(n)
    base=hashed(0,0)*(1-u[:,0])+hashed(1,0)*u[:,0]
    top=hashed(0,1)*(1-u[:,0])+hashed(1,1)*u[:,0]
    return base*(1-u[:,1])+top*u[:,1]


def raster_previews():
    """Orthographic inspection of the *packed* asset, independent of Blender and Cycles."""
    from PIL import Image
    model = json.loads(PACKED.read_text())
    colors = {tuple(w):bytes.fromhex(c) for w,_,c,_ in SPEC.values()}
    for name in [*CROPS,'iso']:
        width,height = (600 if name=='iso' else 480),1536
        if name=='iso':
            eye=np.array([-.70,-1.1,.30])
            target=np.array([.04,0,.015])
            scale=1536/1.10
        else:
            v=views[name]
            eye=np.array({'left':[0.,-1,0],'front':[-1.,0,0],'right':[0.,1,0]}[name])
            cx=(sum(CROPS[name])/2-v['grip'])/v['span']
            cz=(GRIP_Y-TOP)/SPAN-(768-v['top'])/v['span']
            target=np.array([cx if name=='left' else -cx if name=='right' else 0,-cx if name=='front' else 0,cz])
            scale=v['span']
        eye=eye/np.linalg.norm(eye)
        right=np.cross([0.,0,1],eye)
        right/=np.linalg.norm(right)
        up=np.cross(eye,right)
        # Supersample 2x with a depth buffer so the translucent PNG retains subpixel widths.
        rgba=np.zeros((height*2,width*2,4),dtype=np.uint8)
        depth=np.full(rgba.shape[:2],-np.inf)
        for part in [model['body'],model['string']]:
            data=np.array(part['v']).reshape(-1,13)
            world=data[:,[2,0,1]]*np.array([-1,1,1])/model['scale']
            co=world-target
            screen=np.column_stack((width/2+co@right*scale,height/2-co@up*scale))*2
            for tri in np.array(part['i']).reshape(-1,3)-1:
                a,b,c=screen[tri]
                xmin,ymin=np.maximum(0,np.floor(screen[tri].min(0)).astype(int))
                xmax,ymax=np.minimum([width*2,height*2],np.ceil(screen[tri].max(0)).astype(int))
                if xmax<=xmin or ymax<=ymin:
                    continue
                dx,dy=b-a
                ex,ey=c-a
                det=dx*ey-dy*ex
                # Export reflects an axis; front-facing game triangles are positive in this y-down projection.
                if det<=1e-10:
                    continue
                x,y=np.meshgrid(np.arange(xmin,xmax)+.5-a[0],np.arange(ymin,ymax)+.5-a[1])
                u,v=(x*ey-y*ex)/det,(dx*y-dy*x)/det
                za,zb,zc=co[tri]@eye
                z=za+u*(zb-za)+v*(zc-za)
                dest=depth[ymin:ymax,xmin:xmax]
                visible=(u>=0)&(v>=0)&(u+v<=1)&(z>dest)
                dest[visible]=z[visible]
                bary=np.column_stack((1-u[visible]-v[visible],u[visible],v[visible]))
                rest=bary @ (data[tri,:3]/model['scale'])
                grain=bary @ (data[tri,9]/100)
                h=bary @ (data[tri,12]/model['uvScale'])
                weights=tuple(data[tri[0],6:9]//100)
                swatch=np.frombuffer(colors[weights],dtype=np.uint8)
                X,Y,Z=rest.T
                if weights==(1,0,0):
                    space=np.column_stack((grain*14.25,h*6.75))
                    runout=.68*fibre_noise(space)+.32*fibre_noise(2.7*space)
                    drift=np.sin(22*Y+2.2*np.sin(9*h))
                    rings=np.sin(grain*20+3.1*runout)
                    fibre=np.sin(210*grain+2.2*drift+4*runout)
                    variation=.66+.55*runout+.19*rings+.075*fibre
                elif weights==(0,1,0):
                    variation=.96+.09*np.sin(28*grain+1.3*np.sin(57*Y))+.04*np.sin(grain*110+38*Y)*np.sin(371*X-120*Z)
                elif weights==(0,0,1):
                    variation=.93+.13*np.sin(2250*Y+math.tau*grain)
                else:
                    hide=np.sin(1510*X+127*Y)*np.sin(1190*Z-711*Y)
                    variation=.92+.07*hide+.12*np.sin(220*Y+math.tau*grain)
                light=eye*.35+up*.55-right*.55
                normals=bary@(data[tri][:,[5,3,4]]*[-1,1,1]/model['nscale'])
                normals/=np.maximum(1e-12,np.linalg.norm(normals,axis=1)[:,None])
                shade=.80+.32*np.maximum(0,normals@light)
                color=np.clip(swatch*(shade*np.sqrt(variation))[:,None],0,255).astype(np.uint8)
                tile=rgba[ymin:ymax,xmin:xmax]
                tile[visible,:3]=color
                tile[visible,3]=255
        img=Image.fromarray(rgba).resize((width,height),Image.Resampling.LANCZOS)
        from PIL.PngImagePlugin import PngInfo
        info=PngInfo()
        info.add_text('Software','HunterBow packed mesh CPU rasterizer')
        img.save(OUT/f'preview_{name}.png',pnginfo=info)
        print('CPU rendered packed mesh',name)


def compare():
    # Mirror the right drawing into the left camera at the same measured grip and
    # physical scale used for the renders. No independent best-fit search.
    l,r=views['left'],views['right']
    yy,xx=np.indices(l['mask'].shape)
    ry=np.floor(r['top']+(yy+.5-l['top'])*r['span']/l['span']).astype(int)
    rx=np.floor(r['grip']-(xx+.5+CROPS['left'][0]-l['grip'])*r['span']/l['span']-CROPS['right'][0]).astype(int)
    inside=(ry>=0)&(ry<r['mask'].shape[0])&(rx>=0)&(rx<r['mask'].shape[1]);mirror=np.zeros_like(inside)
    mirror[inside]=r['mask'][ry[inside],rx[inside]]
    baseline=(mirror&l['mask']).sum()/(mirror|l['mask']).sum()
    print('Measured side wire offsets from grip, meters',*[abs(np.polyval(v['wire'],v['top']+v['span']*(GRIP_Y-TOP)/SPAN)-v['grip'])/v['span'] for v in (l,r)])
    print('REFERENCE side-to-side IoU',baseline,'side floor',baseline-.03)
    panels,metrics=[],{}
    for name,v in views.items():
        actual = read_image(OUT/f'preview_{name}.png')[:,:,3] >= 128
        reference = v['mask']
        both = reference & actual
        iou = both.sum()/(reference | actual).sum()
        metrics[name]=iou
        print(f'SILHOUETTE {name} IoU={iou:.6f} intersection={both.sum()} union={(reference | actual).sum()}')
        panel = np.full((*both.shape,3),244,np.uint8)
        panel[both] = [70,61,60]
        panel[reference & ~actual] = [189,73,37]
        panel[actual & ~reference] = [26,138,154]
        panels.append(panel)
    dest = OUT/'overlay_comparison.png'
    if bpy is None:
        Image.fromarray(np.concatenate(panels,axis=1)).save(dest)
    else:
        buf = oiio.ImageBuf(np.ascontiguousarray(np.concatenate(panels,axis=1)))
        assert buf.write(str(dest)),buf.geterror()
    assert metrics['front']>=.978 and min(metrics['left'],metrics['right'])>=baseline-.03,metrics
    print('Overlay: left / front / right; charcoal=overlap, orange=reference only, teal=mesh only')


def verify():
    model = json.loads(PACKED.read_text())
    template = json.loads((PACKED.parent/'ThornBow.mesh.json').read_text())
    data = json.loads(INTERMEDIATE.read_text())
    assert all(model[k]==template[k] for k in ('formatVersion','scale','nscale'))
    assert set(template)<=set(model) and model['name']=='hunter_bow'
    assert model['height']==1 and model['sockets']['grip']==[0,0,0] and model['sockets']['stringZ']<0
    assert model['crystal']=={'v':[],'i':[],'triangles':0}
    assert model['vertexStride']==13
    assert 1600<=sum(model[p]['triangles'] for p in data['parts'])<=2800
    positions=[]
    for name in ('body','string'):
        p = model[name]
        assert set(template[name])==set(p) and pack(data['parts'][name])==p
        assert np.isfinite(data['parts'][name]).all()
        vertices = np.asarray(p['v']).reshape(-1,13)
        ix = np.asarray(p['i'])
        assert vertices.dtype.kind=='i' and ix.dtype.kind=='i' and np.isfinite(vertices).all()
        assert len(ix)==p['triangles']*3 and ix.min()==1 and ix.max()==len(vertices)
        assert np.all(vertices[:,10]==0)
        assert np.all(vertices[:,8]==(100 if name=='string' else 0))
        assert np.max(abs(np.linalg.norm(vertices[:,3:6]/model['nscale'],axis=1)-1))<.001
        faces=vertices[ix.reshape(-1,3)-1]
        pos=faces[:,:,:3]
        positions.extend(vertices[:,:3].tolist())
        cross=np.cross(pos[:,1]-pos[:,0],pos[:,2]-pos[:,0])
        assert (np.linalg.norm(cross,axis=1)>0).all(),f'{name} collapsed face'
        assert (np.einsum('ij,ikj->ik',cross,faces[:,:,3:6])>0).all(),f'{name} winding'
        edges=Counter((tuple(a),tuple(b)) for tri in pos for a,b in zip(tri,np.roll(tri,-1,axis=0)))
        assert all(n==1 and edges[b,a]==1 for (a,b),n in edges.items()),f'{name} open or nonmanifold edges'
        links={}
        for a,b in edges:links.setdefault(a,set()).add(b)
        stack=[next(iter(links))];seen=set(stack)
        while stack:
            new=links[stack.pop()]-seen;stack.extend(new);seen.update(new)
        assert len(seen)==len(links),f'{name} disconnected'
        assert set(vertices[:,11])=={10000 if name=='string' else 0}
        assert np.max(abs(vertices[:,12]-(vertices[:,1]+(BASE-GRIP_Y)/SPAN*10000)))<=1
        print('normal directions',name,len(set(map(tuple,vertices[:,3:6]))))
        assert np.einsum('ij,ij->',pos[:,0],cross)>0, f'{name} inward'
        print(f'{name}: {len(vertices)} indexed vertices, {len(pos)} triangles, closed, outward')
    points=np.asarray(positions)/model['scale']
    assert points.min(0).tolist()==model['bounds']['min'] and points.max(0).tolist()==model['bounds']['max']
    # Cast an oblique ray from each string end through the quantized body. An odd
    # crossing count establishes an interior seat independently of the view images.
    body = model['body']
    vert = np.array(body['v']).reshape(-1,13)[:,:3]
    a,b,c = vert[np.array(body['i']).reshape(-1,3)-1].transpose(1,0,2)
    cord = np.unique(np.array(model['string']['v']).reshape(-1,13)[:,:3],axis=0)
    ray = np.array([1,.013,.031])
    q = np.cross(ray,c-a)
    det = ((b-a)*q).sum(1)
    denom = np.where(abs(det)>1e-9,det,1)
    for y in (cord[:,1].min(),cord[:,1].max()):
        r = cord[cord[:,1]==y].mean(0)-a
        k = np.cross(r,b-a)
        u,w,t = (q*r).sum(1)/denom, (k*ray).sum(1)/denom, (k*(c-a)).sum(1)/denom
        hits = (abs(det)>1e-9)&(u>0)&(w>0)&(u+w<1)&(t>0)
        assert hits.sum()%2==1, f'string endpoint outside body at {y}'
    directions=set()
    for part in ('body','string'):
        directions.update(map(tuple,np.array(model[part]['v']).reshape(-1,13)[:,3:6]))
    print('distinct packed normal directions',len(directions),'total triangles',sum(model[p]['triangles'] for p in data['parts']))
    print('PASS both string endpoints seated in nocks')
    print('PASS format v1, stride 13, intermediate/packed agreement, finite, indices, dimensions, materials, winding, areas, watertightness, signed volumes')


def lua_check():
    """Exercise real Lua loader/visual with an in-memory CustomGeometry recorder."""
    from lupa.lua54 import LuaRuntime
    lua=LuaRuntime(unpack_returned_tuples=True)
    model=json.loads(PACKED.read_text());g=lua.globals()
    g.scripts=str(ROOT/'scripts');g.raw=PACKED.read_text()
    g.decode=lambda raw:lua.table_from(json.loads(raw),recursive=True)
    lua.execute("""
        package.path=scripts..'/?.lua;'..package.path
        Vector2=function(...)return {...}end; Vector3=Vector2; Color=Vector2; Quaternion=Vector2
        Variant=function(v)return v end
        cjson={decode=decode};cache={};local material={}; local node={}
        function cache:GetFile(path)
            assert(path=='model/forge-blades/HunterBow.mesh.json')
            return {ReadString=function()return raw end,Close=function()end}
        end
        function cache:GetResource(t,path)assert(path=='model/forge-blades/HunterBow.xml');return material end
        function material:Clone()return setmetatable({}, {__index=material}) end
        function material:SetShaderParameter(k,v)self[k]=v end
        function material:Dispose()end
        function node:CreateChild()return setmetatable({},{__index=node})end
        function node:Remove()self.removed=true end
        captures={}; TRIANGLE_LIST=0
        function node:CreateComponent(t)
            assert(t=='CustomGeometry');local geometry={p={},n={},c={},uv={}}
            function geometry:BeginGeometry()end
            function geometry:SetMaterial(i,m)assert(i==0 and m~=material);return true end
            function geometry:Commit()self.done=true end
            for method,buf in pairs({DefineVertex='p',DefineNormal='n',DefineColor='c',DefineTexCoord='uv'})do
                geometry[method]=function(self,value)table.insert(self[buf],value)end
            end
            table.insert(captures,geometry);return geometry
        end
        local visual=require('combat.HunterBowVisual')
        local job,err=visual.New(node,.5);assert(job,err)
        local frames=0
        repeat frames=frames+1;assert(frames<20) until visual.Step(job)
        assert(frames>1 and job.ready and captures[1].done and captures[2].done)
        visual.SetVisible(job,true);visual.SetStringVisible(job,false);assert(job.stringNode.enabled==false)
        visual.SetGrade(job,2);visual.SetBend(job,.05);assert(job.material.wood_color and job.material.bend>0)
        visual.Dispose(job);assert(job.node==nil)
        local before=cache.GetResource;cache.GetResource=function()return nil end
        assert(visual.New(node,.5)==nil);cache.GetResource=before
    """)
    for i,part in enumerate(('body','string'),1):
        rec=g.captures[i];p=model[part];v=np.array(p['v']).reshape(-1,13)[np.asarray(p['i'])-1]
        for field,begin,end,scale in [('p',0,3,10000),('n',3,6,1000),('c',6,10,100),('uv',11,13,10000)]:
            rows=rec[field];assert len(rows)==len(v)
            actual=np.array([[rows[j+1][k+1] for k in range(end-begin)] for j in range(len(v))])
            assert np.max(abs(actual-v[:,begin:end]/scale))<1e-12,(part,field)
        print(part,len(v),'Lua upload positions/normals/colours/UVs match packed data')
    print('PASS frame budget, material clone, bend, forge tint, string handoff, disposal and asset-failure fallback')


if __name__=='__main__':
    mode=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else (sys.argv[1] if bpy is None and len(sys.argv)>1 else 'build')
    OUT.mkdir(parents=True,exist_ok=True)
    if mode=='raster' and '--inspection-dir' in sys.argv:
        # Keep native previews intact during a packed-mesh cross-check.
        OUT=Path(sys.argv[sys.argv.index('--inspection-dir')+1]);OUT.mkdir(parents=True,exist_ok=True)
    if mode=='lua':
        lua_check()
    elif mode in ('verify','topology'):
        verify()
    else:
        views=measure()
        if mode=='raster':
            raster_previews()
            compare()
        elif mode=='compare':
            compare()
        elif mode in ('build','export'):
            if bpy is not None:
                bpy.ops.wm.read_factory_settings(use_empty=True)
                mats=materials()
            elif mode=='build':
                raise SystemExit('Use Blender for build, or Python -- export for mesh-only export.')
            export((bow_body(),flax()))
            if mode=='build':
                render()
                compare()
        elif mode!='measure':
            raise ValueError(mode)
