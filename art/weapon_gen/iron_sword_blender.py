"""遗迹铁剑 / IronSword. Run with Blender -b --factory-startup -P this_file.
System Python subcommands: measure, export, compare, topology, lua. Inputs and camera
registration are in original image pixels (pixel centres have integer coords).
"""
import hashlib
import json
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
REF = ROOT / 'art/weapons_2d/rarity/iron_sword_3_threeview_v1.png'
OUT = ROOT / 'art/weapon_gen/out/iron_sword'
LUA = ROOT / 'scripts/combat/models/IronSword.lua'
VIEWS = ('front', 'side', 'back')
# Centre of each crop, measured along the full blade. Each orthographic camera uses
# exactly 216 x 864 reference pixels. No fit-to-mask or per-part scaling.
CENTRES = (430.5, 768.5, 1109.5)
WIDTH, HEIGHT = 216, 864
TIP, HEEL = 29.5, 799.0
GRIP_Y = (611 + 729) / 2
M = 1.855 / (HEEL - TIP)
QUANT = 10000
TRIS = []


def reference_pixels():
    from PIL import Image
    return np.asarray(Image.open(REF).convert('RGB'), dtype=int)


def ink_columns():
    rgb = reference_pixels()
    ink = (rgb[:, :, 0] < 150) & (rgb[:, :, 2] - rgb[:, :, 0] > 12)
    return [ink[:, int(c + .5) - WIDTH//2:int(c + .5) + WIDTH//2] for c in CENTRES]


def radii(columns, y):
    widths = []
    for col in columns:
        xs = np.flatnonzero(col[y])
        widths.append((xs[-1] - xs[0] + 1) / 2)
    return (widths[0] + widths[2]) / 2, widths[1]


def measure():
    cols = ink_columns()
    print('Source pixels: row, then left..right (inclusive) in front / side / back')
    detail_rows = (30,180,400,517,550,573,590,602,611,670,729,735,757,780,798,800)
    for y in sorted(set(detail_rows).union(row for row,*_ in STATIONS)):
        spans = []
        for c, col in zip(CENTRES, cols):
            x = np.flatnonzero(col[y]) + int(c+.5)-WIDTH//2
            spans.append(f'{x[0]}..{x[-1]}' if len(x) else 'empty')
        print(y, *spans)
    return cols


# Runtime turning/cavity values. Blender shading uses one physical surface per
# part, with optical response from the normals and object-space node networks.
SHADE = {'edge':1,'steel':.99,'bevel':.98,'crown':.97,'ridge':.96,'turn':.97,
         'silver':1,'stone':.98,'cut':.97,'slate':.96,'recess':.90,'seam':.87,
         'seat':.51,'arris':1,'wrap':1,'wrap_mid':.99,'wrap_lo':.96,'stitch':.94}


def vertex(p):
    x, row, z = p
    return tuple(round(v*M*QUANT)/QUANT for v in (x, GRIP_Y-row, z))


class Shell:
    def __init__(self, name):
        self.name = name
        self.faces = []

    def face(self, points, mat):
        # Coincident corners occur at the ends of a rib or pointed ring.
        poly = list(dict.fromkeys(vertex(p) for p in points))
        for i in range(1, len(poly)-1):
            self.faces.append(([poly[0], poly[i], poly[i+1]], mat))

    def bridge(self, a, b, materials):
        for i in range(len(a)):
            k = (i+1) % len(a)
            self.face([a[i], a[k], b[k], b[i]], materials[i % len(materials)])

    def finish(self):
        # Propagate orientation across shared edges and select the exterior by
        # signed volume in game coordinates, after the Lua quantisation step.
        edges = defaultdict(list)
        for i, (tri, _) in enumerate(self.faces):
            for a, b in zip(tri, tri[1:]+tri[:1]):
                edges[tuple(sorted((a, b)))].append((i, a < b))
        neighbours = defaultdict(list)
        for edge, pair in edges.items():
            if len(pair) != 2:
                raise ValueError((self.name, 'open or non-manifold edge', edge, pair))
            (i, a), (j, b) = pair
            neighbours[i].append((j, a == b))
            neighbours[j].append((i, a == b))
        flip, stack = {0: False}, [0]
        while stack:
            i = stack.pop()
            for j, opposite in neighbours[i]:
                needed = flip[i] ^ opposite
                if j not in flip:
                    flip[j] = needed
                    stack.append(j)
                assert flip[j] == needed
        assert len(flip) == len(self.faces)
        for i, (tri, _) in enumerate(self.faces):
            if flip[i]:
                tri.reverse()
        volume6 = sum(np.dot(a, np.cross(b, c)) for (a, b, c), _ in self.faces)
        for tri, mat in self.faces:
            if volume6 < 0:
                tri.reverse()
            shade = SHADE[mat]
            leather = self.name in ('Leather grip core','Five-turn leather binding','Cross-laced leather thong')
            r=int(self.name=='Ridged steel blade')
            g=int(not r and not leather)
            TRIS.append(dict(p=tri, c=[r, g, 0], shade=shade, glow=0, part=self.name, material=mat))


# Row, traced central shoulder half-width, crown correction and lateral drift
# in original pixels. Both outer radii come directly from the three ink masks.
STATIONS = [(556,9,-4.0,.35),(543,10,-2.3,.55),(540,13,0,-.60),(495,12,-1.15,.85),
            (442,11.8,1.1,-1.05),(382,10.8,-.7,.65),(320,10.1,.65,-.75),
            (257,9.8,-.95,.8),(192,9.8,.85,-.62),(134,9.4,-1.35,.54),
            (103,.85,0,-.16)]


def blade(cols):
    shell=Shell('Ridged steel blade')
    last=None
    for row,shoulder,adjust,drift in STATIONS:
        w,side=radii(cols,552 if row==556 else row)
        if row==556:
            w,side=w-1,18
        if row==543:
            # An exposed bearing ledge leads into the narrower heel below it.
            w,side=w*.85,18
        depth=side+adjust
        haunch=depth*(.78+.045*math.sin(row*.041))
        flute=shoulder*.72
        edge=w*(.965+.01*math.cos(row*.025))
        ring=[]
        for sign in (-1,1):
            ring += [(sign*w,row,0),(sign*edge,row,sign*depth*.50),
                     (sign*shoulder,row,sign*haunch),(sign*flute,row,sign*(haunch-depth*.085)),
                     (drift,row,sign*depth),(-sign*flute,row,sign*(haunch-depth*.085)),
                     (-sign*shoulder,row,sign*haunch),(-sign*edge,row,sign*depth*.50)]
        if last:
            facets=['bevel','steel','crown','ridge','ridge','crown','steel','bevel']*2
            shell.bridge(last,ring,['seat']*16 if row==540 else facets)
        else:
            for i in range(len(ring)):
                shell.face([ring[i-1],ring[i],(0,row,0)],'turn')
        last=ring
    shell.bridge(last,[(0,TIP,0)]*len(last),['bevel','edge','edge','steel','steel','edge','edge','bevel']*2)
    shell.finish()


def symmetric_loop(half):
    return half + [(-x,y) for x,y in reversed(half) if x != 0]


def at_depth(loop, depth):
    return [(x,y,depth) for x,y in loop]


def cap_with_pockets(shell, rim, pockets, z):
    # Constrained triangulation of the traced right-hand face. Indices 0..12
    # follow the bevel rim, 13..17 and 18..22 follow its two pocket mouths.
    pts=[p for p in rim if p[0]>=0]+pockets[0]+pockets[1]
    face_ids=[(21,7,8),(1,2,13),(1,10,0),(10,1,13),(10,12,0),
              (12,10,11),(17,10,13),(10,17,9),(16,21,8),(9,16,8),
              (17,16,9),(20,5,6),(7,20,6),(21,20,7),(2,14,13),
              (14,2,15),(19,4,5),(20,19,5),(16,22,21),(22,16,15),
              (3,22,15),(2,3,15),(19,18,4),(18,3,4),(3,18,22)]
    for side in (-1,1):
        for ids in face_ids:
            shell.face([(side*pts[i][0],pts[i][1],z) for i in ids],'stone')


def guard():
    shell = Shell('Carved crossguard')
    # Traced exterior / bevel break and two cutouts per quillon; both faces
    # share their actual inset floors and sloping pocket walls with the mesh.
    outline = symmetric_loop([(0,562),(23,559),(37,554),(56,559),(60,555.5),
        (83.5,556),(90,590.5),(78,596.5),(55,590),(33,588),(23,591),(14,602),(0,603)])
    cap = symmetric_loop([(0,567),(24,564),(37,559),(58,565),(63,560),
        (79,560),(84,585),(77,589),(55,583),(32,581),(19,585),(10,596),(0,596)])
    holes = [[(28,567),(37,564),(49,568),(54,576.5),(32,574)],
             [(60,564.8),(72.7,566),(77,581.5),(61.5,578),(55.5,568)]]
    holes += [[(-x,y) for x,y in h] for h in holes]
    shell.bridge(at_depth(outline,-5),at_depth(outline,5),['slate'])
    for sign in (-1,1):
        arris=[(.64*x+.36*u,.64*y+.36*v) for (x,y),(u,v) in zip(outline,cap)]
        shell.bridge(at_depth(outline,sign*5),at_depth(arris,sign*9.6),['cut'])
        shell.bridge(at_depth(arris,sign*9.6),at_depth(cap,sign*12),
                     ['silver' if y<573 else 'slate' for _,y in outline])
        cap_with_pockets(shell,cap,holes,sign*12)
        for h in holes:
            cx,cy=np.mean(h,axis=0)
            floor=[(cx+(x-cx)*.70,cy+(y-cy)*.62) for x,y in h]
            shell.bridge(at_depth(h,sign*12),at_depth(floor,sign*8.5),
                         ['recess','slate','cut','recess','recess'])
            shell.face(at_depth(floor,sign*8.5),'recess')
    shell.finish()


def diamond(name, layers):
    shell = Shell(name)
    for sign in (-1,1):
        last=None
        for top,w,mid,bottom,zt,zx,zb,tones in layers:
            ring=[(0,top,sign*zt),(w,mid,sign*zx),(0,bottom,sign*zb),(-w,mid,sign*zx)]
            if last:
                shell.bridge(last,ring,tones)
            elif any((zt,zx,zb)) and sign==-1:
                shell.bridge(ring,[(x,y,-z) for x,y,z in ring],['slate'])
            last=ring
        peak=(0,mid,sign*(zx+2.3))
        for i,tone in enumerate(['stone','slate','turn','silver']):
            shell.face([ring[i],ring[(i+1)%4],peak],tone)
    shell.finish()


def furniture(cols):
    diamond('Guard lozenge',[
        (538,23,577,616,14.6,13,13.7,[]),
        (555,15,577,595,26.5,29.5,24.4,['silver','slate','cut','stone']),
        (558.5,13.3,577,594.5,25.8,27,21,['recess','recess','seam','recess']),
        (562,10.7,577,592.5,26.7,28.5,23,['stone','turn','slate','silver'])])
    w,d = radii(cols,757)
    diamond('Iron counterweight',[
        (719,w,757,HEEL,0,0,0,[]),
        (733,w-3,757,794,11,5,2,['edge','slate','slate','silver']),
        (738,15.5,757,781.5,13.5,13,9.4,['stone','cut','bevel','silver']),
        (741,13.1,757,778,12.7,12.6,8.5,['recess','seam','recess','recess']),
        (744,10.4,757,774,14.1,d-2.3,10,['silver','slate','cut','silver'])])


def oval(w,d):
    return [(w*x,d*z) for x,z in [(0,-1),(.79,-.84),(1,0),(.79,.84),(0,1),(-.79,.84),(-1,0),(-.79,-.84)]]


def grip_ellipse(w,d):
    return [(w*math.cos(math.tau*i/12),d*math.sin(math.tau*i/12)) for i in range(12)]


def ferrule(name, stations, tones, section=oval):
    shell=Shell(name)
    last=None
    for j,(y,w,d) in enumerate(stations):
        ring=[(x,y,z) for x,z in section(w,d)]
        if last:
            shell.bridge(last,ring,tones[j-1])
        else:
            shell.face(ring,'slate')
        last=ring
    shell.face(last,'slate')
    shell.finish()


def grip(cols):
    top,bottom=609,731
    rows=(609,628,646,670,693,713,731)
    radii_at=[radii(cols,max(617,min(726,y))) for y in rows]
    rings=[(y,w-.85,d-.85) for y,(w,d) in zip(rows,radii_at)]
    ferrule('Leather grip core',rings,[['wrap_lo']]*6,grip_ellipse)

    # The underside beds into the rounded grip. A thinner contra-wound
    # thong crosses the five broad turns. The tips tuck into the ferrules.
    def wind(name,turns,half_width,profile,phase,tones):
        shell=Shell(name)
        count=abs(turns)*12
        last=None
        for i in range(count+1):
            row=top+(bottom-top)*i/count
            az=(phase+i*(1 if turns>0 else -1))%12
            section=[]
            for dy,lift in profile:
                y=row+dy*half_width
                w,d=[np.interp(y,rows,axis) for axis in zip(*radii_at)]
                x,z=grip_ellipse(w-.85,d-.85)[az]
                radius=math.hypot(x,z)
                section.append((x+x*lift/radius,y,z+z*lift/radius))
            if last:
                shell.bridge(last,section,tones)
            else:
                shell.face(section,tones[0])
            last=section
        shell.face(last,tones[0])
        shell.finish()
    wind('Five-turn leather binding',5,10.9,
         [(-1,-.65),(-.78,1.0),(.64,.91),(1,.12),(1,-.65)],2,
         ['wrap_mid','wrap','wrap_mid','stitch','wrap_lo'])
    wind('Cross-laced leather thong',-3,1.08,
         [(-1,.12),(0,1.52),(1,.12),(0,-.45)],6,
         ['wrap_mid','wrap_lo','stitch','stitch'])
    ferrule('Grip throat',[(588,25,16),(599,19,15.7),(601,18,15),
            (603,19.6,16.4),(608,19.6,16.4),(610,16.5,14.4),(615,16,14.1)],
            [['slate'],['seat'],['arris'],['silver'],['arris'],['seat']])
    ferrule('Pommel ferrule',[(727,15,12),(732,18.5,15),(736,18,15),(740,14.5,12.7)],
            [['cut','stone','cut','silver'],['silver','stone'],['slate','cut']])


def add_normals():
    # Angle-weighted skin normals share across triangle diagonals and around
    # the winding. Preserve end caps and intentional folds above 70 degrees.
    around=defaultdict(list)
    planes=[]
    for tri in TRIS:
        pts=np.array(tri['p'])
        a,b,c=pts
        n=np.cross(b-a,c-a)
        n/=np.linalg.norm(n)
        planes.append(n)
        if tri['c']==[0,0,0]:
            for i,p in enumerate(tri['p']):
                u,v=pts[i-1]-pts[i],pts[(i+1)%3]-pts[i]
                angle=math.atan2(np.linalg.norm(np.cross(u,v)),np.dot(u,v))
                around[tri['part'],p].append((n,angle))
    for tri,n in zip(TRIS,planes):
        tri['n']=[]
        for p in tri['p']:
            normal=n
            if tri['c']==[0,0,0]:
                fan=around[tri['part'],p]
                normal=sum(axis*weight for axis,weight in fan if axis@n>.342)
                normal=normal/np.linalg.norm(normal)
            tri['n'].append([round(float(v),4) for v in normal])


def export():
    points = np.array([p for t in TRIS for p in t['p']])
    lo,hi = points.min(axis=0).tolist(),points.max(axis=0).tolist()
    meta = dict(height=round(hi[1]-lo[1],4),bounds=dict(min=lo,max=hi),
                sockets=dict(grip=[0,0,0],tip=[0,hi[1],0],bladeBase=list(vertex((0,556,0))),pommel=[0,lo[1],0]))
    add_normals()
    for tri in TRIS:
        inner=tri['material'] in ('crown','ridge','recess','seam')
        tri['uv']=[[.35 if inner else 0, round((p[1]-lo[1])/meta['height']*QUANT)/QUANT] for p in tri['p']]
    (OUT/'iron_sword.json').write_text(json.dumps(dict(meta=meta,tris=TRIS),separators=(',',':'))+'\n')
    def numbers(seq):
        return ','.join(map(str,seq))
    def block(seq,n):
        return ',\n    '.join(numbers(seq[i:i+n]) for i in range(0,len(seq),n))
    pos=[round(v*QUANT) for t in TRIS for p in t['p'] for v in p]
    nrm=[round(v*QUANT) for t in TRIS for normal in t['n'] for v in normal]
    uv=[round(v*QUANT) for t in TRIS for pair in t['uv'] for v in pair]
    col=[round(v*100) for t in TRIS for v in (*t['c'],t['shade'],t['glow'])]
    sockets=','.join(k+'={'+numbers(v)+'}' for k,v in meta['sockets'].items())
    LUA.write_text('-- Generated by art/weapon_gen/iron_sword_blender.py. Metres, grip origin, +Y tip.\n'
        'return {\n'+f'  name="iron_sword", scale={QUANT}, triangles={len(TRIS)}, height={meta["height"]},\n'+
        '  bounds={min={'+numbers(lo)+'},max={'+numbers(hi)+'}},\n  sockets={'+sockets+'},\n'+
        '  pos={\n    '+block(pos,27)+'\n  },\n  nrm={\n    '+block(nrm,27)+'\n  },\n  uv={\n    '+block(uv,24)+'\n  },\n  col={\n    '+block(col,25)+'\n  },\n}\n')


def mesh_signature():
    return hashlib.sha256((OUT/'iron_sword.json').read_bytes()).hexdigest()


def tag_render(path, signature):
    # Store an invisible PNG text record; the comparison can detect stale views
    # even after a deterministic export has updated the JSON file timestamp.
    import struct
    import zlib
    png=path.read_bytes()
    assert png[-8:-4]==b'IEND'
    chunks=[]
    for key,value in [('IronSwordMesh',signature),('Renderer','BLENDER / CYCLES')]:
        data=(key+chr(0)+value).encode('ascii')
        record=b'tEXt'+data
        chunks.append(struct.pack('>I',len(data))+record+struct.pack('>I',zlib.crc32(record)))
    path.write_bytes(png[:33]+b''.join(chunks)+png[33:])


def procedurals(name,dark,light,metal,roughness,stretch,bump_distance):
    import bpy
    mat=bpy.data.materials.new(name)
    mat.use_nodes=True
    mat.diffuse_color=(*light,1)
    tree=mat.node_tree
    def node(kind,label,x,y):
        item=tree.nodes.new(kind)
        item.label=label
        item.location=(x,y)
        return item
    surface=tree.nodes['Principled BSDF']
    surface.location=(220,120)
    surface.inputs['Metallic'].default_value=metal
    tree.nodes['Material Output'].location=(530,120)
    coords=node('ShaderNodeTexCoord','Local metres',-900,80)
    scale=node('ShaderNodeVectorMath','Grain aspect',-710,80)
    scale.operation='MULTIPLY'
    scale.inputs[1].default_value=stretch
    tree.links.new(coords.outputs['Object'],scale.inputs[0])
    noise=node('ShaderNodeTexNoise','Continuous surface grain',-510,80)
    noise.inputs['Scale'].default_value=1
    noise.inputs['Detail'].default_value=2.4
    tree.links.new(scale.outputs[0],noise.inputs['Vector'])
    ramp=node('ShaderNodeValToRGB','Material colour variation',-260,260)
    for element,position,color in zip(ramp.color_ramp.elements,(.22,.78),(dark,light)):
        element.position=position
        element.color=(*color,1)
    tree.links.new(noise.outputs['Fac'],ramp.inputs['Fac'])
    tree.links.new(ramp.outputs['Color'],surface.inputs['Base Color'])
    rough=node('ShaderNodeMapRange','Microsurface roughness',-250,0)
    rough.inputs['To Min'].default_value=roughness[0]
    rough.inputs['To Max'].default_value=roughness[1]
    tree.links.new(noise.outputs['Fac'],rough.inputs['Value'])
    tree.links.new(rough.outputs['Result'],surface.inputs['Roughness'])
    relief=node('ShaderNodeBump','Microrelief in metres',-230,-235)
    relief.inputs['Distance'].default_value=bump_distance
    relief.inputs['Strength'].default_value=.16
    tree.links.new(noise.outputs['Fac'],relief.inputs['Height'])
    tree.links.new(relief.outputs['Normal'],surface.inputs['Normal'])
    return mat


def setup_blender():
    import bpy
    from mathutils import Vector
    sc=bpy.context.scene
    signature=mesh_signature()
    sc['IronSwordMesh']=signature
    steel=procedurals('Honed steel',(.45,.51,.60),(.53,.60,.71),.94,(.22,.34),(380,380,9),.000018)
    iron=procedurals('Burnished iron',(.24,.28,.34),(.35,.40,.47),.84,(.30,.45),(170,170,40),.000035)
    stone=procedurals('Carved grey stone',(.21,.24,.29),(.32,.36,.41),.12,(.50,.67),(205,205,205),.00015)
    hide=procedurals('Indigo leather',(.009,.018,.049),(.022,.046,.108),0,(.61,.79),(580,405,66),.00014)
    thong=procedurals('Indigo leather cord',(.004,.010,.027),(.014,.030,.064),0,(.68,.84),(450,450,85),.00012)
    seat=procedurals('Recessed bearing faces',(.045,.060,.076),(.088,.101,.122),.66,(.42,.53),(210,210,34),.000021)
    for part in dict.fromkeys(t['part'] for t in TRIS):
        tris=[t for t in TRIS if t['part']==part]
        verts=list(dict.fromkeys(p for t in tris for p in t['p']))
        idx={p:i for i,p in enumerate(verts)}
        mesh=bpy.data.meshes.new(part)
        mesh.from_pydata([(x,z,y) for x,y,z in verts],[],[[idx[p] for p in reversed(t['p'])] for t in tris])
        mesh.update()
        ob=bpy.data.objects.new(part,mesh)
        sc.collection.objects.link(ob)
        material={'Ridged steel blade':steel,'Carved crossguard':stone,'Leather grip core':hide,
                  'Five-turn leather binding':hide,'Cross-laced leather thong':thong}.get(part,iron)
        mesh.materials.append(material)
        if any(t['material']=='seat' for t in tris):
            mesh.materials.append(seat)
        uv=mesh.uv_layers.new(name='Submask and height')
        normals=[]
        for face,triangle in zip(mesh.polygons,tris):
            face.material_index=int(triangle['material']=='seat')
            face.use_smooth=material in (hide,thong)
            for loop,pair,normal in zip(face.loop_indices,reversed(triangle['uv']),reversed(triangle['n'])):
                uv.data[loop].uv=pair
                normals.append((normal[0],normal[2],normal[1]))
        mesh.normals_split_custom_set(normals)
    sc.unit_settings.system='METRIC'
    sc.render.engine='CYCLES'
    sc.cycles.device='CPU'
    sc.cycles.samples=32
    sc.cycles.use_denoising=True
    sc.world=bpy.data.worlds.new('Neutral studio')
    sc.world.use_nodes=True
    bg=sc.world.node_tree.nodes['Background']
    bg.inputs['Color'].default_value=(.40,.44,.52,1)
    bg.inputs['Strength'].default_value=.40
    # Broad and narrow rectangular emitters trace the long ridges. A darker
    # world between strips retains a dark reflection on the opposed facets.
    for name,loc,power,width,height,hue in [
        ('Front softbox',(-1.45,-1.8,1.45),90,1.05,3.4,(1,.97,.93)),
        ('Front strip',(1.9,-.85,.65),75,.42,3.0,(.84,.91,1)),
        ('Reverse softbox',(1.4,1.8,1.6),98,1.1,3.3,(1,.96,.90)),
        ('Reverse strip',(-1.8,.8,.38),78,.48,2.8,(.79,.88,1)),
        ('Top fill',(.1,-.35,2.9),24,1.0,1.3,(.93,.96,1))]:
        light=bpy.data.lights.new(name,'AREA')
        light.shape='RECTANGLE'
        light.energy=power
        light.size,light.size_y=width,height
        light.color=hue
        ob=bpy.data.objects.new(name,light)
        sc.collection.objects.link(ob)
        ob.location=loc
        ob.rotation_euler=(Vector((0,0,.54))-ob.location).to_track_quat('-Z','Y').to_euler()
    assert all(image.type in ('RENDER_RESULT','COMPOSITING') for image in bpy.data.images), 'Unexpected persistent image'
    sc.render.film_transparent=True
    sc.render.image_settings.color_mode='RGBA'
    sc.view_settings.view_transform='AgX'
    cam=bpy.data.cameras.new('Orthographic inspection')
    co=bpy.data.objects.new(cam.name,cam)
    sc.collection.objects.link(co)
    sc.camera=co
    cam.type='ORTHO'
    sc.render.resolution_percentage=100
    # Model-space zero is the grip. Use the same reference-space framing for
    # every measured projection, even though the source drawings differ a little.
    for name,direction in zip(('iso',*VIEWS),[(.69,-1,.19),(0,-1,0),(1,0,0),(0,1,0)]):
        target=Vector((0,0,(GRIP_Y-(HEIGHT-1)/2)*M))
        cam.ortho_scale=M*HEIGHT
        sc.render.resolution_x=WIDTH*2 if name!='iso' else 530
        sc.render.resolution_y=HEIGHT*2 if name!='iso' else 1300
        co.location=target+Vector(direction).normalized()*4
        co.rotation_euler=(target-co.location).to_track_quat('-Z','Y').to_euler()
        sc.render.filepath='//preview_'+name+'.png'
        if name=='iso':
            for area in bpy.context.screen.areas:
                if area.type=='VIEW_3D':
                    sp=area.spaces.active
                    sp.shading.color_type='MATERIAL'
                    sp.shading.light='STUDIO'
                    sp.overlay.show_overlays=False
                    sp.region_3d.view_rotation=co.rotation_euler.to_quaternion()
                    sp.region_3d.view_distance=2.7
                    sp.region_3d.view_location=target
                    sp.region_3d.view_perspective='ORTHO'
            bpy.context.preferences.filepaths.save_version=0
            bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'iron_sword.blend'))
        sc.render.filepath=str(OUT/f'preview_{name}.png')
        bpy.ops.render.render(write_still=True)
        tag_render(Path(sc.render.filepath),signature)


def intersects(left,right):
    # Non-coplanar segment/triangle crossings witness a physical joint between
    # two separately closed parts. Broad phase avoids testing distant triangles.
    low,high=right.min(axis=1),right.max(axis=1)
    for tri in left:
        targets=right[np.all((high>=tri.min(axis=0)) & (low<=tri.max(axis=0)),axis=1)]
        if not len(targets):
            continue
        e1,e2=targets[:,1]-targets[:,0],targets[:,2]-targets[:,0]
        for i,origin in enumerate(tri):
            direction=tri[(i+1)%3]-origin
            h=np.cross(direction,e2)
            det=(e1*h).sum(axis=1)
            live=np.abs(det)>1e-14
            det=np.where(live,det,1)
            offset=origin-targets[:,0]
            u=(offset*h).sum(axis=1)/det
            q=np.cross(offset,e1)
            v=(q*direction).sum(axis=1)/det
            distance=(e2*q).sum(axis=1)/det
            if np.any(live & (u>=0) & (v>=0) & (u+v<=1) & (distance>=0) & (distance<=1)):
                return True
    return False


def topology():
    data=json.loads((OUT/'iron_sword.json').read_text())
    tris=data['tris']
    assert 1200 <= len(tris) <= 2200 and data['meta']['height']==1.855
    for t in tris:
        points=np.array(t['p'])
        plane=np.cross(points[1]-points[0],points[2]-points[0])
        for n in t['n']:
            assert abs(np.linalg.norm(n)-1)<.0001 and n@plane>0
    assert all(t['glow']==0 and t['c'][2]==0 for t in tris)
    for part in dict.fromkeys(t['part'] for t in tris):
        faces=[[tuple(round(v*QUANT) for v in p) for p in t['p']] for t in tris if t['part']==part]
        links=defaultdict(list)
        edges=Counter()
        volume=0.
        for face in faces:
            a,b,c=np.array(face)
            assert np.any(np.cross(b-a,c-a)), (part,'degenerate',face)
            volume+=np.dot(a,np.cross(b,c))/6
            for i in range(3):
                p,q,r=face[i],face[(i+1)%3],face[(i+2)%3]
                edges[p,q]+=1
                links[p].append((q,r))
        assert volume>0 and all(v==1 and edges[q,p]==1 for (p,q),v in edges.items()),part
        for pairs in links.values():
            ring=dict(pairs)
            start=p=pairs[0][0]
            for _ in range(len(pairs)):
                p=ring.pop(p)
            assert p==start and not ring
        assert len(links)-len(edges)//2+len(faces)==2
        print(part, len(faces),'tris, oriented closed manifold, volume',volume/QUANT**3)
    shells={key:np.array([t['p'] for t in tris if t['part']==key])
            for key in dict.fromkeys(t['part'] for t in tris)}
    pending=[next(iter(shells))]
    attached=set(pending)
    while pending:
        key=pending.pop()
        for other in shells.keys()-attached:
            if intersects(shells[key],shells[other]) or intersects(shells[other],shells[key]):
                attached.add(other)
                pending.append(other)
    assert attached==shells.keys(), ('floating parts',shells.keys()-attached)
    print('All',len(shells),'closed parts form one physically attached assembly')
    normals=set()
    for t in tris:
        a,b,c=np.asarray(t['p'])
        n=np.cross(b-a,c-a)
        normals.add(tuple(np.round(n/np.linalg.norm(n),4)))
    assert {tuple(t['c']) for t in tris}=={(1,0,0),(0,1,0),(0,0,0)}
    assert {pair[0] for t in tris for pair in t['uv']}=={0,.35}
    assert all(abs(uv[1]-(p[1]-data['meta']['bounds']['min'][1])/1.855)<=.000051
               for t in tris for p,uv in zip(t['p'],t['uv']))
    blade_pts={tuple(p) for t in tris if t['part']=='Ridged steel blade' for p in t['p']}
    crests=[]
    for row,*_ in STATIONS:
        y=vertex((0,row,0))[1]
        ring=[p for p in blade_pts if p[1]==y and (p[0] or p[2])]
        assert len(ring)==16, (row,len(ring))
        crests.append(max(ring,key=lambda p:p[2]))
    diffs=[round(abs(a[2]-b[2])*1000,2) for a,b in zip(crests,crests[1:])]
    print('Rings:',len(crests),'x 16, adjacent crown heights (mm):',diffs)
    assert min(diffs)>=2 and all(a[0]!=b[0] for a,b in zip(crests,crests[1:]))
    print('Distinct unit normals rounded to 4 decimals:',len(normals))
    print(len(tris),'triangles;',data['meta']['height'],'m; zero degenerate faces, zero gem/glow')


def check_lua():
    from lupa.lua54 import LuaRuntime
    model=LuaRuntime().execute(LUA.read_text())
    data=json.loads((OUT/'iron_sword.json').read_text())
    tris=data['tris']
    assert model.name=='iron_sword' and model.scale==QUANT and model.triangles==len(tris)
    assert model.height==data['meta']['height']
    for key,point in data['meta']['sockets'].items():
        assert list(model.sockets[key].values())==point
    for key,point in data['meta']['bounds'].items():
        assert list(model.bounds[key].values())==point
    assert list(model.pos.values())==[round(v*QUANT) for t in tris for p in t['p'] for v in p]
    assert list(model.nrm.values())==[round(v*QUANT) for t in tris for n in t['n'] for v in n]
    assert list(model.uv.values())==[round(v*QUANT) for t in tris for pair in t['uv'] for v in pair]
    assert list(model.col.values())==[round(100*v) for t in tris for v in (*t['c'],t['shade'],t['glow'])]
    print('lupa.lua54 parsed and executed',model.name,'and every coordinate/material/socket matches JSON')


def projection():
    from PIL import Image,ImageDraw
    data=json.loads((OUT/'iron_sword.json').read_text())
    for view,ink in zip(VIEWS,ink_columns()):
        expected=Image.fromarray(ink.astype('uint8')*255).copy()
        ImageDraw.floodfill(expected,(0,0),128)
        truth=np.asarray(expected)!=128
        ss=4
        mask=Image.new('L',(WIDTH*ss,HEIGHT*ss))
        draw=ImageDraw.Draw(mask)
        for tri in data['tris']:
            pts=[]
            for x,y,z in tri['p']:
                lateral={'front':x,'side':z,'back':-x}[view]
                pts.append(((WIDTH/2+lateral/M)*ss,(GRIP_Y+.5-y/M)*ss))
            draw.polygon(pts,fill=255)
        pred=np.asarray(mask.resize((WIDTH,HEIGHT),Image.Resampling.BOX))>=128
        iou=(truth&pred).sum()/(truth|pred).sum()
        def span(m):
            row,col=np.where(m)
            return (col.max()-col.min()+1,row.max()-row.min()+1)
        a,b=span(truth),span(pred)
        print(view,'reference width/height px',tuple(map(int,a)),'mesh',tuple(map(int,b)),'IoU',round(iou,6))
        assert max(abs(u-v) for u,v in zip(a,b))<=6 and iou>=(.93 if view=='side' else .96)
    print('Model dimensions in metres:',np.subtract(data['meta']['bounds']['max'],data['meta']['bounds']['min']))


def compare():
    from PIL import Image,ImageDraw
    cols=ink_columns()
    rgb=reference_pixels().astype('uint8')
    sheet=Image.new('RGB',(WIDTH*6,HEIGHT+51),'#f2f3f5')
    draw=ImageDraw.Draw(sheet)
    for j,(name,col,c) in enumerate(zip(VIEWS,cols,CENTRES)):
        x=int(c+.5)-WIDTH//2
        ref=Image.fromarray(rgb[:,x:x+WIDTH])
        mask=Image.fromarray(col.astype('uint8')*255).copy()
        ImageDraw.floodfill(mask,(0,0),128)
        truth=np.asarray(mask)!=128
        with Image.open(OUT/f'preview_{name}.png') as rendered:
            if rendered.info.get('IronSwordMesh')!=mesh_signature():
                raise ValueError(f'{name} has no Blender render for the current mesh')
            if rendered.info.get('Renderer')!='BLENDER / CYCLES':
                raise ValueError(f'{name} needs a new Cycles material render')
            preview=rendered.convert('RGBA').resize((WIDTH,HEIGHT),Image.Resampling.LANCZOS)
        pred=np.asarray(preview)[:,:,3]>=128
        iou=np.count_nonzero(truth & pred)/np.count_nonzero(truth | pred)
        print(f'{name} IoU={iou:.6f} ref-only={np.count_nonzero(truth & ~pred)} render-only={np.count_nonzero(pred & ~truth)}')
        overlay=np.asarray(ref).copy()
        overlay[truth & ~pred]=(238,46,111)
        overlay[pred & ~truth]=(0,175,164)
        left=2*j*WIDTH
        sheet.paste(Image.fromarray(overlay),(left,26))
        sheet.paste(preview,(left+WIDTH,26),preview)
        draw.text((left+8,6),f'{name.upper()}   IoU {iou:.3%}',fill='#21304c')
        renderer=Image.open(OUT/f'preview_{name}.png').info.get('Renderer','BLENDER / CYCLES')
        draw.text((left+WIDTH+8,6),renderer,fill='#21304c')
        assert iou >= (.93 if name=='side' else .96), (name,iou)
    draw.text((8,HEIGHT+32),'Reference overlay:   pink = reference only     teal = render only',fill='#21304c')
    sheet.save(OUT/'overlay_comparison.png')


def build_mesh():
    OUT.mkdir(parents=True,exist_ok=True)
    cols=measure()
    blade(cols)
    guard()
    furniture(cols)
    grip(cols)
    export()
    print('Generated',len(TRIS),'triangles')


if __name__=='__main__':
    commands={'measure':measure,'export':build_mesh,'projection':projection,'compare':compare,'topology':topology,'lua':check_lua}
    if sys.argv[-1] in commands:
        commands[sys.argv[-1]]()
    else:
        import bpy
        bpy.ops.wm.read_factory_settings(use_empty=True)
        if sys.argv[-1]!='preview':
            import shutil
            import subprocess
            subprocess.run([shutil.which('python3') or '/usr/bin/python3',__file__,'export'],check=True)
        TRIS.extend(json.loads((OUT/'iron_sword.json').read_text())['tris'])
        for tri in TRIS:
            tri['p']=[tuple(p) for p in tri['p']]
        setup_blender()
