"""Generate the Warden Sword from the registered front, side and rear drawings.

Blender -b --factory-startup -P art/weapon_gen/warden_sword_blender.py
python3 art/weapon_gen/warden_sword_blender.py measure|export|topology|silhouette|lua|deterministic|compare
The text exports use grip-centred Y-up metres; the Blender scene is Z-up.
"""
from collections import defaultdict
import json
import math
from pathlib import Path
import sys

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
REF = ROOT / 'art/weapons_2d/rarity/warden_sword_4_threeview_v1.png'
OUT = HERE / 'out/warden_sword'
LUA = ROOT / 'scripts/combat/models/WardenSword.lua'
CENTRES = (415, 768, 1121)
NAMES = ('front', 'side', 'back')
GRIP_ROW = (602 + 700) / 2
TIP, END = 24, 786
UNIT = 1.855 / (END - TIP)
Q = 10000
W, H = 256, 864


def read_art():
    try:
        from PIL import Image
        return np.asarray(Image.open(REF).convert('RGBA'))
    except ImportError:  # Blender's bundled Python
        import OpenImageIO as oiio
        config = oiio.ImageSpec()
        config.attribute('oiio:UnassociatedAlpha',1)
        reader = oiio.ImageInput.open(str(REF),config)
        pixels = reader.read_image(format=oiio.UINT8)
        reader.close()
        return pixels


class Drawing:
    def __init__(self):
        self.mask = read_art()[:, :, 3] >= 128

    def runs(self, view, row):
        c = CENTRES[view]
        xs = np.flatnonzero(self.mask[row, c-100:c+101]) - 100
        return [(a[0], a[-1]) for a in np.split(xs, np.flatnonzero(np.diff(xs) > 1)+1) if len(a)]

    def radius(self, view, row):
        a, b = next(pair for pair in self.runs(view, row) if pair[0] <= 0 <= pair[1])
        return (b-a+1) / 2

    def width(self, row):
        return (self.radius(0, row) + self.radius(2, row)) / 2

    def quillon(self, x):
        edges = []
        for c in (CENTRES[0], CENTRES[2]):
            for sign in (-1, 1):
                col = self.mask[:, c+sign*x]
                top, bottom = 538, 538
                while top > 501 and col[top-1]:
                    top -= 1
                while bottom < 583 and col[bottom+1]:
                    bottom += 1
                edges.append((top-.5, bottom+.5))
        return np.mean(edges, axis=0)

    def registered_mask(self,view):
        axis=[(a+b)/2+CENTRES[view] for row in range(150,401)
              for a,b in self.runs(view,row) if a<=0<=b]
        left=round(np.median(axis)+.5)-W//2
        return self.mask[:,left:left+W]

    def measure(self):
        for i, c in enumerate(CENTRES):
            y, x = np.where(self.mask[:, c-100:c+101])
            print(NAMES[i], 'bounding box', (x.min()+c-100, y.min(), x.max()+c-100, y.max()))
        for row in [110, 123, 325, 440, 468, 496, 538, 578, 588, 650, 709, 740]:
            print('row', row, 'full widths (front, side, back)', [2*self.radius(i,row) for i in range(3)])


# All construction coordinates are (lateral px, source row, depth px).
# Each shell is welded, quantised and oriented before either format is written.
class Shell:
    def __init__(self, name):
        self.name, self.faces = name, []

    def face(self, points, material):
        for i in range(1, len(points)-1):
            self.faces.append(([points[0], points[i], points[i+1]], material))

    def bridge(self, a, b, materials):
        for i in range(max(len(a), len(b))):
            j = (i+1) % max(len(a), len(b))
            if len(a) == 1:
                points = [a[0], b[i], b[j]]
            elif len(b) == 1:
                points = [a[i], b[0], a[j]]
            else:
                points = [a[i], b[i], b[j], a[j]]
            self.face(points, materials[i % len(materials)])

    def loft(self, rings, materials, cap='steel'):
        for a, b in zip(rings, rings[1:]):
            self.bridge(a, b, materials)
        for ring in (rings[0], rings[-1]):
            if len(ring) > 2:
                if self.name in ('Gilt blade socket','Gold diamond pommel'):
                    centre = tuple(np.mean(ring,axis=0))
                    for i,p in enumerate(ring):self.face([p,ring[(i+1)%len(ring)],centre],cap)
                else:self.face(ring, cap)


def section(row, w, d, shoulder=.5, bevel=.69):
    return [(w*x, row, d*z) for x,z in [(1,0),(shoulder,bevel),(0,1),(-shoulder,bevel),
                                          (-1,0),(-shoulder,-bevel),(0,-1),(shoulder,-bevel)]]


# Elevation trace: row, bevel termination/width, ridge offset in pixels.
# Silhouette widths and depths at these stations come from all three alpha masks.
BLADE_TRACE = [(62,.43,-.45),(110,.48,.75),(155,.46,-.55),(235,.45,.72),
               (325,.48,-.70),(394,.70,.46),(419,.85,-.48),(448,.69,.52),
               (468,.34,-.60),(471,.35,.30),(480,.38,.44),(494,.45,-.43),(505,.46,.42),
               (516,.48,-.42),(523,.50,.45)]


def construct(ref):
    shells = []
    def shell(name):
        item = Shell(name)
        shells.append(item)
        return item

    blade = shell('Stepped steel blade')
    rings = [[(0,TIP,0)]]
    last_crown = None
    for row,knee,offset in BLADE_TRACE:
        w = ref.width(row) if row < 523 else 29
        envelope = ref.radius(1,row) * (1 if row <= 468 else .83)
        if row==471:
            w*=.86
            envelope*=.82
        crown = envelope
        if last_crown is not None and abs(crown-last_crown)*UNIT < .0021:
            crown = last_crown - .95 if last_crown >= envelope-.5 else last_crown+.95
        last_crown = crown
        # Eight principal planes. Two close-set ridges flank a shallow fuller.
        # The fuller closes almost completely in the point and under the socket.
        rise = 2.0 if row >= 448 else 3.1
        land = min(w*.115, 2.5) * (.48 if row<110 or row>494 else 1)
        trough = min(crown*.16, 1.7) * (.40 if row<110 or row>494 else 1)
        ring=[]
        for sign in (1,-1):
            half=[(w,0),(w*.93,crown*.17),(w*knee,crown-rise),
                  (offset+land,crown),(offset,crown-trough),(offset-land,crown-.12),
                  (-w*knee,crown-rise),(-w*.93,crown*.17)]
            for i,(x,z) in enumerate(half):
                y=row+13 if row==110 and i in (2,6) else row
                ring.append((sign*x,y,sign*z))
        rings.append(ring)
    blade_faces=['edge','steel','crown','steel','steel','crown','steel','edge']*2
    for upper,lower in zip(rings,rings[1:]):
        blade.bridge(upper,lower,['seat'] if lower[0][1]==471 else blade_faces)
    blade.face(rings[-1],'steel')

    guard = shell('Swept quillons')
    # x stations cross the concave upper and lower arches. The three interior
    # curves follow the steel/gold join, chased gold crease and lower gold lip.
    stations = [(0,562,571,580),(10,552,558,568),(22,537,544,551),
                (35,531,540,550),(53,523,536,553),
                (60,511,531,558),(73,526,539,548)]
    profiles = []
    for x, join, crease, lip in stations:
        top, bottom = ref.quillon(x)
        rows = [top, join, join+(crease-join)*.16,
                crease, crease+(lip-crease)*.85, lip, lip+(bottom-lip)*.62, bottom]
        profile = []
        for sign in (-1,1):
            side = []
            for row, fullness in zip(rows,[.27,.70,.78,.99,.81,.69,.52,.27]):
                # Local front-to-back taper relieves the centre socket and
                # preserves the broad, angular quillon ends in the side view.
                fraction = fullness * (.69+.27*x/73)
                if row >= 562 and x <= 10:
                    fraction = max(fraction, .98 if x == 0 else .84)
                d = ref.radius(1,round(row)) * fraction
                side.append((x,row,sign*d))
            profile.extend(side if sign == -1 else reversed(side))
        profiles.append(profile)
    mirrored = [[(-x,y,z) for x,y,z in ring] for ring in profiles[:0:-1]]
    profiles = [[(-84.5,538.5,0)]] + mirrored + profiles + [[(84.5,538.5,0)]]
    guard_bands=['steel','lip','gold','gold','lip','steel','rim']
    guard.loft(profiles,guard_bands+['rim']+guard_bands[::-1]+['rim'])

    # Double-faced heraldic socket, with separate steel bed, gilt border and
    # recessed navy face. Physical cuts continue around the four edges.
    boss = shell('Gilt blade socket')
    rings=[]
    for row,w,ratio in [(446,0,.99),(469,11.5,.99),(493,13,.99),
                         (513,17,.98),(528,25,.99),(545,13,.99),(563,0,.91)]:
        d = ref.radius(1,row)*ratio
        if w == 0:
            # A very narrow closed ring joins the front and back pinnacles.
            w=.65
        rings.append([(x*w,row,z*d) for x,z in [(1,0),(.65,.87),(.47,1),
                     (0,.97),(-.47,1),(-.65,.87),(-1,0),
                     (-.65,-.87),(-.47,-1),(0,-.97),(.47,-1),(.65,-.87)]])
    boss.loft(rings,['steel','gold','navy','navy','gold','steel']*2)

    def jewel(name, colour, top, middle, bottom, width, factor, side=False):
        # Two independent closed gems seat into opposite faces of the mount.
        for s in (-1,1):
            item = shell(name + (' B' if s > 0 else ' A'))
            def point(u, row, depth):
                return (s*depth,row,u) if side else (u,row,s*depth)
            rim=[]; girdle=[]; table=[]; inner_lip=[]; undercut=[]
            peak = ref.width(middle)*.985 if side else ref.radius(1,middle)
            for u,row in [(0,top),(width,middle),(0,bottom),(-width,middle)]:
                seat=(ref.width(row) if side else ref.radius(1,row))*factor
                rim.append(point(u*1.18,middle+(row-middle)*1.08,seat+.30))
                girdle.append(point(u,row,seat+.82))
                inner_lip.append(point(u*.96,middle+(row-middle)*.96,seat+1.18))
                undercut.append(point(u*.95,middle+(row-middle)*.96,seat-1.7))
                table.append(point(u*.39,middle+(row-middle)*.45,seat*.35+peak*.65+1.4))
            bezel=shell(item.name+' bezel')
            bezel.bridge(rim,inner_lip,['lip']);bezel.bridge(inner_lip,undercut,['gold'])
            bezel.bridge(undercut,rim,['gold'])
            # A closed pavilion supplies the exit surface for refraction and
            # volume absorption; its shoulder tucks into the gold retaining lip.
            item.loft([[point(0,middle,peak*.55)],girdle,table,
                       [point(0,middle,peak+2.4)]],[colour])
    jewel('Amber lozenge','amber',506,526,541,9,.94)

    def fitting(name, rows):
        item=shell(name)
        rings=[section(row,ref.width(row),ref.radius(1,row),.64,.77) for row in rows]
        item.loft(rings,['gold'],'gold')
    collar=shell('Crown ferrule')
    last=None
    for row,ratio,band in [(579,1,'gold'),(584,.89,'seat'),(586,1,'lip'),
                          (593,1,'gold'),(596,.89,'lip'),(602,.97,'seat')]:
        ring=section(row,ref.width(row)*ratio,ref.radius(1,row)*ratio,.64,.77)
        if last: collar.bridge(last,ring,[band])
        else: collar.face(ring,'gold')
        last=ring
    collar.face(last,'seat')
    fitting('Pommel ferrule',[699,703,709,715])

    # Slight swell at the grip centre. A separate continuous twisted band has
    # six bevels across its section; its underside is embedded in the leather.
    grip=shell('Indigo leather grip')
    w,d=ref.width(650),ref.radius(1,650)
    grip_rows=(600,616,638,659,685,702)
    radii=(.91,.94,.97,.97,.94,.91)
    rings=[]
    for row,r in zip(grip_rows,radii):
        rings.append([(w*r*math.cos(i*math.tau/12),row,d*r*math.sin(i*math.tau/12)) for i in range(12)])
    grip.loft(rings,['leather'],'leather')
    cord=shell('Continuous bias binding')
    rings=[]
    for i in range(43):
        t=i/42; row=600+102*t; angle=-math.tau*4.25*t
        r=np.interp(row,grip_rows,radii)
        ring=[]
        for radial,dy in [(-.10,-1.45),(.005,-1.85),(.085,-.72),(.082,.70),(.01,1.8),(-.10,1.5)]:
            ring.append((w*(r+radial)*math.cos(angle),row+dy,d*(r+radial)*math.sin(angle)))
        rings.append(ring)
    cord.loft(rings,['leather','rib','rib','rib','leather','leather'],'rib')

    pommel=shell('Gold diamond pommel')
    # Four recessed stone seats; the raised gold rails either side of the
    # side-setting carry the silhouette even where its sapphire projects out.
    rings=[]
    for row in (713,740):
        w,d=ref.width(row),ref.radius(1,row)
        profile=[(.80,0),(1,.25),(.68,.67),(.39,1),(0,.78),
                 (-.39,1),(-.68,.67),(-1,.25)]
        rings.append([(sign*x*w,row,sign*z*d) for sign in (1,-1) for x,z in profile])
    pommel.loft(rings+[[(0,END,0)]],['gold'],'gold')
    jewel('Pommel sapphire','sapphire',717,740,761,9.2,.86)
    jewel('Edge sapphire','sapphire',719,740,758,6,.98,True)
    return shells


def oriented(shell):
    vertices, lookup, faces, mats = [], {}, [], []
    for tri, mat in shell.faces:
        ids=[]
        for x,row,z in tri:
            p=tuple(round(t*UNIT*Q) for t in (x,GRIP_ROW-row,z))
            if p not in lookup:
                lookup[p]=len(vertices);vertices.append(p)
            ids.append(lookup[p])
        faces.append(ids); mats.append(mat)
    edges=defaultdict(list)
    for i,f in enumerate(faces):
        for a,b in zip(f,f[1:]+f[:1]):
            edges[tuple(sorted((a,b)))].append((i,a<b))
    links=defaultdict(list)
    for edge,pair in edges.items():
        assert len(pair)==2,(shell.name,edge,pair)
        (a,sa),(b,sb)=pair
        links[a].append((b,sa==sb));links[b].append((a,sa==sb))
    flips={0:False}; stack=[0]
    while stack:
        i=stack.pop()
        for j,parity in links[i]:
            expected=flips[i]^parity
            if j not in flips:
                flips[j]=expected;stack.append(j)
            assert flips[j]==expected
    assert len(flips)==len(faces)
    faces=[f[::-1] if flips[i] else f for i,f in enumerate(faces)]
    verts=np.asarray(vertices,dtype=float)/Q
    t=verts[faces]
    if np.einsum('ij,ij->',t[:,0],np.cross(t[:,1],t[:,2]))<0:
        faces=[f[::-1] for f in faces]
    return verts,faces,mats


# Channel weights remain categorical (sRGB conversion applies to face tone).
# Amber and sapphire both use the gem band; their heights distinguish the mounts.
MATERIALS = {
    # runtime weight, submask, face tone, glow, Blender sRGB, metal, roughness
    'edge':    ((1,0,0),0,.99,0,(.93,.96,.99),.82,.19),
    'steel':   ((1,0,0),0,.88,0,(.70,.77,.85),.80,.31),
    'crown':   ((1,0,0),0,.95,0,(.85,.90,.96),.84,.24),
    'seat': ((1,0,0),0,.51,0,(.22,.245,.30),.65,.49),
    'rim':     ((1,0,0),.35,.59,0,(.25,.34,.46),.66,.37),
    'navy':    ((1,0,0),.35,.72,0,(.27,.35,.49),.72,.31),
    'gold':    ((0,1,0),0,.89,0,(.81,.63,.36),.72,.38),
    'lip':     ((0,1,0),0,.99,0,(.95,.80,.51),.75,.28),
    'leather': ((0,0,0),0,.91,0,(.105,.15,.27),0,.78),
    'rib':     ((0,0,0),0,.99,0,(.19,.25,.40),0,.65),
    'amber':   ((0,0,1),1,.94,.12,(1,.57,.10),0,.13),
    'sapphire':((0,0,1),1,.94,.12,(.06,.48,.91),0,.12),
}


def csv(values):
    return ','.join(map(str,values))


def block(values,step):
    return ',\n    '.join(csv(values[i:i+step]) for i in range(0,len(values),step))


def export(pieces):
    tris=[]
    for part,vertices,faces,mats in pieces:
        for f,kind in zip(faces,mats):
            tri=vertices[f];weights,mask,shade,glow=MATERIALS[kind][:4]
            tris.append(dict(p=tri.tolist(),c=weights,shade=shade,glow=glow,part=part.name,
                             uv=[[mask,round((p[1]-(round((GRIP_ROW-END)*UNIT,4)))/1.855,6)] for p in tri]))
    points=np.array([t['p'] for t in tris]).reshape(-1,3)
    low,high=points.min(axis=0).tolist(),points.max(axis=0).tolist()
    sockets=dict(grip=[0,0,0],tip=[0,high[1],0],bladeBase=[0,round((GRIP_ROW-468)*UNIT,4),0],pommel=[0,low[1],0])
    meta=dict(height=round(high[1]-low[1],4),bounds=dict(min=low,max=high),sockets=sockets)
    (OUT/'warden_sword.json').write_text(json.dumps(dict(meta=meta,tris=tris),separators=(',',':'))+'\n')
    pos=np.rint(points.reshape(-1)*Q).astype(int).tolist()
    col=[round(v*100) for t in tris for v in (*t['c'],t['shade'],t['glow'])]
    uv=[round(v*1000000) for t in tris for pair in t['uv'] for v in pair]
    fields = ['-- Generated by art/weapon_gen/warden_sword_blender.py. Grip-centred metres.','return {',
              '  name="warden_sword", scale=10000, uvScale=1000000, triangles=%d, height=%.4f,' % (len(tris),meta['height']),
              '  bounds={min={'+csv(low)+'},max={'+csv(high)+'}},',
              '  sockets={'+','.join(k+'={'+csv(v)+'}' for k,v in sockets.items())+'},']
    for k,arr,step in [('pos',pos,27),('col',col,25),('uv',uv,24)]:
        fields.extend(['  '+k+'={','    '+block(arr,step),'  },'])
    LUA.write_text('\n'.join(fields+['}','']))
    print('exported',len(tris),'triangles',meta['height'],'metres')
    return meta,tris


def prepare():
    OUT.mkdir(parents=True,exist_ok=True)
    ref=Drawing(); pieces=[(part,*oriented(part)) for part in construct(ref)]
    meta,tris=export(pieces)
    return pieces,meta,tris


def studio_material(bpy, kind, props):
    rgb,metal,rough = props[4:]
    linear = tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb)
    mat=bpy.data.materials.new(kind.title());mat.use_nodes=True
    mat.diffuse_color=(*linear,1);mat.metallic=metal;mat.roughness=rough
    tree=mat.node_tree; links=tree.links
    surface=tree.nodes.get('Principled BSDF'); surface.location=(330,100)
    surface.inputs['Metallic'].default_value=metal
    surface.inputs['Roughness'].default_value=rough
    def node(type_name,label,x,y):
        n=tree.nodes.new(type_name);n.label=label;n.location=(x,y);return n
    coords=node('ShaderNodeTexCoord','Model-space coordinates',-960,110)
    mapping=node('ShaderNodeVectorMath','Physical grain scale',-750,110);mapping.operation='MULTIPLY'
    leather=kind in ('leather','rib');crystal=kind in ('amber','sapphire')
    mapping.inputs[1].default_value=(420,420,370) if leather else ((18,18,17) if crystal else (960,960,65))
    links.new(coords.outputs['Object'],mapping.inputs[0])
    noise=node('ShaderNodeTexNoise','Grain' if not crystal else 'Internal colour variation',-545,110)
    noise.inputs['Scale'].default_value=1;noise.inputs['Detail'].default_value=2.4
    links.new(mapping.outputs['Vector'],noise.inputs['Vector'])
    ramp=node('ShaderNodeValToRGB','Material tint',-300,230)
    dark,light=(.65,1.13) if leather else ((.68,1.18) if crystal else (.92,1.04))
    for e,f,pos in zip(ramp.color_ramp.elements,(dark,light),(.18,.82)):
        e.position=pos;e.color=(*[min(1,v*f) for v in linear],1)
    links.new(noise.outputs['Fac'],ramp.inputs['Fac']);links.new(ramp.outputs[0],surface.inputs['Base Color'])
    if crystal:
        surface.inputs['IOR'].default_value=1.55 if kind=='amber' else 1.77
        surface.inputs['Transmission Weight'].default_value=.73 if kind=='amber' else .82
        surface.inputs['Coat Weight'].default_value=.18
        volume=node('ShaderNodeVolumeAbsorption','Colour through the cut',320,-240)
        volume.inputs['Color'].default_value=(*linear,1);volume.inputs['Density'].default_value=5 if kind=='amber' else 8
        links.new(volume.outputs[0],tree.nodes.get('Material Output').inputs['Volume'])
    else:
        # The BRDF supplies Fresnel. Grains modulate both finish and micro-relief.
        finish=node('ShaderNodeMapRange','Surface finish',-50,35)
        finish.inputs['To Min'].default_value=rough-.065;finish.inputs['To Max'].default_value=rough+.065
        links.new(noise.outputs['Fac'],finish.inputs['Value']);links.new(finish.outputs['Result'],surface.inputs['Roughness'])
        bump=node('ShaderNodeBump','Leather pores' if leather else 'Brushed finish',-40,-150)
        bump.inputs['Strength'].default_value=.24 if leather else .09
        bump.inputs['Distance'].default_value=.00034 if leather else .000075
        links.new(noise.outputs['Fac'],bump.inputs['Height']);links.new(bump.outputs['Normal'],surface.inputs['Normal'])
        if leather:surface.inputs['Sheen Weight'].default_value=.19
    return mat


def setup_studio(bpy,scene):
    from mathutils import Vector
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=32
    scene.cycles.use_denoising=True;scene.cycles.seed=19
    scene.cycles.max_bounces=8;scene.cycles.transmission_bounces=6
    scene.render.film_transparent=True;scene.render.image_settings.color_mode='RGBA'
    scene.view_settings.view_transform='AgX'
    world=bpy.data.worlds.new('Soft neutral bounce');world.use_nodes=True;scene.world=world
    sky=world.node_tree.nodes.get('Background');sky.inputs['Color'].default_value=(.72,.78,.87,1)
    sky.inputs['Strength'].default_value=.40
    # Tall strip boxes reflect continuously through the long sweeps. Front and
    # back have separate keys so all orthographic cameras can use the same rig.
    for label,pos,power,tint,width,height in [
        ('Silver key',(-1.25,-1.7,1.5),125,(.86,.93,1),.78,2.8),
        ('Warm return',(1.52,-1.2,.32),85,(1,.87,.70),.42,2.3),
        ('Rear softbox',(.80,1.8,1.25),168,(.87,.94,1),1.2,2.5),
        ('Rear strip',(-1.5,.98,.15),70,(1,.9,.77),.36,1.9),
        ('Crown light',(0,-.55,2.75),60,(1,.96,.87),1.15,1.15)]:
        lamp=bpy.data.lights.new(label,'AREA');lamp.shape='RECTANGLE'
        lamp.energy=power;lamp.color=tint;lamp.size=width;lamp.size_y=height
        ob=bpy.data.objects.new(label,lamp);scene.collection.objects.link(ob);ob.location=pos
        ob.rotation_euler=(Vector((0,0,.51))-ob.location).to_track_quat('-Z','Y').to_euler()


def build():
    import bpy
    from mathutils import Vector
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    pieces,meta,tris=prepare()
    low,high=meta['bounds'].values()
    scene=bpy.context.scene
    scene.unit_settings.system='METRIC'
    materials={kind:studio_material(bpy,kind,props) for kind,props in MATERIALS.items()}
    cursor=0
    for part,vertices,faces,mats in pieces:
        mesh=bpy.data.meshes.new(part.name)
        mesh.from_pydata(vertices[:,[0,2,1]].tolist(),[],[f[::-1] for f in faces]);mesh.update()
        ob=bpy.data.objects.new(part.name,mesh);scene.collection.objects.link(ob)
        slots=list(dict.fromkeys(mats))
        for kind in slots:mesh.materials.append(materials[kind])
        uv=mesh.uv_layers.new(name='Material mask and height')
        channels=mesh.color_attributes.new(name='Forge channels',type='FLOAT_COLOR',domain='CORNER')
        for poly,kind in zip(mesh.polygons,mats):
            face=tris[cursor];cursor+=1;poly.material_index=slots.index(kind)
            poly.use_smooth=part.name in ('Indigo leather grip','Continuous bias binding')
            for loop,pair in zip(poly.loop_indices,reversed(face['uv'])):
                uv.data[loop].uv=pair
                channels.data[loop].color=(*face['c'],face['shade'])
    assert all(img.name=='Render Result' for img in bpy.data.images)
    assert all(node.type!='TEX_IMAGE' for mat in materials.values() for node in mat.node_tree.nodes)
    print('PASS blend image inventory:',list(bpy.data.images.keys()),'; zero image texture nodes')
    setup_studio(bpy,scene)
    scene.render.resolution_x=W*2;scene.render.resolution_y=H*2;scene.render.resolution_percentage=100
    cam=bpy.data.cameras.new('Elevation');cam.type='ORTHO';cam.ortho_scale=H*UNIT
    eye=bpy.data.objects.new('Inspection camera',cam);scene.collection.objects.link(eye);scene.camera=eye
    target=Vector((0,0,(GRIP_ROW+.5-H/2)*UNIT))
    for area in bpy.context.screen.areas:
        if area.type=='VIEW_3D':
            space=area.spaces.active;space.shading.color_type='MATERIAL';space.overlay.show_overlays=False
            space.region_3d.view_perspective='ORTHO';space.region_3d.view_distance=2.9
            space.region_3d.view_location=target;space.region_3d.view_rotation=Vector((-.55,1,-.06)).to_track_quat('-Z','Y')
    for label,offset in [('iso',(2.35,-3.8,.42)),('front',(0,-4,0)),('side',(4,0,0)),('back',(0,4,0))]:
        if label=='iso':
            cam.ortho_scale=2.09;scene.render.resolution_x=800;scene.render.resolution_y=1400
            target.z=(low[1]+high[1])/2
        else:
            cam.ortho_scale=H*UNIT;scene.render.resolution_x=W*2;scene.render.resolution_y=H*2
            target.z=(GRIP_ROW+.5-H/2)*UNIT
        eye.location=target+Vector(offset);eye.rotation_euler=(-Vector(offset)).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath='//preview_'+label+'.png'
        if label=='iso':bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'warden_sword.blend'))
        scene.render.filepath=str(OUT/('preview_'+label+'.png'))
        bpy.ops.render.render(write_still=True)
    # Validate the saved native file after every camera has rendered.
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'warden_sword.blend'))
    scene=bpy.context.scene
    assert scene.render.engine=='CYCLES' and len(bpy.data.lights)==5
    assert all(i.name=='Render Result' for i in bpy.data.images)
    assert all(n.type!='TEX_IMAGE' for m in bpy.data.materials if m.node_tree for n in m.node_tree.nodes)
    count=sum(len(o.data.polygons) for o in scene.objects if o.type=='MESH');assert count==len(tris)
    print('PASS reloaded native Cycles scene:',count,'triangles, five area lights, zero image textures')


def silhouette():
    """Project the exported positions at 4x; no material or scene data used."""
    from PIL import Image,ImageDraw
    ref=Drawing(); tris=json.loads((OUT/'warden_sword.json').read_text())['tris']
    for i,c in enumerate(CENTRES):
        mask=Image.new('L',(W*4,H*4));draw=ImageDraw.Draw(mask)
        for tri in tris:
            points=[]
            for x,y,z in tri['p']:
                u=(x,z,-x)[i]
                points.append((4*(W/2+u/UNIT),4*(GRIP_ROW+.5-y/UNIT)))
            draw.polygon(points,fill=255)
        pred=np.asarray(mask.resize((W,H),Image.Resampling.BOX))>=128
        a=ref.registered_mask(i)
        score=(pred&a).sum()/(pred|a).sum()
        print(NAMES[i],round(score,6),'reference pixels',a.sum(),'mesh pixels',pred.sum())
        assert score >= (.93 if i==1 else .96),NAMES[i]


def compare():
    from PIL import Image,ImageDraw
    drawing=Drawing();sheet=Image.new('RGB',(3*W,H+90),'#202633');draw=ImageDraw.Draw(sheet)
    for i,c in enumerate(CENTRES):
        # Fix horizontal registration from the straight blade only. The same
        # translation is applied to every row; no rescaling or mask fitting.
        ref=drawing.registered_mask(i)
        with Image.open(OUT/('preview_'+NAMES[i]+'.png')) as pic:
            pred=np.asarray(pic.getchannel('A').resize((W,H),Image.Resampling.BOX))>=128
        score=(ref&pred).sum()/(ref|pred).sum()
        print('%s %.6f  reference=%d, rendered=%d, intersection=%d, union=%d' %
              (NAMES[i],score,ref.sum(),pred.sum(),(ref&pred).sum(),(ref|pred).sum()))
        assert score >= (.93 if i==1 else .96),NAMES[i]
        arr=np.zeros((H,W,3),dtype='uint8');arr[:]=[29,34,45];arr[ref&pred]=[190,201,213]
        arr[ref&~pred]=[255,144,52];arr[pred&~ref]=[52,201,231]
        sheet.paste(Image.fromarray(arr),(i*W,56));draw.text((i*W+12,20),NAMES[i].upper()+'  %.2f%%'%(100*score),fill='white')
    draw.text((12,H+66),'GREY  overlap       ORANGE  reference only       CYAN  mesh only',fill='white')
    sheet.save(OUT/'overlay_comparison.png')


def verify():
    data=json.loads((OUT/'warden_sword.json').read_text());groups=defaultdict(list)
    for t in data['tris']:groups[t['part']].append(t['p'])
    assert 1500<=len(data['tris'])<=2200
    assert data['meta']['height']==1.855 and data['meta']['sockets']['grip']==[0,0,0]
    for name,triangles in groups.items():
        edges=defaultdict(list);links=defaultdict(lambda:defaultdict(set));area_min=math.inf;vol=0
        for tri in triangles:
            a,b,c=np.asarray(tri);area_min=min(area_min,np.linalg.norm(np.cross(b-a,c-a))/2)
            vol+=np.dot(a,np.cross(b,c))/6
            tri=list(map(tuple,tri))
            for i,p in enumerate(tri):
                q,r=tri[(i+1)%3],tri[(i+2)%3];edges[tuple(sorted((p,q)))].append(p<q)
                links[p][q].add(r);links[p][r].add(q)
        assert all(sorted(e)==[False,True] for e in edges.values()),name
        for neighbors in links.values():
            assert all(len(n)==2 for n in neighbors.values()),name
            seen=set();stack=[next(iter(neighbors))]
            while stack:
                u=stack.pop()
                if u not in seen:seen.add(u);stack.extend(neighbors[u]-seen)
            assert len(seen)==len(neighbors),name
        assert area_min>1e-12 and vol>0,(name,area_min,vol)
        print(name,len(triangles),'faces; smallest area',area_min,'signed volume',vol)
    # The link condition above verifies each vertex. Euler characteristic and
    # a graph walk also reject accidentally concatenated shells within a part.
        assert len(links)-len(edges)+len(triangles)==(0 if name.endswith(' bezel') else 2),name
        seen=set();stack=[next(iter(links))]
        while stack:
            point=stack.pop()
            if point not in seen:seen.add(point);stack.extend(links[point].keys()-seen)
        assert len(seen)==len(links),name
    ts=np.asarray([t['p'] for t in data['tris']]);n=np.cross(ts[:,1]-ts[:,0],ts[:,2]-ts[:,0]);n/=np.linalg.norm(n,axis=1)[:,None]
    blade=np.asarray(groups['Stepped steel blade']);verts=list(dict.fromkeys(map(tuple,blade.reshape(-1,3))))
    last=None; min_step=math.inf
    for row,_,_ in BLADE_TRACE:
        rings=[p for p in verts if abs(p[1]-(GRIP_ROW-row)*UNIT)<.00006
               or (row==110 and abs(p[1]-(GRIP_ROW-123)*UNIT)<.00006)]
        assert len(rings)==16,(row,len(rings))
        p=max(rings,key=lambda p:p[2])
        if last is not None:
            min_step=min(min_step,abs(p[2]-last[2]));assert p[0]!=last[0] and min_step>=.002-1e-8,row
        last=p
    print('Measured',len(BLADE_TRACE),'16-sided blade stations; minimum crown change',round(min_step*1000,2),'mm')
    print('Distinct face normals (components rounded to four decimals):',len(np.unique(n.round(4),axis=0)))
    print('PASS',len(groups),'closed orientable manifold shells;',len(data['tris']),'faces; zero degenerates')


def lua_check():
    from lupa import LuaRuntime
    data=json.loads((OUT/'warden_sword.json').read_text());m=LuaRuntime().execute(LUA.read_text())
    assert m.name=='warden_sword' and m.scale==Q and m.triangles==len(data['tris']) and m.height==data['meta']['height']
    for field,n in [('pos',9),('col',5),('uv',6)]:assert len(m[field])==m.triangles*n
    for i,t in enumerate(data['tris']):
        assert [m.pos[i*9+j+1] for j in range(9)]==[round(v*Q) for a in t['p'] for v in a]
        assert [m.col[i*5+j+1] for j in range(5)]==[round(v*100) for v in (*t['c'],t['shade'],t['glow'])]
        assert [m.uv[i*6+j+1] for j in range(6)]==[round(v*m.uvScale) for a in t['uv'] for v in a]
    for key,values in data['meta']['sockets'].items():assert list(m.sockets[key].values())==values
    for key,values in data['meta']['bounds'].items():assert list(m.bounds[key].values())==values
    print('PASS lupa loaded Lua model; every coordinate, palette weight, shade, glow, UV, bound and socket matches JSON')


def deterministic():
    from hashlib import sha256
    paths=[OUT/'warden_sword.json',LUA]
    def hashes():return [sha256(p.read_bytes()).hexdigest() for p in paths]
    prepare();first=hashes();prepare();assert hashes()==first
    for p,digest in zip(paths,first):print(digest,p.name)
    print('PASS two complete mesh generations, byte-identical JSON and Lua')


if __name__=='__main__':
    commands={'measure':lambda:Drawing().measure(),'compare':compare,'silhouette':silhouette,'topology':verify,'lua':lua_check,
              'export':prepare,'deterministic':deterministic}
    if len(sys.argv)==2 and sys.argv[1] in commands:commands[sys.argv[1]]()
    else:build()
