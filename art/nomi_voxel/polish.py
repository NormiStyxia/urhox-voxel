"""Colour-only polish of Nomi's mesh (2026-11-10, after user review of in-game screenshots).

Sampling baked the reference image's own shading into vertex RGB. In game the
real light and the hair's cast shadow then darken those cells again, so the face
looked dirty. Coat colours had also spilled into the hair, and into the gold tie.

Geometry, bones, and every cell not listed in polish_edits.json are unchanged.
Quads are split into unit cells, recoloured, then merged again; check_mesh.py
undoes the recorded edits and compares the unit cells with the pre-polish baseline.

Rules (in this order):
  1. Head "dirt" -- brown-grey shading (A/H/o) and coat navy on hair -- takes the
     majority colour of its clean neighbours; next to skin it becomes skin.
     The eyes (front, eye rows) are protected.
  2. Isolated dark hair specks (dark component of at most SPECK_MAX cells) take
     the majority colour of the surrounding hair; longer strand lines are kept.
  3. Navy, skin, or brown inside the gold tie (front of the chest) becomes gold;
     skin samples left on the white collar V around the knot become white.
  4. Darker sampled hair tones keep 60% of their darkening (strands stay visible).
"""
import json
from collections import Counter
from pathlib import Path
import numpy as np
from scipy.spatial import cKDTree

HERE = Path(__file__).resolve().parent
OFFSET = np.array((26., 0., 22.))
DIR_N = {'px': (1, 0, 0), 'nx': (-1, 0, 0), 'py': (0, 1, 0), 'ny': (0, -1, 0), 'pz': (0, 0, 1), 'nz': (0, 0, -1)}

# RGB 0-255 as stored in the palette
SKIN = [(251, 234, 222), (244, 215, 202), (234, 211, 198)]
SHADE = [(162, 141, 136), (216, 187, 176), (120, 113, 112)]   # baked brown-grey shading
GOLD = (233, 189, 96)
BLOUSE = (232, 233, 240)
HAIR_FALLBACK = (167, 172, 194)
SPECK_MAX = 3
HAIR_BASE = np.array((232., 233., 240.))
HAIR_CONTRAST = 0.6                                              # rule 4: keep 60% of the darkening
HAIR_KEEP_LUMA = 215
EYE_ZONE = dict(d='pz', y=(56, 61), x=(16, 35))                 # index coords of the eye rows
TIE_ZONE = dict(d='pz', y=(36, 44), x=(20, 31))                  # index coords of the tie


def luma(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def is_navy(c):
    return c[2] > c[0] + 25 and luma(c) < 110


def unit_cells(q):
    """Expand a quad (bone,d,layer,u,v,w,h,c) into unit quads."""
    bone, d, layer, u, v, w, h, c = q
    return [(bone, d, layer, u + a, v + b, c) for a in range(int(w)) for b in range(int(h))]


def cell_ijk(d, layer, u, v):
    if d in ('px', 'nx'):
        return layer, v, u
    if d in ('py', 'ny'):
        return u, layer, v
    return u, v, layer


def cell_centre(d, layer, u, v):
    i, j, k = cell_ijk(d, layer, u, v)
    n = np.array(DIR_N[d], float)
    return np.array((i + .5, j + .5, k + .5)) + n * .5 - OFFSET


def merge(cells):
    """Greedy rectangles per (bone, dir, layer, colour); same scan order as voxelize.greedy."""
    groups = {}
    for bone, d, layer, u, v, c in cells:
        groups.setdefault((bone, d, layer), {})[(u, v)] = c
    quads = []
    for (bone, d, layer), g in groups.items():
        used = set()
        for (u, v) in sorted(g):
            if (u, v) in used:
                continue
            c = g[(u, v)]
            w = 1
            while (u + w, v) in g and (u + w, v) not in used and g[(u + w, v)] == c:
                w += 1
            h = 1
            while all((u + t, v + h) in g and (u + t, v + h) not in used and g[(u + t, v + h)] == c for t in range(w)):
                h += 1
            for t in range(w):
                for s in range(h):
                    used.add((u + t, v + s))
            quads.append((bone, d, layer, u, v, w, h, c))
    return quads


def canonical(quads, tris, palette):
    """Order-independent description: unit cells and triangles with their RGB."""
    cells = sorted([(b, d, int(l), int(u), int(v), [round(float(x), 3) for x in palette[c]])
                    for q in quads for (b, d, l, u, v, c) in unit_cells(q)])
    ts = [(b, np.round(np.asarray(p, float), 4).tolist(), [round(float(x), 3) for x in palette[c]]) for b, p, c in tris]
    return cells, ts


def polish(quads, palette, tris):
    palette = [np.asarray(c, float) for c in palette]
    rgb = [tuple(int(round(x)) for x in c) for c in palette]

    def index(col):
        col = np.asarray(col, float)
        for i, c in enumerate(palette):
            if np.allclose(c, col, atol=2.0):
                return i
        palette.append(col)
        rgb.append(tuple(int(round(x)) for x in col))
        return len(palette) - 1

    def all_of(col):
        # the sampled palette holds duplicate RGB entries (body and head copies)
        index(col)
        return {i for i, c in enumerate(palette) if np.allclose(c, np.asarray(col, float), atol=2.0)}

    exact = lambda i: [float(x) for x in palette[i]]   # unrounded; check_mesh rounds like the exporter
    skin = set().union(*(all_of(c) for c in SKIN))
    shade = set().union(*(all_of(c) for c in SHADE))
    golds = all_of(GOLD)
    gold = index(GOLD)

    cells = [c for q in quads for c in unit_cells(q)]
    tris = [list(t) for t in tris]
    edits = []

    # ---- head elements (unit cells + cap triangles) with centres and normals
    elems = []   # (kind, idx, centre, normal)
    for n_, (bone, d, layer, u, v, c) in enumerate(cells):
        if bone == 'head':
            elems.append(('q', n_, cell_centre(d, layer, u, v), np.array(DIR_N[d], float)))
    for n_, (bone, pts, c) in enumerate(tris):
        if bone == 'head':
            p = np.asarray(pts, float) - OFFSET
            nrm = np.cross(p[1] - p[0], p[2] - p[0])
            nrm /= np.linalg.norm(nrm) + 1e-9
            elems.append(('t', n_, p.mean(axis=0), nrm))
    centres = np.array([e[2] for e in elems])
    tree = cKDTree(centres)
    nbrs = []
    for a, e in enumerate(elems):
        near = tree.query_ball_point(e[2], 1.05)
        nbrs.append([b for b in near if b != a and float(elems[b][3] @ e[3]) > -0.2])

    def get(a):
        kind, n_, _, _ = elems[a]
        return cells[n_][-1] if kind == 'q' else tris[n_][2]

    def put(a, c, rule):
        kind, n_, _, _ = elems[a]
        old = get(a)
        if old == c:
            return
        if kind == 'q':
            cells[n_] = cells[n_][:-1] + (c,)
        else:
            tris[n_][2] = c
        edits.append({'rule': rule, 'kind': kind, 'key': key(a), 'before': exact(old), 'after': exact(c)})

    def key(a):
        kind, n_, _, _ = elems[a]
        if kind == 'q':
            b, d, l, u, v, _ = cells[n_]
            return [b, d, int(l), int(u), int(v)]
        # the exporter groups triangles by bone, so key by the index within the bone
        bone = tris[n_][0]
        return [bone, sum(1 for t in tris[:n_] if t[0] == bone)]

    def in_zone(a, z):
        kind, n_, _, _ = elems[a]
        if kind != 'q':
            return False
        b, d, l, u, v, _ = cells[n_]
        i, j, _k = cell_ijk(d, l, u, v)
        return d == z['d'] and z['y'][0] <= j <= z['y'][1] and z['x'][0] <= i <= z['x'][1]

    eye = {a for a in range(len(elems)) if in_zone(a, EYE_ZONE)}
    dirty = lambda c: c in shade or is_navy(rgb[c])

    # rule 1: shading / navy on the head
    for _ in range(12):
        todo = [a for a in range(len(elems)) if a not in eye and dirty(get(a))]
        if not todo:
            break
        changes = []
        for a in todo:
            clean = [get(b) for b in nbrs[a] if not dirty(get(b)) and b not in eye]
            if not clean:
                continue
            sk = [c for c in clean if c in skin]
            pick = Counter(sk if len(sk) * 2 >= len(clean) else clean).most_common(1)[0][0]
            changes.append((a, pick))
        if not changes:
            break
        for a, c in changes:
            put(a, c, 'head_shading' if get(a) in shade else 'head_navy')
    for a in range(len(elems)):
        if a not in eye and dirty(get(a)):
            put(a, index(HAIR_FALLBACK), 'head_shading')

    # rule 2: isolated dark specks inside the hair
    hairish = lambda c: (c not in skin and c not in golds and not is_navy(rgb[c]) and c not in shade
                         and max(rgb[c]) - min(rgb[c]) < 60 and luma(rgb[c]) > 90)
    dark = lambda c: hairish(c) and luma(rgb[c]) < 160
    seen = set()
    for a in range(len(elems)):
        if a in seen or a in eye or not dark(get(a)):
            continue
        comp, stack = [], [a]
        seen.add(a)
        while stack:
            x = stack.pop()
            comp.append(x)
            for b in nbrs[x]:
                if b not in seen and b not in eye and dark(get(b)):
                    seen.add(b)
                    stack.append(b)
        if len(comp) > SPECK_MAX:
            continue
        ring = [get(b) for x in comp for b in nbrs[x] if b not in comp and hairish(get(b)) and not dark(get(b))]
        if len(ring) >= 2 * len(comp):
            pick = Counter(ring).most_common(1)[0][0]
            for x in comp:
                put(x, pick, 'hair_speck')

    # rule 4: compress the darker sampled hair tones toward the base hair colour.
    # Strand patterns stay (same cells, same order of brightness); in game the real
    # light and shadow supply the depth, so baked dark tones only read as dirt.
    for a in range(len(elems)):
        c = get(a)
        if a in eye or not hairish(c) or luma(rgb[c]) >= HAIR_KEEP_LUMA:
            continue
        new = HAIR_BASE - (HAIR_BASE - np.asarray(rgb[c], float)) * HAIR_CONTRAST
        put(a, index(np.round(new)), 'hair_contrast')

    # rule 3: the gold tie on the chest front. Neighbours are taken on the front-most
    # cell of each (x, y) column, because a stray cell may sit one layer behind the tie.
    front = {}
    for n_, (bone, d, layer, u, v, c) in enumerate(cells):
        if d != TIE_ZONE['d']:
            continue
        if TIE_ZONE['y'][0] <= v <= TIE_ZONE['y'][1] and TIE_ZONE['x'][0] <= u <= TIE_ZONE['x'][1]:
            if (u, v) not in front or layer > cells[front[(u, v)]][2]:
                front[(u, v)] = n_
    for _ in range(3):
        changes = []
        for (u, v), n_ in front.items():
            c = cells[n_][-1]
            if c in golds or not (is_navy(rgb[c]) or c in skin or c in shade):
                continue
            g = sum(1 for t in ((u + 1, v), (u - 1, v), (u, v + 1), (u, v - 1))
                    if t in front and cells[front[t]][-1] in golds)
            if g >= 2:
                changes.append(n_)
        for n_ in changes:
            b, d, l, u, v, c = cells[n_]
            cells[n_] = (b, d, l, u, v, gold)
            edits.append({'rule': 'tie', 'kind': 'q', 'key': [b, d, int(l), int(u), int(v)],
                          'before': exact(c), 'after': exact(gold)})
        if not changes:
            break
    # Skin samples left around the knot sit on the white sailor-collar V (the neck is above).
    white = index(BLOUSE)
    for (u, v), n_ in front.items():
        b, d, l, uu, vv, c = cells[n_]
        if c in skin:
            cells[n_] = (b, d, l, uu, vv, white)
            edits.append({'rule': 'tie', 'kind': 'q', 'key': [b, d, int(l), int(uu), int(vv)],
                          'before': exact(c), 'after': exact(white)})

    return merge(cells), palette, [tuple(t) for t in tris], edits
