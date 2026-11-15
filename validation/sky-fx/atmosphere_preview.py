"""CPU formal cloud/shaft/flame formula previews. No game lighting, Bloom or GPU.
Clouds reuse the real Lua mesh/atlas/palette with analytic derivatives; flame
panels show the exact procedural fragment, not a mock screenshot of the game.
"""
from pathlib import Path
import runpy,json,hashlib
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2]
r=runpy.run_path(str(ROOT/'validation/sky-fx/skycards_check.py'))
smooth=r['smooth'];srgb=r['srgb']
def flame(uv,time,phase,halo=False):
 y=uv[...,1];x=uv[...,0]*2-1
 sway=np.sin(y*8-time*2+phase)*.12*y+np.sin(y*14-time*3+phase)*.045*y
 width=.48*np.maximum(1-y,0)**.90
 body=1-smooth(width*.65,width+.03,np.abs(x-sway))
 left_width=.30*np.maximum(1-y/(.68+np.sin(time*1.8+phase)*.06),0)**.75
 tongue=(1-smooth(left_width*.65,left_width+.015,np.abs(x+.36-sway*.7)))*(1-smooth(.62,.75,y))
 right_width=.26*np.maximum(1-y/(.54+np.sin(time*2.2+phase)*.05),0)**.75
 other=(1-smooth(right_width*.65,right_width+.015,np.abs(x-.35-sway)))*(1-smooth(.48,.61,y))
 coverage=np.maximum(body,np.maximum(tongue,other))*smooth(0,.06,y)*(1-smooth(.94,1,y))
 core=(1-smooth(.07,.32,np.abs(x-sway*.4)))*(1-smooth(.10,.60,y))
 color=np.array([2.3,.28,.025])*(1-core[...,None])+np.array([3.2,1.9,.45])*core[...,None]
 alpha=coverage*.76
 if halo:
  q=(uv-.5)*2;h=np.maximum(0,1-np.sum(q*q,axis=-1));color=np.broadcast_to([1.6,.32,.035],color.shape);alpha=h*h*h*.065
 return color,alpha
def fire_image(time,night,w=230,h=280):
 y,x=np.mgrid[:h,:w];world=np.stack([(x+.5-w/2)/h*3.8,(h-y-.5)/h*3.8-.7],axis=-1)
 out=np.zeros((h,w,3))+[.009,.018,.035]
 # Single plane perpendicular view + faint halo. Normal depth testing and
 # crossed-plane overlap/Zone fog cannot be validated by this local swatch.
 for halo in (True,False):
  uv=np.stack([world[...,0]/(3.2 if halo else .9)+.5,(world[...,1]+(.8 if halo else 0))/(3.2 if halo else 1.65)],axis=-1)
  valid=np.all((uv>=0)&(uv<=1),axis=-1);safe=np.clip(uv,0,1)
  color,alpha=flame(safe,time,np.floor(255/7)/255*6.283185,halo)
  alpha=np.where(valid,np.clip(alpha*night,0,.82),0)
  out=color*alpha[...,None]+out*(1-alpha[...,None])
 assert np.isfinite(out).all()
 return Image.fromarray(np.uint8(np.round(srgb(out)*255)))
def main():
 path=ROOT/'validation/sky-fx';metrics=[]
 canvas=Image.new('RGB',(1152,1040),(18,20,28));draw=ImageDraw.Draw(canvas)
 cases=[(0,.18,12,'DAY horizon'),(.1,.55,8,'MORNING upper'),(2,.18,18,'DUSK sun-facing'),(.4,-.52,23,'NIGHT / high down')]
 for row,(yaw,pitch,hour,label) in enumerate(cases):
  for col,(time,old) in enumerate(((300,True),(120,False),(300,False))):
   im,m=r['render'](yaw,pitch,hour,w=384,h=216,time=time,baseline=old)
   y=row*260;canvas.paste(im,(col*384,y+38));draw.text((col*384+8,y+5),label,fill='white')
   draw.text((col*384+8,y+20),('BASELINE' if old else 'CANDIDATE')+' t='+str(time)+'s / CPU',fill='white')
   metrics.append(dict(view=label,time=time,baseline=old,**m))
 canvas.save(path/'atmosphere-cloud-motion.png')
 # Same time, same fixed view direct before/after plus exact initial equality.
 before,_=r['render'](0,.18,12,w=384,h=216,time=0,baseline=True)
 after,_=r['render'](0,.18,12,w=384,h=216,time=0)
 assert np.array_equal(np.asarray(before),np.asarray(after))
 grid=Image.new('RGB',(920,650),(18,20,28));draw=ImageDraw.Draw(grid)
 for row,night in enumerate((.3,1.)):
  for col,time in enumerate((0,.4,.8,1.2)):
   grid.paste(fire_image(time,night),(230*col,325*row+38))
   draw.text((230*col+6,325*row+6),f'CPU fire / night={night} / t={time}',fill='white')
   draw.text((230*col+6,325*row+21),'No Bloom / no scene lighting',fill='white')
 grid.save(path/'atmosphere-flame-frames.png')
 uv=np.stack(np.meshgrid(np.linspace(0,1,96),np.linspace(0,1,160)),axis=-1)
 for t in np.linspace(0,20,81):
  for halo in (False,True):
   color,alpha=flame(uv,t,.7,halo)
   assert np.isfinite(color).all() and np.isfinite(alpha).all() and alpha.min()>=0 and alpha.max()<=.82
 # Formal existing shaft shader with only the new travelling world band.
 grid=Image.new('RGB',(900,360),(18,20,28));draw=ImageDraw.Draw(grid)
 yy,xx=np.mgrid[:300,:300];u=(xx+.5)/300;v=1-(yy+.5)/300
 for i,(time,dusk,enabled) in enumerate(((0,0,True),(120,1,True),(240,0,False))):
  wx=-19+(u*2-1)*3.8;wz=-13-v*24;wy=7+v*45
  distance=np.sqrt(wx**2+(wy-8)**2+(wz+28)**2)
  edge=np.maximum(0,1-np.abs(u*2-1));ends=smooth(0,.22,v)*(1-smooth(.70,1,v))
  breath=.76+.24*np.sin(time*.15+wx*.09+wz*.05)
  band=.78+.22*np.sin(wx*.38+wz*.23-time*.08)
  alpha=edge*edge*ends*smooth(2,9,distance)*breath*band*.035*enabled
  color=np.array([1,.94,.72])*(1-dusk)+np.array([1,.65,.28])*dusk
  bg=np.array([.025,.045,.075]);out=color*alpha[...,None]+bg*(1-alpha[...,None])
  grid.paste(Image.fromarray(np.uint8(srgb(out)*255)),(i*300,45))
  draw.text((i*300+6,8),['DAY','DUSK envelope proxy','NIGHT off'][i]+' / CPU shaft',fill='white')
  draw.text((i*300+6,23),'Formal alpha; no Zone fog/Bloom',fill='white')
 grid.save(path/'atmosphere-shaft-swatches.png')
 (path/'atmosphere-preview-metrics.json').write_text(json.dumps(dict(clouds=metrics,shader_hashes={n:hashlib.sha256((ROOT/'assets/Shaders/BLGL'/n).read_bytes()).hexdigest() for n in ('RuinsCloud.shader','RuinsPillarFlame.shader','RuinsLightShaft.shader')}),indent=2))
 print('PASS CPU formal budget previews; initial sky identical; flame finite at 81 times; no Web/GPU/scene lighting claim')
if __name__=='__main__':main()
