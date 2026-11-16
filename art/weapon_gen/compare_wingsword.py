#!/usr/bin/env python3
"""Independent alpha/colour-mask comparison against the three-view.
Uses the EXISTING /tmp/pxvenv Pillow/numpy, installs nothing:
/tmp/pxvenv/bin/python -I art/weapon_gen/compare_wingsword.py
A software z-buffer measures actual exported (quantized) triangle geometry.
Blender front (when available) is registered by the documented camera scale,
not independently squeezed to fit either the blade or the guard.
"""
import json, pathlib, runpy
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
ROOT=pathlib.Path(__file__).resolve().parents[2]
T=runpy.run_path(str(ROOT/'art/weapon_gen/trace_wingsword.py'))
D=json.loads((ROOT/'art/weapon_gen/out/wingsword.json').read_text())
OUT=ROOT/'art/weapons_2d/wing_sword_v2';OUT.mkdir(exist_ok=True)
S=T['SCALE']; CX=T['CENTER_X']; X0=650; W,H=620,2100
src=Image.open(ROOT/T['SOURCE']).convert('RGBA')
ref=src.crop((X0,0,X0+W,H)); a=np.asarray(ref).astype(float)
alpha=a[:,:,3]>128; r,g,b=[a[:,:,i] for i in range(3)]
y,x=np.indices((H,W)); gx=x+X0
ref_gold=alpha&(r>120)&(r>b*1.08)&(g>b*1.04)&(y>=1170)&(y<1725)
ref_blade=alpha&(((b>140)&(g>90)&(b>r*1.05))|((r>220)&(g>220)&(b>220)))&~ref_gold&(gx>840)&(gx<1060)&(y<1445)
zbuf=np.full((H,W),np.inf); labels=np.zeros((H,W),np.uint8)
col=np.zeros((H,W,4),np.uint8)
PAL=np.array([[.96,.99,1],[1,.84,.43],[.02,.79,1],[.08,.15,.36]])
for tri in D['tris']:
    pts=np.round(np.array(tri['p'])*10000)/10000
    xx=pts[:,0]/S+CX-X0; yy=50+(1.62-pts[:,1])/S
    area=(xx[1]-xx[0])*(yy[2]-yy[0])-(yy[1]-yy[0])*(xx[2]-xx[0])
    if abs(area)<1e-8:continue
    x0=max(0,int(np.floor(xx.min())));x1=min(W,int(np.ceil(xx.max()))+1)
    y0=max(0,int(np.floor(yy.min())));y1=min(H,int(np.ceil(yy.max()))+1)
    Y,X=np.mgrid[y0:y1,x0:x1];X=X+.5;Y=Y+.5
    u=((xx[1]-X)*(yy[2]-Y)-(yy[1]-Y)*(xx[2]-X))/area
    v=((xx[2]-X)*(yy[0]-Y)-(yy[2]-Y)*(xx[0]-X))/area
    w=1-u-v;z=u*pts[0,2]+v*pts[1,2]+w*pts[2,2]
    mask=(u>=-1e-8)&(v>=-1e-8)&(w>=-1e-8)&(z<zbuf[y0:y1,x0:x1])
    zbuf[y0:y1,x0:x1][mask]=z[mask]
    rgb=np.array(tri['c']); weights=np.r_[rgb,max(0,1-rgb.sum())]
    color=np.minimum(1,weights@PAL*tri['shade'])
    if tri['glow']>0:color=np.minimum(1,color*.55+.45*PAL[2]+.25*tri['glow'])
    col[y0:y1,x0:x1][mask]=np.r_[np.rint(color*255).astype(np.uint8),255]
    label=1 if tri['part']=='blade' else 2 if tri['part'] in ('wings','guard_core','collar') and tri['c'][1]>.5 else 3
    labels[y0:y1,x0:x1][mask]=label
model_gold=labels==2;model_blade=labels==1
# Restrict gold to same blade/guard crop (exclude grip bands and pommel).
model_gold&=(y>=1170)&(y<1725)
def iou(a,b):return float((a&b).sum()/(a|b).sum())
def mask_image(m):return Image.fromarray((m*255).astype('uint8'))
for name,m in [('ref_gold',ref_gold),('model_gold',model_gold),('ref_blade',ref_blade),('model_blade',model_blade)]:mask_image(m).save(OUT/(name+'.png'))
software=Image.fromarray(col);software.save(ROOT/'art/weapon_gen/out/analysis_front.png')
# Global width envelopes in side view, with alpha>128, NOT RGB on transparent bg.
side=np.asarray(src)[50:1715,1820:2010]; am=side[:,:,3]>128
blade_side=am[:1050]; by,bx=np.where(blade_side)
guard_side=am[1050:];gy,gxx=np.where(guard_side)
ref_blade_thick=(bx.max()-bx.min()+1)*S
ref_guard_thick=(gxx.max()-gxx.min()+1)*S
blade_z=[q[2] for t in D['tris'] if t['part']=='blade' for q in t['p']]
guard_z=[q[2] for t in D['tris'] if t['part'] in ('wings','guard_core','collar') for q in t['p']]
model_blade_thick=max(blade_z)-min(blade_z);model_guard_thick=max(guard_z)-min(guard_z)
metrics={'triangles':len(D['tris']),'gold_guard_iou':iou(ref_gold,model_gold),'blade_iou':iou(ref_blade,model_blade),
 'side_blade':{'reference_m':ref_blade_thick,'model_m':model_blade_thick,'relative_error':abs(model_blade_thick/ref_blade_thick-1)},
 'side_guard':{'reference_m':ref_guard_thick,'model_m':model_guard_thick,'relative_error':abs(model_guard_thick/ref_guard_thick-1)},
 'method':'Fixed tip=50, bottom=2035, center=949, 1.855m total. Front visible colour masks (no navy ink), exported quantized triangles with z-buffer. Side maximum alpha-envelope width, not per-row profile accuracy.',
 'blender_front_available':(OUT/'preview_front.png').exists()}
(OUT/'metrics.json').write_text(json.dumps(metrics,indent=2)+'\n');print(json.dumps(metrics,indent=2))
# Unambiguous geometry comparison even if GPU rendering is unavailable.
bg=Image.new('RGBA',(W,H),'#e7e7eb');bg.alpha_composite(ref)
preview=Image.new('RGBA',(W,H),'#e7e7eb');preview.alpha_composite(software)
def pair(left,right,name,right_label):
    canvas=Image.new('RGB',(W*2,H+60),'#e7e7eb');canvas.paste(left,(0,60));canvas.paste(right,(W,60))
    draw=ImageDraw.Draw(canvas);draw.text((30,20),'CONCEPT (fixed scale)',fill='#172440');draw.text((W+30,20),right_label,fill='#172440')
    canvas.resize((620,1080)).save(OUT/name)
pair(bg,preview,'comparison_geometry.png','GEOMETRY Z-BUFFER (not Blender)')
# Render pixels mapped back to reference coordinates using camera ortho_scale.
if metrics['blender_front_available']:
    render=Image.open(OUT/'preview_front.png').convert('RGBA')
    ppm=render.height/(D['meta']['height']*1.08)
    factor=1/(ppm*S); newsize=(round(render.width*factor),round(render.height*factor))
    render=render.resize(newsize,Image.Resampling.LANCZOS)
    registered=Image.new('RGBA',(W,H))
    registered.alpha_composite(render,(round(CX-X0-newsize[0]/2),round((50+2035)/2-newsize[1]/2)))
    target=Image.new('RGBA',(W,H),'#e7e7eb');target.alpha_composite(registered)
    pair(bg,target,'comparison_front.png','BLENDER FRONT (same scale)')
# Cyan boundary = model; magenta boundary = concept; fill half-transparent model.
over=bg.copy();fill=software.copy();fill.putalpha(fill.getchannel('A').point(lambda v:round(v*.32)));over.alpha_composite(fill)
for m,color in [(ref_gold|ref_blade,(225,40,160,230)),(model_gold|model_blade,(0,145,175,240))]:
    mask=mask_image(m);edge=np.array(mask.filter(ImageFilter.MaxFilter(5)))!=np.array(mask.filter(ImageFilter.MinFilter(5)))
    layer=np.zeros((H,W,4),np.uint8);layer[edge]=color;over.alpha_composite(Image.fromarray(layer))
over.resize((620,2100)).save(OUT/'silhouette_overlay.png')
