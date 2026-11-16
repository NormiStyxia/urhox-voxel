"""Trace the thorn-bow three-view sheet into branch polylines + flower placements (1:1 with the reference).

Input : art/weapons_2d/castorice_bow/thornbow_threeview_v1.jpg  (side | front | side, 2560x1440)
Output: art/weapon_gen/out/thornbow_trace.json  -> read by thornbow_blender.py
All coordinates are sheet units divided by L (=1334 px, bow height); x from the view's left edge,
y from the bow top, depth z from the FRONT view (+ = front view right).
Run: python3 art/weapon_gen/thornbow_trace.py   (needs numpy, scipy, scikit-image, pillow)
"""
import json, math, os, sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from skimage.morphology import skeletonize, disk, binary_opening, remove_small_holes, remove_small_objects

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SRC = os.path.join(ROOT, 'art/weapons_2d/castorice_bow/thornbow_threeview_v1.jpg')
OUT = os.path.join(os.path.dirname(__file__), 'out', 'thornbow_trace.json')
SIDE = (328, 783); FRONT = (1217, 1367); TOP = 65; PXL = 1334.0
OPEN_R = int(os.environ.get('TB_OPEN_R', 5))        # drop twigs thinner than 2*R px
TIP_GROW = int(os.environ.get('TB_TIP_GROW', 22))   # re-grow tapered tips after opening
MIN_EDGE = float(os.environ.get('TB_MIN_EDGE', 0.030))  # drop stubs shorter than this (x L)

ref = np.array(Image.open(SRC).convert('RGB')).astype(float) / 255
H, W, _ = ref.shape
mx = ref.max(axis=2); r, g, b = ref[..., 0], ref[..., 1], ref[..., 2]


def masks(x0, x1):
    dark = mx < 0.42
    dark[:, :x0 - 12] = False; dark[:, x1 + 12:] = False; dark[:TOP - 8] = False
    crys = ndi.binary_dilation(((b - g) > 0.10) & (mx > 0.18) & (mx < 0.62) & (b > 0.35), iterations=2)
    dark &= ~crys
    dark = ndi.binary_closing(dark, iterations=2)
    flower = (mx > 0.6) & ((b - g) > 0.08) & ((r - g) > 0.03)
    flower[:, :x0 - 12] = False; flower[:, x1 + 12:] = False
    return dark, flower


dark, flower = masks(*SIDE)
seed = binary_opening(dark, disk(OPEN_R))
rec = seed.copy()
for _ in range(TIP_GROW):
    rec = ndi.binary_dilation(rec) & dark
rec = remove_small_holes(rec, 220)
rec = remove_small_objects(rec, 400)
rec = ndi.binary_opening(rec, iterations=1)
dt = ndi.distance_transform_edt(rec)
skel = skeletonize(rec)

# ---- skeleton -> graph (nodes = endpoints / junctions, edges = pixel paths)
sk = np.argwhere(skel)
idx = {tuple(p): i for i, p in enumerate(sk)}
nbr = {}
for (y, x) in sk:
    n = []
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if (dy or dx) and (y + dy, x + dx) in idx:
                n.append((y + dy, x + dx))
    nbr[(y, x)] = n
deg = {p: len(n) for p, n in nbr.items()}
nodes = {p for p, d in deg.items() if d != 2}
# merge junction clusters (adjacent junction pixels) into one node
lab, nl = ndi.label(np.isin(np.arange(1), [0]))  # placeholder to keep scipy imported
node_pts = [p for p in nodes]
visited_edges = set()
edges = []
for p in node_pts:
    for q in nbr[p]:
        if (p, q) in visited_edges:
            continue
        path = [p, q]
        visited_edges.add((p, q))
        prev, cur = p, q
        while cur not in nodes:
            nxt = [n for n in nbr[cur] if n != prev]
            if not nxt:
                break
            prev, cur = cur, nxt[0]
            path.append(cur)
        visited_edges.add((cur, prev))
        if len(path) >= 3:
            edges.append(path)


def to_sheet(yx):
    return ((yx[1] - SIDE[0]) / PXL, (yx[0] - TOP) / PXL)


def smooth(pts, k=5):
    a = np.array(pts, float)
    if len(a) < 2 * k:
        return a
    out = a.copy()
    for i in range(len(a)):
        lo, hi = max(0, i - k), min(len(a), i + k + 1)
        out[i] = a[lo:hi].mean(axis=0)
    out[0], out[-1] = a[0], a[-1]
    return out


# ---- depth from the front view: dark-pixel horizontal extent at each row (half width -> max |z| budget)
fdark, fflower = masks(*FRONT)
fcx = (FRONT[0] + FRONT[1]) / 2


def depth_budget(y_px):
    row = fdark[int(np.clip(y_px, 0, H - 1))]
    xs = np.where(row)[0]
    return (xs.max() - xs.min()) / 2 / PXL if len(xs) else 0.02


branches = []
for path in edges:
    pts = [(p[1], p[0]) for p in path]            # (x_px, y_px)
    if len(pts) < 8:
        continue
    pl = smooth(pts)
    length = sum(math.dist(pl[i], pl[i + 1]) for i in range(len(pl) - 1)) / PXL
    rad = [dt[int(p[0]), int(p[1])] for p in path]
    # discard stubs: short *and* thin
    if length < MIN_EDGE:
        continue
    branches.append(dict(pts=[[(p[0] - SIDE[0]) / PXL, (p[1] - TOP) / PXL] for p in pl[::3]] + [[(pl[-1][0] - SIDE[0]) / PXL, (pl[-1][1] - TOP) / PXL]],
                         rad=[float(np.median(rad[max(0, i - 6):i + 7])) / PXL for i in range(0, len(rad), 3)] + [float(rad[-1]) / PXL],
                         length=length))

# ---- flowers: connected components of the lilac mask in the side view
fl, nfl = ndi.label(ndi.binary_opening(flower, iterations=2))
flowers = []
for i in range(1, nfl + 1):
    ys, xs = np.where(fl == i)
    if len(xs) < 900:
        continue
    cx, cy = xs.mean(), ys.mean()
    area = len(xs)
    # principal axis of the blob (direction the lotus faces) from covariance
    cov = np.cov(np.vstack([xs - cx, ys - cy]))
    w, v = np.linalg.eigh(cov)
    flowers.append(dict(x=(cx - SIDE[0]) / PXL, y=(cy - TOP) / PXL, area=area / PXL ** 2,
                        radius=math.sqrt(area / math.pi) / PXL, w=float(math.sqrt(w[1])) / PXL, h=float(math.sqrt(w[0])) / PXL,
                        axis=[float(v[0, 1]), float(v[1, 1])]))
# front view flower z offsets: pair each side flower to the closest-y front blobs (alternate sign to keep balance)
ffl, nff = ndi.label(ndi.binary_opening(fflower, iterations=2))
fcands = []
for i in range(1, nff + 1):
    ys, xs = np.where(ffl == i)
    if len(xs) < 700:
        continue
    fcands.append(((ys.mean() - TOP) / PXL, (xs.mean() - fcx) / PXL))
flowers.sort(key=lambda f: f['y'])
used = set()
for f in flowers:
    best = None
    for k, (fy, fz) in enumerate(fcands):
        if k in used:
            continue
        d = abs(fy - f['y'])
        if best is None or d < best[0]:
            best = (d, k, fz)
    if best and best[0] < 0.05:
        used.add(best[1]); f['z'] = best[2]
    else:
        f['z'] = 0.0

out = dict(L=PXL, sheet=dict(side=SIDE, front=FRONT, top=TOP), branches=branches, flowers=flowers,
           params=dict(open_r=OPEN_R, tip_grow=TIP_GROW, min_edge=MIN_EDGE))
os.makedirs(os.path.dirname(OUT), exist_ok=True)
json.dump(out, open(OUT, 'w'))
print('branches', len(branches), 'total length %.2f L' % sum(b['length'] for b in branches), 'flowers', len(flowers))
print('mean rad px %.1f' % (np.mean([np.mean(b['rad']) for b in branches]) * PXL))
# preview
prev = np.full((H, W, 3), 255, np.uint8)
prev[dark] = (170, 170, 170); prev[rec] = (60, 60, 60)
for bch in branches:
    for (x, y) in bch['pts']:
        px, py = int(x * PXL + SIDE[0]), int(y * PXL + TOP)
        prev[max(0, py - 1):py + 2, max(0, px - 1):px + 2] = (255, 60, 60)
for f in flowers:
    px, py = int(f['x'] * PXL + SIDE[0]), int(f['y'] * PXL + TOP)
    prev[max(0, py - 6):py + 7, max(0, px - 6):px + 7] = (40, 160, 255)
Image.fromarray(prev[:, SIDE[0] - 30:SIDE[1] + 40]).save('/tmp/tr/trace_preview.png')
