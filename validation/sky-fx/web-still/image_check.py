"""Measure captured Web pixels, never a generated cloud rendering."""
from pathlib import Path
from PIL import Image,ImageDraw
import numpy as np,json
D=Path(__file__).resolve().parent
frames=[Image.open(D/n).convert("RGB") for n in ("fixed0.webp","fixed10.webp")]
a,b=[np.asarray(f) for f in frames]
assert a.shape==b.shape==(646,1280,3)
seconds=json.loads((D/"frame-timing.json").read_text())["deltaSeconds"]
# Left shoulder below the clock HUD and above the fixed arch.
edges=[]
for img in (a,b):
 rows=[]
 for y in range(112,130):
  xs=np.where((img[y,440:560,0]>190)&(img[y,440:560,1]>190))[0]
  assert len(xs)>0
  rows.append(int(xs[0]+440))
 edges.append(np.array(rows))
shift=float(np.median(edges[1]-edges[0]))
# Fixed stone gradient registration tolerates changing exposure.
def gradient(img):
 g=img.astype(float).mean(axis=2)
 return np.diff(g,axis=1)
g0,g1=map(gradient,(a,b))
scores=[]
for dy in range(-4,5):
 for dx in range(-4,5):
  x=g0[215:265,300:400].ravel();y=g1[215+dy:265+dy,300+dx:400+dx].ravel()
  scores.append((float(np.corrcoef(x,y)[0,1]),dx,dy))
corr,dx,dy=max(scores)
report={"source":"REAL WEB SCREENSHOTS, no runtime/code/parameter edits between frames",
 "elapsed_wall_seconds":seconds,"cloud_left_edge_median_dx_px":shift,
 "stone_registration_dx_px":dx,"stone_registration_dy_px":dy,"stone_gradient_correlation":corr,
 "limits":"18 shoulder rows; no full optical flow/GPU readback; this session only; quality/persisted motion unobserved"}
(D/"web-motion-measurement.json").write_text(json.dumps(report,indent=2))
# Screenshots are lossy WebP and the directional light advances between frames.
# Require the zero-displacement match to win, not pixel-identical stone shading.
assert shift>15 and dx==0 and dy==0 and corr>.90,report
out=Image.new("RGB",(1280,510),(20,24,30));draw=ImageDraw.Draw(out)
for i,f in enumerate(frames):
 y=i*255
 draw.text((12,y+8),f"REAL WEB | t={0 if i==0 else seconds:.3f}s | original screenshot crop, same camera",fill="white")
 crop=f.crop((0,48,1280,270));out.paste(crop,(0,y+28))
 draw=ImageDraw.Draw(out)
 x=int(np.median(edges[0]));draw.line((x,y+28,x,y+140),fill=(255,70,70),width=2)
 x=int(np.median(edges[i]));draw.line((x,y+85,x+35,y+85),fill=(255,230,60),width=2)
out.save(D/"web-motion-21s.png")
print(json.dumps(report,indent=2));print("PASS real Web cloud moves against fixed architecture; other sessions unresolved")
