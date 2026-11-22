"""Render exact Lua geometry offline, NOT engine captures. Run from project root."""
from pathlib import Path
import json, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().study_path = str(ROOT / 'scripts/?.lua') + ';'
lua.execute('package.path=study_path..package.path')
blades = lua.execute((OUT / 'BladeStudies.lua').read_text())
palette_source = lua.eval('require("combat.ForgeShowroomBlades")')[0]

def plain(v):
    if not hasattr(v, 'items'): return v
    keys = list(v.keys())
    if keys and all(isinstance(k, int) for k in keys): return [plain(v[k]) for k in sorted(keys)]
    return {k: plain(x) for k, x in v.items()}

data = {r: plain(blades.Data(r)) for r in 'AB'}
palette = plain(palette_source.Palette(None))
font = '/System/Library/Fonts/Supplemental/Arial.ttf'
S = 2
def label(draw, xy, text, size=18):
    draw.text(tuple(int(v*S) for v in xy), text, font=ImageFont.truetype(font, size*S), fill='#cbd3e2')

def draw_blade(image, d, cx, bottom, height, yaw=0):
    angle = math.radians(yaw); ca, sa = math.cos(angle), math.sin(angle)
    def transform(p): return [ca*p[0]+sa*p[2], p[1], -sa*p[0]+ca*p[2]]
    pixels = np.array(image)
    depth = np.full(pixels.shape[:2],np.inf)
    verts = d['vertices']
    for i in range(0, len(verts), 3):
        vs = verts[i:i+3]; n = transform(vs[0]['n'])
        if n[2] >= -1e-6: continue
        ps = [transform(v['p']) for v in vs]
        base = [sum(vs[0]['c'][k]*palette[ch][j] for k,ch in enumerate(['primary','secondary','accent'])) for j in range(3)]
        light = .68+.32*max(0,sum(n[j]*[-.40,.45,-.80][j] for j in range(3)))
        color = tuple(round(min(1,max(0,c*light*vs[0]['shade']))*255) for c in base)
        pts = [((cx+p[0]*height/1.7)*S,(bottom-p[1]*height/1.7)*S) for p in ps]
        x0=max(0,math.floor(min(p[0] for p in pts))); x1=min(image.width,math.ceil(max(p[0] for p in pts)))
        y0=max(0,math.floor(min(p[1] for p in pts))); y1=min(image.height,math.ceil(max(p[1] for p in pts)))
        if x0>=x1 or y0>=y1: continue
        (ax,ay),(bx,by),(cx2,cy2)=pts
        den=(by-cy2)*(ax-cx2)+(cx2-bx)*(ay-cy2)
        if abs(den)<1e-9: continue
        yy,xx=np.mgrid[y0:y1,x0:x1];xx=xx+.5;yy=yy+.5
        w0=((by-cy2)*(xx-cx2)+(cx2-bx)*(yy-cy2))/den
        w1=((cy2-ay)*(xx-cx2)+(ax-cx2)*(yy-cy2))/den
        w2=1-w0-w1
        z=w0*ps[0][2]+w1*ps[1][2]+w2*ps[2][2]
        mask=(w0>=-1e-6)&(w1>=-1e-6)&(w2>=-1e-6)&(z<depth[y0:y1,x0:x1])
        depth[y0:y1,x0:x1][mask]=z[mask]
        pixels[y0:y1,x0:x1][mask]=color
    image.paste(Image.fromarray(pixels))

for r in 'AB':
    im = Image.new('RGB',(1000*S,1100*S),'#1c2638'); dr = ImageDraw.Draw(im)
    label(dr,(40,32),f'ROUTE {r}  |  '+('HARD FACETS' if r=='A' else '1 cm CUBOIDS'),30)
    label(dr,(40,82),'Exact Lua mesh / offline illustration / not Web render',18)
    for x,yaw,title in [(150,0,'FRONT'),(390,28,'3/4'),(620,90,'SIDE'),(850,180,'BACK')]:
        draw_blade(im,data[r],x,960,800,yaw)
        label(dr,(x-34,994),title,16)
    label(dr,(40,1050),f"{int(data[r]['triangles'])} triangles | 1.70 m | no textures | +Y tip",18)
    im.resize((1000,1100),Image.Resampling.LANCZOS).save(OUT/f'route-{r}.png')

im = Image.new('RGB',(760*S,1100*S),'#1c2638'); dr = ImageDraw.Draw(im)
label(dr,(40,26),'BLADE ROUTE STUDIES',30)
label(dr,(40,76),'Same scale / actual geometry / offline, not in-game',17)
for r,x in [('A',220),('B',550)]:
    draw_blade(im,data[r],x,955,800,24)
    label(dr,(x-85,1000),'A  HARD FACETS' if r=='A' else 'B  CUBOIDS',23)
label(dr,(40,1050),'Flow is animated in Web; this sheet shows neutral materials.',16)
im.resize((760,1100),Image.Resampling.LANCZOS).save(OUT/'comparison.png')
metrics = {}
for r,d in data.items():
    size = [round(b-a,6) for a,b in zip(d['bounds']['min'],d['bounds']['max'])]
    metrics[r] = {'triangles': d['triangles'], 'vertices': len(d['vertices']), 'cuboids': len(d['boxes']),
        'aabb_m': size, 'aabb_m3': math.prod(size), 'vertex_bytes': len(d['vertices'])*36, 'texture_bytes': 0}
(OUT/'metrics.json').write_text(json.dumps(metrics,indent=2))
print(json.dumps(metrics,indent=2))
