"""Silver bow, measured on the original 1536 x 864 orthographic drawing.

Blender -b --factory-startup -P art/weapon_gen/silver_bow_blender.py
Add -- export-only for a deterministic geometry rebuild without rendering.
System python3 with Pillow, scipy and numpy handles measurements and the overlay.
python3 art/weapon_gen/silver_bow_blender.py measure|export|topology|lua|compare|compare-mesh|check-scene
"""
from pathlib import Path
import json
import math
import subprocess
import sys

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = HERE / 'out/silver_bow'
REF = ROOT / 'art/weapons_2d/rarity/silver_bow_1_threeview_v1.png'
PACKED = ROOT / 'assets/model/forge-blades/SilverBow.mesh.json'
RAW = OUT / 'silver_bow_game.json'
HEIGHT, GRIP_X, GRIP_Y = 811., 349., 454.
# (crop centre, top and bottom sheet landmarks, sheet X of grip)
COLUMNS = {'left': (370, 25, 836, 349), 'front': (770, 14, 845, 769.5),
           'right': (1167, 25, 836, 1188)}
WIDTH, IMAGE_H = 290, 864


def reference_masks():
    from PIL import Image
    from scipy import ndimage
    a = np.asarray(Image.open(REF).convert('RGB'), dtype=int)
    assert a.shape == (864, 1536, 3)
    backdrop = np.median(a[:, :160], axis=1)[:, None, :]
    masks = {}
    for view, (cx, *_) in COLUMNS.items():
        rgb = a[:, cx-WIDTH//2:cx+WIDTH//2]
        ink = (rgb[:, :, 0] < 185) | (rgb[:, :, 2]-rgb[:, :, 0] > 28)
        labels, _ = ndimage.label(~ink)
        area = np.bincount(labels.ravel())
        paper = np.max(np.abs(rgb-backdrop), axis=2) < 6
        hits = np.bincount(labels.ravel(), weights=paper.ravel())
        empty = (area > 3) & (hits/np.maximum(area, 1) > .76)
        empty[0] = False
        masks[view] = ~empty[labels]
    return masks


def measure():
    for view, mask in reference_masks().items():
        cx = COLUMNS[view][0]
        ys, xs = np.where(mask)
        print(view, 'bounds inclusive', (xs.min()+cx-WIDTH//2, ys.min(), xs.max()+cx-WIDTH//2, ys.max()))
        for y in [25, 53, 95, 109, 143, 198, 228, 264, 305, 345, 372, 405, 435, 454, 480, 510, 540, 570, 608, 645, 695, 725, 750, 800, 835]:
            transitions = np.diff(np.r_[False, mask[y], False].astype(int))
            runs = np.flatnonzero(transitions).reshape(-1, 2)+cx-WIDTH//2
            print(y, [(int(x), int(end-1)) for x, end in runs])


def compare_mesh():
    """Compare the packed LOD independently of the renderer; never consume older stills."""
    from PIL import Image,ImageDraw
    model=json.loads(PACKED.read_text());images={}
    for name,(cx,top,bot,gx) in COLUMNS.items():
        ppm=bot-top;canvas=Image.new('L',(WIDTH*4,IMAGE_H*4));draw=ImageDraw.Draw(canvas)
        for part in ('body','crystal','string'):
            g=model[part];v=np.asarray(g['v']).reshape(-1,13)[:,:3]/10000;idx=np.asarray(g['i']).reshape(-1,3)-1
            horiz=-v[:,0] if name=='front' else v[:,2]*(-1 if name=='left' else 1)
            projected=np.column_stack((WIDTH/2+gx-cx+horiz*ppm,top+ppm*((GRIP_Y-25)/HEIGHT-v[:,1])))*4
            for triangle in projected[idx]:draw.polygon([tuple(p) for p in triangle],fill=255)
        images[name]=np.asarray(canvas.resize((WIDTH,IMAGE_H),Image.Resampling.BOX))>=128
    compare(images)


def compare(images=None):
    from PIL import Image, ImageDraw, ImageFont
    canvas = Image.new('RGB', (3*WIDTH, IMAGE_H+70), '#e9eaf0')
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 21)
    masks=reference_masks();both=masks['left'] & masks['right'][:,::-1];either=masks['left'] | masks['right'][:,::-1]
    threshold=both.sum()/either.sum()-.03;scores={}
    for i,(view,mask) in enumerate(masks.items()):
        if images is None:
            rgba = Image.open(OUT / f'preview_{view}.png').convert('RGBA')
            silhouette = np.asarray(rgba)[:,:,3]>=128
        else: silhouette=images[view]
        score = (mask & silhouette).sum() / (mask | silhouette).sum();scores[view]=score
        print(f'{view} reference={mask.sum()} rendered={silhouette.sum()} IoU={score:.6f}')
        colors = np.full((*mask.shape, 3), (233, 234, 240), dtype=np.uint8)
        colors[mask & silhouette] = (55, 67, 91)
        colors[mask & ~silhouette] = (205, 74, 84)
        colors[silhouette & ~mask] = (0, 150, 163)
        canvas.paste(Image.fromarray(colors), (i*WIDTH, 70))
        draw.text((i*WIDTH+20, 10), f'{view.capitalize()}   {score:.1%}', fill='#262e42', font=font)
    for x, color, label in [(20, '#37435b', 'Overlap'), (180, '#cd4a54', 'Reference only'), (415, '#0096a3', 'Model only')]:
        draw.rectangle((x, 47, x+12, 59), fill=color)
        draw.text((x+20, 39), label, fill='#262e42', font=font)
    path=OUT/'overlay_comparison.png'
    draw.text((605,39),'Packed mesh' if images is not None else 'Blender render',fill='#262e42',font=font)
    print('Side reference ceiling',threshold+.03,'side minimum',threshold,'front minimum',.96)
    assert scores['front']>=.96 and min(scores['left'],scores['right'])>=threshold, scores
    canvas.save(path)


def verify():
    from collections import Counter
    data = json.loads(PACKED.read_text())
    raw = json.loads(RAW.read_text())
    assert (data['name'], data['formatVersion'], data['vertexStride'],
            data['scale'], data['nscale']) == ('silver_bow', 1, 13, 10000, 1000)
    assert data['height'] == 1 and data['sockets']['grip'] == [0, 0, 0] and data['sockets']['stringZ'] < 0
    total = 0
    directions = set()
    for part in ('body', 'crystal', 'string'):
        item = data[part]
        v = np.asarray(item['v']).reshape(-1, 13)
        inds = np.asarray(item['i']).reshape(-1, 3)-1
        rows = np.asarray(raw['parts'][part])
        assert rows.shape == (3*len(inds), 13) and np.isfinite(rows).all()
        assert item['triangles'] == len(inds) and v.dtype.kind == 'i' and inds.min() == 0 and inds.max() == len(v)-1
        q = v[inds]
        pos, norm = q[:, :, :3], q[:, :, 3:6]
        geom = np.cross(pos[:, 1]-pos[:, 0], pos[:, 2]-pos[:, 0])
        directions.update(map(tuple,v[:,3:6]))
        areas=np.linalg.norm(geom,axis=1)*.005
        print(part,'maximum triangle area mm2',round(max(areas),3))
        assert max(areas)<=300 and set(v[:,11]) <= {0,3500,10000}
        assert np.allclose(v[:,12]/10000, v[:,1]/10000-data['bounds']['min'][1],atol=.00016)
        dot = (geom*norm.sum(axis=1)).sum(axis=1)
        assert dot.min() > 0 and np.all(np.abs(np.linalg.norm(norm, axis=2)-1000) < 1.1), (part, dot.min())
        # Count components by welded position, independently of material/normal splits.
        parents = {}
        edges = Counter()

        def root(k):
            while parents[k] != k:
                parents[k] = parents[parents[k]]
                k = parents[k]
            return k
        for tri in pos:
            keys = [tuple(p) for p in tri]
            for p in keys:
                parents.setdefault(p, p)
            for a, b in zip(keys, keys[1:]+keys[:1]):
                parents[root(a)] = root(b)
                edges[tuple(sorted((a, b)))] += 1
        count = len({root(k) for k in parents})
        assert set(edges.values()) == {2}, (part, Counter(edges.values()))
        assert count == 1, (part, count)
        signed_volume = (pos[:, 0]*geom).sum()/6e12
        assert signed_volume > 0
        print(part, len(inds), 'triangles, one closed surface; minimum winding dot',
              dot.min(), 'signed volume', signed_volume)
        total += len(inds)

    def positions(part):
        group = data[part]
        v = np.reshape(group['v'], (-1, 13))[:, :3]/10000
        return v[np.reshape(group['i'], (-1, 3))-1]
    body = positions('body')

    def inside(point):
        a, b, c = (body-point).transpose(1, 0, 2)
        la, lb, lc = (np.linalg.norm(q, axis=1) for q in (a, b, c))
        num = np.einsum('ij,ij->i', a, np.cross(b, c))
        den = la*lb*lc+(a*b).sum(1)*lc+(b*c).sum(1)*la+(c*a).sum(1)*lb
        return abs(np.arctan2(num, den).sum()) > math.pi
    cord = np.unique(positions('string').reshape(-1, 3), axis=0)
    for y in [cord[:, 1].min(), cord[:, 1].max()]:
        assert inside(cord[cord[:, 1] == y].mean(axis=0)), 'Unseated nock'
    gem = np.unique(positions('crystal').reshape(-1, 3), axis=0)
    inside_count = sum(inside(pt) for pt in gem)
    assert 0 < inside_count < len(gem)
    print('Packed bud intersects wood; both cord ends are inside their nocks.')
    assert 2000 <= total <= 3200
    inn = np.concatenate([np.asarray(raw['parts'][p])[:, :3] for p in raw['parts']])
    assert np.allclose(inn.min(axis=0), data['bounds']['min'], atol=.000051) and np.allclose(
        inn.max(axis=0), data['bounds']['max'], atol=.000051)
    print('Distinct packed normal directions',len(directions),'sweeps',raw['sweeps'])
    print('PASS schema, finite values, indices, winding, welded junctions, range, bounds, sockets; triangles', total)


def at(x, d, y):
    return ((x-GRIP_X)/HEIGHT, -d/HEIGHT, (GRIP_Y-y)/HEIGHT)


def obj_mesh(name, vertices, faces, mat):
    points = np.asarray(vertices, dtype=float)
    triangles = np.asarray([(face[0], face[k], face[k+1]) for face in faces for k in range(1, len(face)-1)])
    corners = points[triangles]
    if np.einsum('ij,ij->', corners[:, 0], np.cross(corners[:, 1], corners[:, 2])) < 0:
        triangles = triangles[:, ::-1].copy()
    return points, triangles


STATIONS = {}


def profile(name, stations, mat, sides=10, spacing=2, lens=False):
    """Horizontal sections (sheet row, side centre, front offset, side and front half-widths).
    Shape-preserving cubic Hermite interpolation avoids overshoot at narrow shoot tips.
    """
    STATIONS[name] = (len(stations), sides)
    p = np.asarray(sorted(stations), dtype=float)
    t = p[:, 0]
    values = p[:, 1:]
    ds = np.diff(t)
    slopes = np.diff(values, axis=0)/ds[:, None]
    m = np.zeros_like(values)
    m[0] = slopes[0]
    m[-1] = slopes[-1]
    for j in range(1, len(p)-1):
        a, b = slopes[j-1], slopes[j]
        same = a*b > 0
        m[j, same] = (3*(ds[j-1]+ds[j]))/((2*ds[j]+ds[j-1])/a[same]+(ds[j]+2*ds[j-1])/b[same])
    ys = sorted(set(t).union(np.arange(t[0], t[-1], spacing)))
    verts = []
    faces = []
    prev = []
    for y in ys:
        j = min(np.searchsorted(t, y, side='right')-1, len(t)-2)
        u = (y-t[j])/ds[j]
        x, d, rx, rd = ((2*u**3-3*u*u+1)*values[j]+(u**3-2*u*u+u)*ds[j]*m[j] +
                        (-2*u**3+3*u*u)*values[j+1]+(u**3-u*u)*ds[j]*m[j+1])
        ring = []
        for k in range(1 if min(rx, rd) < 1e-6 else sides):
            ang = k*2*math.pi/sides
            cs = math.cos(ang)
            sn = math.sin(ang)
            if lens or (name == 'Crown to heel' and (y < 111 or y > 748)):
                cs = math.copysign(abs(cs)**1.38, cs)
                sn = math.copysign(abs(sn)**1.50, sn)
            ring.append(len(verts))
            verts.append(at(x+rx*cs, d+rd*sn, y))
        if prev:
            for k in range(sides):
                q = (k+1) % sides
                if len(prev) == 1:
                    faces.append((prev[0], ring[q], ring[k]))
                elif len(ring) == 1:
                    faces.append((prev[k], prev[q], ring[0]))
                else:
                    faces.append((prev[k], prev[q], ring[q], ring[k]))
        elif len(ring) > 1:
            faces.append(tuple(reversed(ring)))
        prev = ring
    if len(prev) > 1:
        faces.append(tuple(prev))
    return obj_mesh(name, verts, faces, mat)


def wood_shapes():
    shapes = []

    def shoot(name, data, leaf=False):
        shapes.append(profile(name, data, wood, 12, lens=leaf))
    # Each limb changes depth as it turns across the grip. Separate silhouettes and
    # paired front-view shoots merge into the same remeshed surface at their collars.
    shoot('Crown to heel', [(25, 454, 0, 0, 0), (42, 454, 0, 6, 5), (64, 447, 0, 16, 13), (79, 440, 0, 18, 14), (95, 428, 0, 13, 10), (111, 423, -3, 8, 8), (142, 414, -5, 11, 9), (163, 405, -6, 10, 7), (184, 394, -5, 13, 9), (211, 370, -5, 16, 9), (237, 340, -3, 17, 10), (256, 314, 1, 15, 13), (278, 294, 3, 12, 10), (300, 290, 6, 16, 8), (320, 298, 8, 18, 9), (342, 322, 7, 17, 10), (362, 341, 3, 14, 11), (383, 352, -2, 13, 12), (402, 356, -6, 15, 12), (416, 348, -3, 15, 12), (437, 329, 5,
          10, 10), (457, 325, 8, 8, 8), (473, 350, 8, 10, 9), (482, 357, 4, 9, 10), (501, 346, 1, 14, 11), (519, 335, -7, 15, 11), (540, 320, -19, 12, 11), (564, 317, -24, 11, 10), (587, 321, -22, 12, 10), (609, 335, -13, 12, 9), (632, 352, -7, 15, 10), (650, 365, -3, 16, 11), (674, 390, -4, 14, 9), (692, 402, -2, 13, 9), (707, 411, 0, 10, 7), (731, 417, 0, 7, 8), (753, 421, 0, 8, 9), (772, 429, 0, 18, 15), (788, 437, 0, 21, 17), (803, 441, 0, 16, 14), (820, 447, 0, 6, 8), (836, 444, 0, 0, 0)])
    shoot('Bough crossing the upper limb', [(104, 455, 0, 0, 0), (109, 450, 0, 13, 6), (119, 448, 0, 21, 9), (131, 444, 1, 21, 10), (147, 429, 4, 16, 9), (166, 410, 6, 13, 8), (195, 385, 6, 14, 8), (216, 365, 7, 15, 10), (
        243, 341, 6, 15, 12), (262, 325, 7, 11, 9), (281, 316, 5, 10, 8), (301, 314, -1, 10, 10), (319, 318, -8, 11, 9), (338, 330, -10, 11, 9), (353, 343, -7, 11, 10), (368, 351, -3, 9, 8), (392, 355, 0, 4, 5)])
    shoot('Lower return and nock', [(469, 350, -4, 4, 4), (486, 346, -7, 10, 8), (504, 340, -5, 13, 11), (520, 326, 7, 15, 12), (534, 305, 17, 17, 12), (550, 296, 23, 17, 11), (570, 294, 25, 17, 10), (585, 300, 23,
          18, 10), (602, 315, 18, 18, 11), (623, 338, 10, 16, 10), (644, 360, 6, 16, 10), (666, 382, 4, 15, 9), (688, 408, 3, 15, 9), (705, 430, 2, 16, 8), (717, 444, 0, 13, 7), (728, 456, 0, 9, 4), (739, 474, 0, 0, 0)])
    # Axial leaf visible through the lower fork; the wide cheeks frame a central ridge.
    shoot('Lower spindle leaf', [(505, 336, 0, 2, 2), (530, 319, 0, 5, 3), (552, 307, 0, 10, 12),
          (579, 303, 0, 12, 17), (602, 321, 0, 12, 14), (628, 344, 0, 10, 4), (640, 355, 0, 3, 2)], True)
    for sign in (-1, 1):
        def pair(name, data): shoot(name+str(sign), [(y, x, d*sign, a, b) for y, x, d, a, b in data], True)
        pair('Crown spearlet', [(53, 389, 19, 0, 0), (66, 404, 16, 9, 3), (80, 409, 14, 10, 5),
             (93, 417, 9, 5, 5), (109, 421, 3, 4, 4), (121, 421, 1, 3, 3)])
        pair('Crown secondary fork', [(95, 383, 25, 0, 0), (114, 392, 24, 6, 4),
             (131, 402, 18, 6, 7), (149, 406, 10, 7, 5), (168, 405, 5, 5, 4)])
        pair('Upper lateral buds', [(198, 300, 19, 0, 0), (213, 307, 20, 9, 8), (226, 308, 22, 13, 10),
             (235, 309, 23, 9, 9), (244, 311, 21, 5, 9), (254, 311, 16, 5, 8), (272, 307, 7, 6, 5)])
        pair('Upper collar bracts', [(338, 351, 28, 0, 0), (347, 347, 24, 6, 5),
             (359, 346, 19, 9, 6), (380, 351, 7, 6, 5), (395, 355, 4, 3, 3)])
        pair('Lower lateral buds', [(580, 317 if sign < 0 else 298, 22, 4, 4), (592, 306 if sign < 0 else 301, 19, 6, 5), (
            603, 291, 23, 8, 5), (609, 283, 29, 12, 7), (620, 281, 31, 15, 8), (632, 279, 29, 9, 5), (648, 281, 22, 0, 0)])
        pair('Heel forklets', [(680, 395, 3, 7, 4), (697, 400, 7, 7, 5), (711, 398, 12, 6, 6),
             (726, 394, 18, 7, 6), (738, 385, 22, 8, 4), (753, 369, 24, 0, 0)])
        pair('Heel spearlet', [(735, 418, 2, 7, 4), (752, 417, 7, 7, 4),
             (770, 409, 13, 9, 5), (787, 409, 16, 6, 4), (803, 416, 18, 0, 0)])
    shoot('Upper swept thorn', [(341, 305, 4, 7, 3), (345, 307, 6, 17, 5),
          (350, 302, 8, 18, 4), (351.7, 283, 9, 0, 0)])
    shoot('Lower swept thorn', [(607, 360, -6, 0, 0), (620, 366, -8, 4, 3),
          (636, 371, -8, 5, 5), (653, 376, -4, 6, 5), (663, 384, -1, 4, 3)])
    # Swelling directly behind the cord rather than an unsupported string endpoint.
    for name, data in [('Upper nock', [(133, 448, 0, 4, 3), (145, 447.5, 0, 4.5, 4), (165, 447.5, 0, 3, 2.8)]), ('Lower nock', [(694, 447.5, 0, 3, 2.8), (706, 448, 0, 5, 4), (714, 447, 0, 4, 4)])]:
        shoot(name, data)
    # The cup grows from the exposed spine on the target side of the wrapped grip.
    shoot('Bud stem', [(396, 320, 0, 1, 2), (409, 319, 0, 5, 6), (425, 321, 0, 6, 9),
          (438, 325, 0, 7, 10), (453, 325, 2, 7, 9), (462, 330, 3, 3, 4)])
    for s in (-1, 1):
        shoot('Calyx wing '+str(s), [(407, 286, 39*s, 0, 0), (411, 291, 33*s, 9, 6), (415, 290, 28*s, 17, 9),
              (419, 300, 24*s, 15, 9), (425, 309, 18*s, 11, 8), (434, 319, 9*s, 6, 7), (443, 326, 5*s, 5, 6)], True)
        shoot('Calyx lancet '+str(s), [(390, 332, 25*s, 0, 0), (401, 325, 22*s, 5, 3),
              (412, 321, 17*s, 7, 5), (428, 321, 8*s, 5, 6), (441, 324, 3*s, 4, 5)], True)
    return shapes


def wrapped_core():
    # A ridged continuous sleeve. The cut of the spiral is geometry and survives export.
    vertices = []
    faces = []
    rings = 76
    sides = 32
    for j in range(rings+1):
        u = j/rings
        y = 411+98*u
        cx = 349+1.8*math.sin(math.pi*2*u)
        for k in range(sides):
            a = 2*math.pi*k/sides
            phase = (6.7*u-k/sides) % 1
            ridge = 2.55*math.sin(math.pi*phase)**.65 - 2.1*math.exp(-((phase-.03)/.065)**2)
            r = 11.3+ridge+2.6*(2*u-1)**2
            vertices.append(at(cx+(r+.6)*math.cos(a), r*math.sin(a), y))
            if j:
                i = j*sides+k
                n = j*sides+(k+1) % sides
                faces.append((i-sides, n-sides, n, i))
    faces += [tuple(range(sides))[::-1], tuple(range(rings*sides, (rings+1)*sides))]
    return obj_mesh('Spiral grip', vertices, faces, cloth)


def camera(name, direction, centre, scale):
    cd = bpy.data.cameras.new(name)
    cd.type = 'ORTHO'
    cd.ortho_scale = scale
    cd.sensor_fit = 'VERTICAL'
    cd.clip_start = .01
    ob = bpy.data.objects.new(name, cd)
    scene.collection.objects.link(ob)
    ob.location = Vector(centre)+Vector(direction).normalized()*3
    ob.rotation_euler = (-Vector(direction)).to_track_quat('-Z', 'Y').to_euler()
    return ob


def studio():
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 42
    scene.cycles.use_denoising = False
    scene.render.film_transparent = True
    scene.render.image_settings.color_mode = 'RGBA'
    scene.view_settings.view_transform = 'AgX'
    world = bpy.data.worlds.new('Pearl studio')
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get('Background')
    setin(bg, 0, (.57, .65, .87, 1))
    setin(bg, 1, .42)
    for name, loc, energy, color, size in [('Pearl softbox', (-1.6, -1.8, 2.1), 140, (1, .96, .93), 1.3), ('Opposite pearl', (-1.3, 1.9, 1), 108, (.86, .92, 1), 1.1), ('Silver edge', (1.4, .1, .5), 125, (.79, .85, 1), .8)]:
        light = bpy.data.lights.new(name, 'AREA')
        light.energy = energy
        light.color = color
        light.shape = 'DISK'
        light.size = size
        ob = bpy.data.objects.new(name, light)
        scene.collection.objects.link(ob)
        ob.location = loc
        ob.rotation_euler = (-Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    cams = {}
    for name, (cx, top, bottom, gx) in COLUMNS.items():
        ppm = bottom-top
        midz = (GRIP_Y-25)/HEIGHT-(IMAGE_H/2-top)/ppm
        if name == 'front':
            centre = (0, (gx-cx)/ppm, midz)
            direction = (-1, 0, 0)
        else:
            sign = 1 if name == 'left' else -1
            centre = ((cx-gx)*sign/ppm, 0, midz)
            direction = (0, -sign, 0)
        cams[name] = camera(name, direction, centre, IMAGE_H/ppm)
    cams['iso'] = camera('Three-quarter', (-.84, -1.12, .23), (.022, 0, .018), 1.09)
    return cams


def fit_projections():
    """Fit the mesh, not the cameras: smooth cross-section corrections in sheet pixels.
    The paired side views share an average outline. All parts receive the same field.
    """
    from PIL import Image, ImageDraw
    from scipy.ndimage import gaussian_filter, map_coordinates
    shapes = [(np.asarray(v), np.asarray(f, dtype=int)) for v, f in json.load(sys.stdin)]
    masks = reference_masks()

    def boundaries(row):
        return np.flatnonzero(np.diff(np.r_[False, row, False].astype(int))).reshape(-1, 2)
    for name, axis, sign in [('left', 0, 1), ('front', 1, -1)]:
        cx, top, bot, gx = COLUMNS[name]
        ppm = bot-top
        centre = WIDTH/2+gx-cx
        # The reflected right crop has the same centre relative to the registered grip.
        refs = [masks[name]] if name == 'front' else [masks['left'], masks['right'][:, ::-1]]
        for iteration in range(4):
            image = Image.new('L', (2*WIDTH, 2*IMAGE_H))
            draw = ImageDraw.Draw(image)

            def screen(v):
                return centre+sign*ppm*v[:, axis], top+ppm*((GRIP_Y-25)/HEIGHT-v[:, 2])
            for verts, faces in shapes:
                proj = np.column_stack(screen(verts))*2
                for tri in proj[faces]:
                    draw.polygon([tuple(pt) for pt in tri], fill=255)
            raster = np.asarray(image.resize((WIDTH, IMAGE_H), Image.Resampling.BOX)) >= 128
            delta = np.zeros((IMAGE_H, WIDTH))
            columns = np.arange(WIDTH)
            for y in range(IMAGE_H):
                actual = boundaries(raster[y])
                goals = [boundaries(ref[y]) for ref in refs]
                if not len(actual) or any(not len(x) for x in goals):
                    continue
                xs = [0]
                ds = [0]
                for lo, hi in actual:
                    a = np.array([lo, hi])
                    matches = []
                    for g in goals:
                        # Do not associate a narrow thorn with the adjacent main limb.
                        near = g[np.argmin(np.abs(g-a).sum(axis=1))]
                        # When two drawing lobes merge at this row, preserve both extremes.
                        over=g[(g[:,0]<hi-1)&(g[:,1]>lo+1)]
                        if len(over)>1:near=np.array((over[0,0],over[-1,1]))
                        if len(g)!=len(actual) and len(over)==1 and (near[1]-near[0])>1.8*(hi-lo):
                            near=np.clip(a,near[0],near[1])
                        matches.append(near)
                    b = np.mean(matches, axis=0)
                    if name=='front':
                        if lo==actual[0,0]:b[0]=goals[0][0,0]
                        if hi==actual[-1,1]:b[1]=goals[0][-1,1]
                    d = np.clip(b-a, -11, 11)
                    if name == 'left' and 166 < y < 694 and lo > 215:
                        d[:] = 0
                    if name!='front' and max(abs(b-a)) > 19:
                        continue
                    # Keep changing depth maps monotonic across tiny gaps.
                    for x, dx in zip(a, d):
                        if x > xs[-1]:
                            xs.append(x)
                            ds.append(dx)
                xs.append(WIDTH)
                ds.append(0)
                delta[y] = np.interp(columns, xs, ds)
            delta = gaussian_filter(delta, (3.8, 2.4))
            slope = np.diff(delta, axis=1).min(axis=1)
            delta *= np.minimum(1, .60/np.maximum(-slope, .01))[:, None]
            for verts, _ in shapes:
                x, y = screen(verts)
                offset = map_coordinates(delta, [y, x], order=1, mode='nearest')
                # Cord and its two seats share the original fixed nock axis.
                side_x = GRIP_X+verts[:, 0]*HEIGHT
                side_y = GRIP_Y-verts[:, 2]*HEIGHT
                pinned = (np.abs(side_x-447.5) < 9) & (side_y > 139) & (side_y < 716)
                offset[pinned] = 0
                verts[:, axis] += .84*sign*offset/ppm
    json.dump([v.tolist() for v, _ in shapes], sys.stdout)


def finish_contours():
    """Fit the visible edge intersections of the actual LOD to the sheet scanlines.
    Each observation is a linear combination of its two edge vertices. Edge-difference
    regularization carries the boundary correction smoothly around the back of a branch.
    """
    from scipy.sparse import coo_matrix
    from scipy.sparse.linalg import lsqr
    shapes=json.load(sys.stdin);pts=np.concatenate([a for a,b in shapes]);off=0;faces=[]
    for v,f in shapes:
        faces.extend(np.asarray(f)+off);off+=len(v)
    faces=np.asarray(faces);edges=np.unique(np.sort(np.concatenate([faces[:,[0,1]],faces[:,[1,2]],faces[:,[2,0]]]),axis=1),axis=0)
    pts[:,2]=(pts[:,2]-pts[:,2].min())/np.ptp(pts[:,2])+(GRIP_Y-836)/HEIGHT
    masks=reference_masks()
    for view,axis,sign in [('left',0,1),('front',1,-1)]:
        cx,top,last,gx=COLUMNS[view];ppm=last-top; y=top+ppm*((GRIP_Y-25)/HEIGHT-pts[:,2]);corners=y[faces]
        scans=[]
        for row in range(top+1,last):
            ordinate=row+.5; subset=faces[(corners.min(1)<ordinate)&(corners.max(1)>ordinate)]
            if not len(subset):continue
            ea=subset[:,[0,1,2]];eb=subset[:,[1,2,0]];cross=(y[ea]<ordinate)!=(y[eb]<ordinate);a=ea[cross].reshape(-1,2);b=eb[cross].reshape(-1,2)
            u=(ordinate-y[a])/(y[b]-y[a]);refs=[masks[view][row]] if view=='front' else [masks['left'][row],masks['right'][row,::-1]]
            runs=[np.flatnonzero(np.diff(np.r_[False,r,False].astype(int))).reshape(-1,2) for r in refs]
            if all(len(r) for r in runs):scans.append((a,b,u,runs))
        for iteration in range(4):
            x=WIDTH*.5+gx-cx+sign*pts[:,axis]*ppm
            ii=[];jj=[];vv=[];rhs=[]
            def equation(ids,coeffs,target):
                ii.extend([len(rhs)]*len(ids));jj.extend(ids);vv.extend(coeffs);rhs.append(target)
            for a,b,u,runs in scans:
                loc=(1-u)*x[a]+u*x[b];ordering=np.argsort(loc,axis=1);left=loc.min(1);right=loc.max(1);order=np.argsort(left);groups=[]
                for i in order:
                    if not groups or left[i]>groups[-1][1]+.65:groups.append([left[i],right[i],i,i])
                    elif right[i]>groups[-1][1]:groups[-1][1]=right[i];groups[-1][3]=i
                for j,(lo,hi,i0,i1) in enumerate(groups):
                    match=[g[np.argmin(np.abs(g-[lo,hi]).sum(1))] for g in runs];l,r=np.mean(match,axis=0)
                    if j==0:l=np.mean([g[0,0] for g in runs])
                    if j==len(groups)-1:r=np.mean([g[-1,1] for g in runs])
                    for side,(i,residual) in enumerate([(i0,l-lo),(i1,r-hi)]):
                        if any(len(g)!=len(groups) for g in runs) and not (side==0 and j==0 or side==1 and j==len(groups)-1):continue
                        if abs(residual)>12:continue
                        k=ordering[i,side];w=u[i,k];equation([a[i,k],b[i,k]],[1-w,w],np.clip(residual,-4,4))
            for i,j in edges:equation([i,j],[.77,-.77],0)
            for i,pt in enumerate(pts):
                side_x=GRIP_X+pt[0]*HEIGHT;side_y=GRIP_Y-pt[2]*HEIGHT
                pin=350 if abs(side_x-447.5)<5 and 143<side_y<713 else .32
                equation([i],[pin],0)
            matrix=coo_matrix((vv,(ii,jj)),shape=(len(rhs),len(pts))).tocsr()
            delta=lsqr(matrix,rhs,iter_lim=120)[0];pts[:,axis]+=.80*sign*np.clip(delta,-4,4)/ppm
    offset=0;out=[]
    for v,_ in shapes:out.append(pts[offset:offset+len(v)].tolist());offset+=len(v)
    json.dump(out,sys.stdout)


def limit_face_area(verts,faces,centres):
    """Split both incident triangles at the longest edge, preserving the closed shell."""
    while True:
        triangles=verts[faces];area=np.linalg.norm(np.cross(triangles[:,1]-triangles[:,0],triangles[:,2]-triangles[:,0]),axis=1)*.5
        worst=int(np.argmax(area))
        if area[worst] <= .000255:return verts, faces, centres
        poly=faces[worst];k=np.argmax(np.linalg.norm(verts[poly]-verts[np.roll(poly,-1)],axis=1));a,b=poly[k],poly[(k+1)%3]
        i=len(verts);verts=np.vstack((verts,(verts[a]+verts[b])/2));new_faces=[];new_centres=[]
        for j in np.flatnonzero((faces==a).any(1)&(faces==b).any(1)):
            old=faces[j].copy();k=next(t for t in range(3) if {old[t],old[(t+1)%3]}=={a,b});p,q,r=np.roll(old,-k)
            faces[j]=[p,i,r];new_faces.append([i,q,r]);new_centres.append(centres[j])
        faces=np.vstack((faces,new_faces));centres=np.vstack((centres,new_centres))


def verify_lua():
    """Drive the shipping module through the real frame cursor. Capture engine calls."""
    from lupa.lua54 import LuaRuntime
    lua=LuaRuntime(unpack_returned_tuples=True);m=json.loads(PACKED.read_text());seen={p:[] for p in ('body','crystal','string')}
    lua.globals().decode=lambda text:lua.table_from(json.loads(text),recursive=True)
    lua.globals().raw=PACKED.read_text();lua.globals().capture=lambda part,*values:seen[part].append(values)
    lua.execute('''
    cjson={decode=decode};TRIANGLE_LIST=1
    function Vector3(...) return {...} end; Vector2=Vector3;Color=Vector3;Variant=function(a)return a end
    local mat={}; function mat:Clone()return self end; function mat:Dispose()end;function mat:SetShaderParameter()end
    cache={GetFile=function(_,path)assert(path=='model/forge-blades/SilverBow.mesh.json');return {ReadString=function()return raw end,Close=function()end}end,GetResource=function()return mat end}
    function Node(name)
        local n={};function n:CreateChild(k)return Node(k)end;function n:Remove()end
        function n:CreateComponent()
            local g={};function g:SetNumGeometries(count)assert(count==2)end
            function g:BeginGeometry(i)self.part=name=='silver_bow_string' and 'string' or i==1 and 'crystal' or 'body'end
            function g:DefineVertex(p)self.p=p end;function g:DefineNormal(v)self.n=v end;function g:DefineColor(c)self.c=c end
            function g:DefineTexCoord(uv)local p,n,c=self.p,self.n,self.c;capture(self.part,p[1],p[2],p[3],n[1],n[2],n[3],c[1],c[2],c[3],c[4],uv[1],uv[2])end
            function g:Commit()end;function g:SetMaterial()return true end;return g
        end;return n
    end''')
    lua.globals().visual=lua.execute((ROOT/'scripts/combat/SilverBowVisual.lua').read_text());lua.execute('''local v=assert(visual.New(Node('root'),.5));local frames=0
    repeat frames=frames+1;assert(frames<64) until visual.Step(v);assert(frames>3);visual.SetVisible(v,true);visual.SetStringVisible(v,false);assert(v.node.enabled and not v.stringNode.enabled);visual.SetBend(v,.1);visual.Dispose(v)''')
    for name,values in seen.items():
        part=m[name];rows=np.reshape(part['v'],(-1,13))[np.array(part['i'])-1];expected=rows[:,[0,1,2,3,4,5,6,7,8,9,11,12]]/np.array([10000]*3+[1000]*3+[100]*4+[10000]*2)
        assert np.array_equal(np.asarray(values),expected),name
        print(name,len(values),'uploaded positions, normals, RGBA and UV identical to packed JSON')


def volume_geometry():
    """Fuse all the living wood and cloth into one exterior using Blender's OpenVDB.
    This stage can also run in the bundled Python without requiring a display driver.
    """
    import openvdb as vdb
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(HERE))
    from thornbow_export import build
    OUT.mkdir(parents=True, exist_ok=True)
    global wood, cloth
    wood = 'wood'
    cloth = 'cloth'
    pieces = wood_shapes()
    grip = wrapped_core()
    transform = vdb.createLinearTransform(voxelSize=1.65/HEIGHT)

    def level_set(piece):
        vertices, indices = piece
        return vdb.FloatGrid.createLevelSetFromPolygons(np.ascontiguousarray(vertices, dtype='f'), np.ascontiguousarray(indices, dtype='I'), transform=transform)
    grip_grid = level_set(grip)
    grid = grip_grid.deepCopy()
    for piece in pieces:
        grid.combine(level_set(piece), min)
    sample = grid.getAccessor()
    grip_sample = grip_grid.getAccessor()

    def distance(point, access):
        return access.getValue(tuple(round(i) for i in transform.worldToIndex(tuple(point))))
    for xyz in [(447.5, 0, 154), (447.5, 0, 707), (321, 0, 423)]:
        dist = distance(at(*xyz), sample)
        print('Contact', xyz, dist, flush=True)
        assert dist < 0

    def surface(adaptivity):
        vs, tr, qu = grid.convertToPolygons(adaptivity=adaptivity)
        faces = np.concatenate((tr, qu[:, [0, 1, 2]], qu[:, [0, 2, 3]]))
        return vs, faces
    v, f = surface(1.0)
    print('Adaptive minimum', len(f), flush=True)
    if len(f) < 2540:
        lo, hi = 0., 1.
        for _ in range(10):
            m = (lo+hi)/2
            verts, indices = surface(m)
            if len(indices) > 2540:
                lo = m
            else:
                hi = m
                v, f = verts, indices

    # Ignore sub-voxel interior cavities produced where smooth shells overlap.
    # A detached twig is much larger and raises an authoring error here.
    parent = list(range(len(v)))

    def root(i):
        while i != parent[i]:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for a, b, c in f:
        parent[root(a)] = root(b)
        parent[root(c)] = root(b)
    groups = np.array([root(int(face[0])) for face in f])
    main = np.bincount(groups).argmax()
    for key in set(groups)-{main}:
        span = np.ptp(v[f[groups == key]].reshape(-1, 3), axis=0).max()*HEIGHT
        assert span < 6, f'Detached branch: {span:.1f} pixels'
    f = f[groups == main]
    print('Body prior to simplification', len(f), flush=True)

    gem = profile('Ice bud', [(367, 295, 0, 0, 0), (382, 302, 0, 10, 12), (393, 306, 0, 14, 19), (405,
                  311, 0, 14, 20), (417, 318, 0, 8, 12), (426, 321, 0, 1, 2)], 'ice', 8, spacing=1000, lens=True)
    string = profile('Cord', [(150, 447.5, 0, 2.1, 1.4), (707, 447.5, 0, 2.1, 1.4)], 'cord', 8, spacing=100)
    raw = {'parts': {}, 'stats': {}, 'sweeps': STATIONS}
    zmin, zmax = v[f, 2].min(), v[f, 2].max()
    # Transfer the calibrated correction to every piece, including both nocks.
    shapes = []
    source_centres = []
    for verts, faces in [(v, f), gem, string]:
        used, inv = np.unique(faces, return_inverse=True)
        verts = verts[used].astype(float)
        faces = inv.reshape(-1, 3)
        source_centres.append(verts[faces].mean(axis=1))
        verts[:, 2] = (verts[:, 2]-zmin)/(zmax-zmin)+(GRIP_Y-836)/HEIGHT
        shapes.append((verts, faces))
    payload = json.dumps([(vs.tolist(), fs.tolist()) for vs, fs in shapes])
    fitted = json.loads(subprocess.check_output(
        ['python3', str(Path(__file__).resolve()), 'fit'], input=payload, text=True))
    reduced=[];source_centres_final=[]
    for name, coords, (_, faces), centres in zip(('body', 'crystal', 'string'), fitted, shapes, source_centres):
        verts = np.asarray(coords)
        source_verts = shapes[('body','crystal','string').index(name)][0].copy()
        source_verts[:,2]=(source_verts[:,2]-(GRIP_Y-836)/HEIGHT)*(zmax-zmin)+zmin
        if name=='body':
            verts,faces,source_verts=simplify(verts,faces,2540,source_verts)
        centres=source_verts[faces].mean(axis=1)
        used,inv=np.unique(faces,return_inverse=True)
        reduced.append((verts[used].tolist(),inv.reshape(-1,3).tolist()));source_centres_final.append(centres)
    shaped=json.loads(subprocess.check_output(['python3',str(Path(__file__).resolve()),'polish'],input=json.dumps(reduced),text=True))
    for name,coords,(_,inds),centres in zip(('body','crystal','string'),shaped,reduced,source_centres_final):
        verts,faces,centres=limit_face_area(np.asarray(coords),np.asarray(inds),centres)
        verts = verts[:, [1, 2, 0]].copy()
        verts[:, 2] *= -1
        # Pack and weld first so both outputs use the exact same surface and normals.
        # Keep distinct vertices distinct on the export lattice (a 0.1 mm grid).
        quant=np.rint(verts*10000).astype(int);occupied=set(map(tuple,quant));seen=set()
        for i,q in enumerate(quant):
            key=tuple(q)
            if key in seen:
                candidates=[q+step for step in np.ndindex(3,3,3)]
                candidates=[v-1 for v in candidates if tuple(v-1) not in occupied]
                nearest=min(candidates,key=lambda v:np.linalg.norm(v-verts[i]*10000))
                quant[i]=nearest;occupied.add(tuple(nearest))
            seen.add(key)
        verts=quant/10000.
        corners = verts[faces]
        normals = np.cross(corners[:, 1]-corners[:, 0], corners[:, 2]-corners[:, 0])
        if np.einsum('ij,ij->', corners[:, 0], normals) < 0:
            faces = faces[:, ::-1].copy()
            normals *= -1
        smooth = np.zeros_like(verts)
        for k in range(3):
            np.add.at(smooth, faces[:, k], normals)
        smooth /= np.maximum(1e-15, np.linalg.norm(smooth, axis=1)[:, None])
        normals /= np.maximum(1e-15, np.linalg.norm(normals, axis=1)[:, None])
        rows = []
        for i, tri in enumerate(faces):
            n = smooth[tri]
            y = GRIP_Y-centres[i, 2]*HEIGHT
            if name == 'crystal' or np.dot(n.sum(axis=0), normals[i]) < .12:
                n = np.tile(normals[i], (3, 1))
            grip_face = name == 'body' and 409 < y < 511 and distance(centres[i], grip_sample)*HEIGHT < 2
            leaf_face = y < 93 or y > 755 or (603 < y < 650 and centres[i, 0] < (296-GRIP_X)/HEIGHT)
            w = (0, 0, 1) if name != 'body' else (0, 0, 0) if grip_face else (0, 1, 0) if leaf_face else (1, 0, 0)
            for pt, normal in zip(verts[tri], n):
                a = float(np.clip(1-abs(y-397)/34,0.1,1)) if name=='crystal' else 1.
                if grip_face:
                    angle = math.atan2(-pt[0], -pt[2])
                    a = (6.7*((GRIP_Y-pt[1]*HEIGHT)-411)/98-angle/(2*math.pi)) % 1
                height01=float(np.clip(pt[1]-(GRIP_Y-836)/HEIGHT,0,1))
                submask = (0.35 if y>409 else 1.) if name=='crystal' else 1. if name=='string' else .35 if leaf_face else 0.
                rows.append([*pt, *normal, *w, a, .26 if name=='crystal' else 0., submask, height01])
        raw['parts'][name] = rows
        raw['stats'][name] = len(faces)
    RAW.write_text(json.dumps(raw, separators=(',', ':'), allow_nan=False)+chr(10))
    # Reuse v1 metadata; UVs join the deduplication key and use position precision.
    packed = build({'parts':{n:[r[:11] for r in rows] for n,rows in raw['parts'].items()}})
    packed['vertexStride']=13
    packed['uvScale']=10000
    scales=np.array([10000]*3+[1000]*3+[100]*5+[10000]*2)
    for name, rows in raw['parts'].items():
        vertices=[];indices=[];lookup={}
        for row in np.rint(np.asarray(rows)*scales).astype(int).tolist():
            key=tuple(row)
            if key not in lookup:
                lookup[key]=len(lookup)+1;vertices.extend(row)
            indices.append(lookup[key])
        packed[name]={'triangles':len(indices)//3,'v':vertices,'i':indices}
    packed['name'] = 'silver_bow'
    PACKED.write_text(json.dumps(packed,separators=(',',':'),allow_nan=False)+chr(10))
    print(raw['stats'], flush=True)


def simplify(vertices, faces, target, source):
    """Quadric edge collapses, preserving topology and refusing face inversions."""
    import heapq
    vertices = vertices.astype(float)
    faces = faces.astype(int)
    count = len(faces)
    adj = [set() for _ in vertices]
    quadrics = np.zeros((len(vertices), 4, 4))
    corners = vertices[faces]
    n = np.cross(corners[:, 1]-corners[:, 0], corners[:, 2]-corners[:, 0])
    n /= np.maximum(1e-15, np.linalg.norm(n, axis=1)[:, None])
    plane = np.column_stack((n, -(n*corners[:, 0]).sum(axis=1)))
    for k in range(3):
        np.add.at(quadrics, faces[:, k], plane[:, :, None]*plane[:, None, :])
    for i, tri in enumerate(faces):
        for v in tri:
            adj[v].add(i)
    heap = []
    stamp = np.zeros(len(vertices), dtype=int)
    dead = np.zeros(len(faces), dtype=bool)

    def offer(a, b):
        if b < a:
            a, b = b, a
        q = quadrics[a]+quadrics[b]
        mid = (vertices[a]+vertices[b])/2
        pt = mid
        try:
            opt = np.linalg.solve(q[:3, :3], -q[:3, 3])
            span = np.linalg.norm(vertices[a]-vertices[b])
            if np.linalg.norm(opt-mid) < .85*span:
                pt = opt
        except np.linalg.LinAlgError:
            pass
        h = np.r_[pt, 1]
        heapq.heappush(heap, (float(h@q@h), a, b, int(stamp[a]), int(stamp[b]), tuple(pt)))
    for a, b in sorted({tuple(sorted((a, b))) for tri in faces for a, b in zip(tri, np.roll(tri, -1))}):
        offer(a, b)
    while count > target and heap:
        _, a, b, sa, sb, pt = heapq.heappop(heap)
        if stamp[a] != sa or stamp[b] != sb:
            continue
        shared = adj[a] & adj[b]
        touched = adj[a] | adj[b]
        if len(shared) != 2:
            continue
        na = set(faces[list(adj[a])].ravel())
        nb = set(faces[list(adj[b])].ravel())
        if len(na & nb) != 4:
            continue
        ids = sorted(touched-shared)
        before = vertices[faces[ids]]
        after = before.copy()
        after[(faces[ids] == a) | (faces[ids] == b)] = pt
        old = np.cross(before[:, 1]-before[:, 0], before[:, 2]-before[:, 0])
        new = np.cross(after[:, 1]-after[:, 0], after[:, 2]-after[:, 0])
        alignment = (old*new).sum(axis=1)
        if np.max(np.linalg.norm(new,axis=1)) > .00037:
            continue
        if np.any(alignment < .08*np.linalg.norm(old, axis=1)*np.linalg.norm(new, axis=1)+1e-18):
            continue
        for i in shared:
            for key in faces[i]:
                adj[key].discard(i)
            dead[i] = True
        for i in list(adj[b]):
            faces[i, faces[i] == b] = a
        adj[a].update(adj[b])
        adj[b].clear()
        source[a] = (source[a]+source[b])/2
        vertices[a] = pt
        quadrics[a] += quadrics[b]
        stamp[a] += 1
        stamp[b] += 1
        count -= 2
        for v in sorted((na | nb)-{a, b}):
            offer(a, v)
    return vertices, faces[~dead], source


def input_socket(node, key):
    if isinstance(key, int):
        return node.inputs[key] if 0 <= key < len(node.inputs) else None
    return node.inputs.get(key)


def setin(node, key, value):
    socket = input_socket(node, key)
    if socket is not None:
        socket.default_value = value


def wire(tree, output, node, key):
    socket = input_socket(node, key)
    if socket is not None:
        tree.links.new(output, socket)


def material(name, color, metallic, rough, emission=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes['Principled BSDF']
    for key, value in [('Base Color', (*color, 1)), ('Metallic', metallic),
                       ('Roughness', rough), ('Emission Color', (*color, 1)),
                       ('Emission Strength', emission)]:
        setin(shader, key, value)
    return mat


def woven_grip(mat):
    tree = mat.node_tree
    nodes = tree.nodes
    xyz = nodes.new('ShaderNodeSeparateXYZ')
    wire(tree, nodes.new('ShaderNodeNewGeometry').outputs['Position'], xyz, 0)

    def calc(op, a, b=None):
        node = nodes.new('ShaderNodeMath')
        node.operation = op
        for idx, value in enumerate((a, b)):
            if isinstance(value, (float, int)):
                setin(node, idx, value)
            elif value is not None:
                wire(tree, value, node, idx)
        return node.outputs[0]

    angle = calc('ARCTAN2', xyz.outputs['Y'], xyz.outputs['X'])
    height = calc('MULTIPLY', xyz.outputs['Z'], -HEIGHT*6.7*2*math.pi/98)
    phase = calc('ADD', calc('ADD', height, angle), (GRIP_Y-411)*6.7*2*math.pi/98)
    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = (.145, .16, .245, 1)
    ramp.color_ramp.elements[1].color = (.024, .028, .056, 1)
    wire(tree, calc('COSINE', phase), ramp, 0)
    wire(tree, ramp.outputs[0], nodes['Principled BSDF'], 'Base Color')


def silver_surfaces():
    def fibre(mat, scale, dark, light, strength, distance):
        tree = mat.node_tree
        nodes = tree.nodes
        bsdf = nodes['Principled BSDF']
        coords = nodes.new('ShaderNodeTexCoord')
        mapping = nodes.new('ShaderNodeVectorMath')
        mapping.operation = 'MULTIPLY'
        setin(mapping, 1, scale)
        wire(tree, coords.outputs['Object'], mapping, 0)
        grain = nodes.new('ShaderNodeTexNoise')
        setin(grain, 'Scale', 1.)
        setin(grain, 'Detail', 2.4)
        setin(grain, 'Distortion', .26)
        wire(tree, mapping.outputs['Vector'], grain, 'Vector')
        ramp = nodes.new('ShaderNodeValToRGB')
        colors = ramp.color_ramp.elements
        colors[0].position, colors[0].color = .25, (*dark, 1)
        colors[1].position, colors[1].color = .75, (*light, 1)
        wire(tree, grain.outputs['Fac'], ramp, 0)
        wire(tree, ramp.outputs[0], bsdf, 'Base Color')
        bump = nodes.new('ShaderNodeBump')
        setin(bump, 'Strength', strength)
        setin(bump, 'Distance', distance)
        wire(tree, grain.outputs['Fac'], bump, 'Height')
        wire(tree, bump.outputs[0], bsdf, 'Normal')

    ash = material('Silver ash • growth fibres', (.69, .74, .82), 0, .65)
    fibre(ash, (380, 530, 25), (.27, .31, .43), (.84, .87, .91), .16, .00029)
    silk = material('Graphite • shot silk', (.085, .095, .17), 0, .67)
    woven_grip(silk)
    setin(silk.node_tree.nodes['Principled BSDF'], 'Sheen Weight', .50)

    leaf = material('Silver leaf • nacre and veins', (.78, .82, .91), .44, .30)
    fibre(leaf, (240, 360, 34), (.48, .52, .65), (.88, .91, .97), .13, .00019)
    nacre = leaf.node_tree.nodes['Principled BSDF']
    setin(nacre, 'Coat Weight', .23)
    setin(nacre, 'Coat Roughness', .22)
    setin(nacre, 'Coat IOR', 1.45)
    setin(nacre, 'Thin Film Thickness', 280.)  # nanometres
    setin(nacre, 'Thin Film IOR', 1.38)

    ice = material('Glacial bud • cut dielectric', (.13, .56, .93), 0, .073)
    tree = ice.node_tree
    bsdf = tree.nodes['Principled BSDF']
    setin(bsdf, 'IOR', 1.56)
    setin(bsdf, 'Transmission Weight', .77)
    layer = tree.nodes.new('ShaderNodeLayerWeight')
    tones = tree.nodes.new('ShaderNodeValToRGB')
    colors = tones.color_ramp.elements
    colors[0].color, colors[1].color = (.065, .28, .68, 1), (.47, .86, 1, 1)
    colors.new(.46).color = (.15, .57, .94, 1)
    wire(tree, layer.outputs['Facing'], tones, 0)
    wire(tree, tones.outputs[0], bsdf, 'Base Color')
    setin(bsdf, 'Emission Color', (.035, .37, .72, 1))
    setin(bsdf, 'Emission Strength', .10)
    absorb = tree.nodes.new('ShaderNodeVolumeAbsorption')
    setin(absorb, 'Color', (.19, .68, .95, 1))
    setin(absorb, 'Density', 28.)
    wire(tree, absorb.outputs[0], tree.nodes['Material Output'], 'Volume')

    cord = material('Cord • silver filaments', (.62, .7, .82), .8, .29)
    fibre(cord, (1500, 1700, 310), (.45, .54, .66), (.83, .87, .93), .08, .00009)
    return [ash, silk, leaf, ice, cord]


def verify_saved_scene():
    """Audit the native scene on disk, including the actual mesh buffers used to render."""
    import io
    import struct
    import zstandard

    scene_file = OUT / 'silver_bow.blend'
    encoded = scene_file.read_bytes()
    if encoded.startswith(b'BLENDER'):
        content = encoded
    else:
        with zstandard.ZstdDecompressor().stream_reader(io.BytesIO(encoded)) as reader:
            content = reader.read()
    # Blender 5.x uses the 17-byte file header and 32-byte LargeBHead8 records.
    stream = io.BytesIO(content)
    assert stream.read(17).startswith(b'BLENDER17-01v'), 'unexpected Blender file format'
    header = struct.Struct('<4siQqq')
    blocks = {}
    while chunk := stream.read(header.size):
        code, _, _, size, _ = header.unpack(chunk)
        assert size >= 0
        payload = stream.read(size)
        assert len(payload) == size, 'truncated Blender block'
        blocks.setdefault(code.rstrip(bytes(1)), []).append(payload)
    assert b'ENDB' in blocks and b'IM' not in blocks, 'incomplete scene or embedded image'
    assert b'ShaderNodeTexImage' not in content and REF.name.encode() not in content
    assert len(blocks[b'ME']) == 3 and len(blocks[b'MA']) == 5
    assert len(blocks[b'CA']) == 4 and len(blocks[b'LA']) == 3 and b'CYCLES' in content
    for token in (b'ShaderNodeTexNoise', b'ShaderNodeValToRGB', b'ShaderNodeBump', b'ShaderNodeVolumeAbsorption'):
        assert token in content, token

    data_blocks = set(blocks[b'DATA'])
    mesh = json.loads(PACKED.read_text())
    for part in ('body', 'crystal', 'string'):
        group = mesh[part]
        packed = np.reshape(group['v'], (-1, mesh['vertexStride']))
        triangles = np.reshape(group['i'], (-1, 3))[:, ::-1] - 1
        points = packed[triangles.ravel(), :3]
        point_ids = {}
        indices = [point_ids.setdefault(tuple(p), len(point_ids)) for p in points]
        coords = np.array(list(point_ids), dtype=float)[:, [2, 0, 1]] / mesh['scale']
        coords[:, 0] *= -1
        assert coords.astype('<f4').tobytes() in data_blocks, f'{part}: position mismatch'
        assert np.asarray(indices, dtype='<i4').tobytes() in data_blocks, f'{part}: winding/index mismatch'
        print(f'{part}: {len(coords)} welded positions and {len(indices)//3} triangles match packed JSON')
    print('PASS native scene: 0 image datablocks, 0 image samplers, 3 meshes, 5 materials, 4 cameras, 3 lamps; Cycles')


def blender_scene():
    global scene
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    bpy.context.preferences.filepaths.save_version = 0
    materials = silver_surfaces()
    for name, rows in json.loads(RAW.read_text())['parts'].items():
        vs = []
        faces = []
        lookup = {}
        norms = []
        mats = []
        for i in range(0, len(rows), 3):
            tri = []
            for row in rows[i:i+3][::-1]:
                key = (-row[2], row[0], row[1])
                idx = lookup.get(key)
                if idx is None:
                    idx = len(vs)
                    vs.append(key)
                    lookup[key] = idx
                tri.append(idx)
                norms.append((-row[5], row[3], row[4]))
            faces.append(tri)
            w = rows[i][6:9]
            mats.append(3 if name=='crystal' else 4 if name=='string' else 2 if w[1] else 0 if w[0] else 1)
        me = bpy.data.meshes.new(name)
        me.from_pydata(vs, [], faces)
        me.update()
        ob = bpy.data.objects.new(name, me)
        scene.collection.objects.link(ob)
        for m in materials:
            me.materials.append(m)
        for f, mi in zip(me.polygons, mats):
            f.material_index = mi
            f.use_smooth = True
        uv=me.uv_layers.new(name='Material mask and height')
        weights=me.color_attributes.new(name='Material weights',type='FLOAT_COLOR',domain='CORNER')
        for j in range(0,len(rows),3):
            for k,row in enumerate(reversed(rows[j:j+3])):
                uv.data[j+k].uv=row[11:13]; weights.data[j+k].color=row[6:10]
        me.normals_split_custom_set(norms)
    cams = studio()
    scene.camera = cams['iso']
    scene.render.resolution_percentage = 100
    scene.render.resolution_x = 405
    scene.render.resolution_y = IMAGE_H
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == 'VIEW_3D':
                space = area.spaces.active
                space.region_3d.view_rotation = cams['iso'].rotation_euler.to_quaternion()
                space.region_3d.view_distance = 1.6
                space.region_3d.view_location = (.02, 0, .02)
                space.region_3d.view_perspective = 'ORTHO'
                space.overlay.show_overlays = False
                space.shading.color_type = 'MATERIAL'
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'silver_bow.blend'))
    verify_saved_scene()
    for name, cam in cams.items():
        scene.camera = cam
        scene.render.resolution_x = 405 if name == 'iso' else WIDTH
        scene.render.filepath = str(OUT/f'preview_{name}.png')
        bpy.ops.render.render(write_still=True)
    subprocess.run(['python3', str(Path(__file__).resolve()), 'compare'], check=True)


if __name__ == '__main__':
    mode = sys.argv[-1]
    if mode=='check-scene': verify_saved_scene()
    elif mode=='compare-mesh': compare_mesh()
    elif mode=='lua': verify_lua()
    elif mode=='polish': finish_contours()
    elif mode=='export':
        binary=Path('/Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13')
        subprocess.run([str(binary),__file__,'geometry'],check=True)
    elif mode=='topology': verify()
    elif mode in ('measure', 'compare', 'verify', 'geometry', 'fit'):
        {'measure': measure, 'compare': compare, 'verify': verify,
            'geometry': volume_geometry, 'fit': fit_projections}[mode]()
    else:
        import bpy
        from mathutils import Vector
        volume_geometry()
        if mode != 'export-only':
            blender_scene()
