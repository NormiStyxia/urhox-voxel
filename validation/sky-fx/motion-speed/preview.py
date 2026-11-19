"""Same formal shader/atlas, FOV55/yaw/pitch/exposure. CPU only, not Web."""
from pathlib import Path
import runpy,json
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[3];D=Path(__file__).resolve().parent
r=runpy.run_path(str(ROOT/'validation/sky-fx/skycards_check.py'))
rows=json.loads((D/'actual-lua-uniforms.json').read_text())
for count in (4,12,24):
 canvas=Image.new('RGB',(1280,420));draw=ImageDraw.Draw(canvas)
 for j,version in enumerate(('old','new')):
  for i,t in enumerate((0,3,5,10)):
   data=rows[str(count)][str(t)][version]
   image,metrics=r['render'](.5,.24,12,count=count,w=320,h=180,time=data[4],wind_value=data[:4],fov=55)
   x,y=i*320,j*210
   canvas.paste(image,(x,y+30))
   draw.text((x+5,y+6),f'CPU ONLY | {count} | {version} | {t}s | FOV55',fill='white')
 canvas.save(D/f'sequence-{count}-cpu.png')
print('PASS 3 formal old/new CPU sequences, times0/3/5/10, fixed camera/lighting/atlas, one cloud texture sample; NOT WEB')
