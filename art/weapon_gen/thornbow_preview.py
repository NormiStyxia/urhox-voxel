"""Painter's-algorithm preview of thornbow_game.json (side/front/3-4 views) - no GPU needed.
usage: python3 thornbow_preview.py in.json out.png"""
import json, sys, math
import numpy as np
from PIL import Image, ImageDraw
d = json.load(open(sys.argv[1]))
rows = np.array(d['parts']['body'] + d['parts']['string'])
tri = rows.reshape(-1, 3, 11)
def view(yaw, W=520, H=1000, scale=880):
    c, s = math.cos(yaw), math.sin(yaw)
    R = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])   # rotate around Y
    P = tri[:, :, 0:3] @ R.T
    N = tri[:, :, 3:6] @ R.T
    img = Image.new('RGB', (W, H), (20, 18, 30))
    dr = ImageDraw.Draw(img)
    order = np.argsort(-P[:, :, 2].mean(axis=1))        # far (+z... camera at -z looks +z) first
    for i in order:
        n = N[i].mean(axis=0); n /= (np.linalg.norm(n) + 1e-9)
        if n[2] > 0.25 and tri[i, 0, 6] + tri[i, 0, 7] < 1.5 and tri[i, 0, 8] < 0.5 and False: continue
        sh = 0.35 + 0.65 * max(0.0, float(np.dot(n, [-0.35, 0.6, -0.7])))
        w = tri[i, 0, 6:9]
        wood = np.array([0.43, 0.30, 0.22]); pet = np.array([0.95, 0.60, 0.88]); cry = np.array([0.55, 0.25, 0.95]); grip = np.array([0.30, 0.22, 0.30])
        base = wood * w[0] + pet * w[1] + cry * w[2] + grip * (1 - w.sum())
        if tri[i, 0, 10] >= 0.9: base = np.array([1, 0.7, 0.95])
        col = tuple(int(255 * min(1, v)) for v in base * sh)
        pts = [(W / 2 + p[0] * scale * 1.0, H / 2 - p[1] * scale) for p in P[i]]
        dr.polygon(pts, fill=col)
    return img
out = Image.new('RGB', (520 * 3, 1000))
for k, yaw in enumerate((math.pi / 2, 0.0, math.pi / 4)):
    out.paste(view(yaw), (520 * k, 0))
out.save(sys.argv[2])
