"""CPU actual vertex + stable one-sample fragment, not an in-game screenshot."""
from pathlib import Path
import runpy,json
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[3];OUT=Path(__file__).resolve().parent
r=runpy.run_path(str(ROOT/'validation/sky-fx/skycards_check.py'))
rot=runpy.run_path(str(ROOT/'validation/sky-fx/rotation_check.py'))
canvas=Image.new('RGB',(1152,488));metrics=[]
for i,time in enumerate((0,600,1800)):
 for row,old in enumerate((True,False)):
  image,m=r['render'](.5,.24,12,count=24,w=384,h=216,time=time,baseline=old)
  x,y=i*384,row*244
  canvas.paste(image,(x,y+28));ImageDraw.Draw(canvas).text((x+6,y+8),f'CPU {"BASELINE" if old else "WIND"} t={time}s / NOT WEB',fill='white')
  metrics.append(dict(time=time,baseline=old,**m))
canvas.save(OUT/'motion-cpu.png')

# Same ground helper: explicit atlas LOD, two taps, virtual altitude 120m.
def mask(points,mips,projection):
 grid=points/150;cell=grid-np.floor(grid);slope=np.array(projection[:2]);slant=np.linalg.norm(slope)
 along=slope/max(slant,.0001);local=cell-.5
 envelope=16*cell[:,0]*(1-cell[:,0])*cell[:,1]*(1-cell[:,1])
 local-=np.outer(local@along,along)*((1-1/(1+.18*slant))*envelope[:,None])
 uv=(np.mod(np.floor(grid),[4,2])+.004+(local+.5)*.992)/[4,2]
 return r['sample'](mips,uv,np.full(len(uv),3-projection[3]))[:,3]
def ground(hour,time):
 _,p=r['geometry'](24,hour);sun=p['sun'];elev=np.sin((hour-6)/12*np.pi)
 envelope=r['smooth'](.04,.30,elev);strength=.16*p['day']*envelope
 proj=[*np.clip(sun[[0,2]]/max(sun[1],.15),-4,4),120,1]
 y,x=np.mgrid[:216,:384];world=np.stack([(x-192)*.85,(y-108)*.85],axis=-1).reshape(-1,2)
 point=world+np.array(proj[:2])*(120-6)-rot['raw'](rot['wind'](time))[:2]
 mips=r['mipmaps']();m=.5*(mask(point,mips,proj)+mask(point+[3,-2],mips,proj))
 shade=r['smooth'](.05,.92,m)
 factor=1+strength*((1-shade[:,None])*[.06,.03,0]-shade[:,None]*[1,.96,.86])
 # Neutral receiver swatch to isolate actual shader factor; no faux game geometry.
 color=r['srgb'](factor*np.array([.12,.23,.075]))
 return Image.fromarray(np.rint(color.reshape(216,384,3)*255).astype('uint8')),strength
canvas=Image.new('RGB',(1152,488))
for i,hour in enumerate((8,12,18)):
 image,m=r['render'](.5,.24,hour,count=24,w=384,h=216,time=600)
 canvas.paste(image,(i*384,28))
 ImageDraw.Draw(canvas).text((i*384+6,8),f'CPU {hour}:00 / t=600 / NOT WEB',fill='white')
 image,strength=ground(hour,600);canvas.paste(image,(i*384,272))
 ImageDraw.Draw(canvas).text((i*384+6,251),f'ALBEDO factor only / strength={strength:.3f}',fill='white')
canvas.save(OUT/'sun-shadow-cpu.png')
(OUT/'preview-counts.json').write_text(json.dumps(metrics,indent=2))
print('PASS CPU previews: actual vertex expressions / stable fragment / real high budget, shadow factor swatches only; not Web or GPU timing')
