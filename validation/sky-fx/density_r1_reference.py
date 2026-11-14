"""CPU mirror of RuinsCloud integration, not a Web screenshot or shader compiler.
Samples the shipped quantized voxels; same bounds, interpolation, lighting and steps.
"""
from pathlib import Path
import math, json
import numpy as np
from scipy.ndimage import map_coordinates
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[2]
im=np.asarray(Image.open(ROOT/'validation/sky-fx/density-r1.png')).astype(float)/255
V=np.stack([im[(z//16)*96:(z//16+1)*96,(z%16)*256:(z%16+1)*256] for z in range(256)])
assert V.shape==(256,96,256,3) and np.isfinite(V).all()
assert V.min()==0 and 0.6<V.max()<1
assert not V[[0,-1]].any() and not V[:,[0,-1]].any() and not V[:,:,[0,-1]].any()
LO=np.array([-320.,-96.,-320.]);HI=np.array([320.,160.,320.])
def smooth(a,b,v):
 t=np.clip((v-a)/(b-a),0,1);return t*t*(3-2*t)
def density(p,channel=0):
 q=(p-LO)/(HI-LO)*[255,95,255]
 return map_coordinates(V[:,:,:,channel],q[..., [2,1,0]].reshape(-1,3).T,order=1,mode='constant',cval=0,prefilter=False).reshape(p.shape[:-1])
def box_interval(ro,rd,lo,hi):
 shape=np.broadcast_shapes(ro.shape[:-1],rd.shape[:-1]);near=np.zeros(shape);far=np.full(shape,600.)
 for axis in range(3):
  o,d=ro[...,axis],rd[...,axis];parallel=np.abs(d)<1e-6
  divisor=np.where(parallel,1,d)
  a,b=(lo[axis]-o)/divisor,(hi[axis]-o)/divisor
  near=np.maximum(near,np.where(parallel,-2e6,np.minimum(a,b)))
  far=np.minimum(far,np.where(parallel,2e6,np.maximum(a,b)))
  far=np.where(parallel&((o<lo[axis])|(o>hi[axis])),-1.,far)
 return near,far
def interval(ro,rd,lower=True):
 ua,ub=box_interval(ro,rd,[-320,30,-320],[320,160,320])
 la,lb=box_interval(ro,rd,[-320,-96,-320],[320,-8,320])
 u,l=ub>ua,lb>la
 if not lower:return np.where(u,ua,1.),np.where(u,ub,-1.)
 a=np.where(u&l,np.minimum(ua,la),np.where(u,ua,np.where(l,la,1.)))
 b=np.where(u&l,np.maximum(ub,lb),np.where(u,ub,np.where(l,lb,-1.)))
 return a,b
def march(ro,rd,channel=0,day=1.,dusk=0.,scene=600.,stats=None):
 a,b=interval(ro,rd,lower=channel!=2);b=np.minimum(b,scene)
 steps=[96,48,20][channel];lights=[2,1,0][channel]
 ds=np.maximum(0,b-a)/steps
 scatter=np.zeros(rd.shape);trans=np.ones(rd.shape[:-1])
 counts={k:np.zeros(rd.shape[:-1],dtype=int) for k in ['iterations','main','nonempty','light','density_reads','occupancy_reads','exhausted']}
 def readable(p):return np.all((p>=LO)&(p<=HI),axis=-1)&~((p[...,1]>-8)&(p[...,1]<30))
 sun=np.array([-.6,.7,-.35]);sun/=np.linalg.norm(sun)
 mu=np.clip(rd@sun,-1,1);phase=.7975/np.maximum(1.2025-.9*mu,.3)**1.5
 horizon=np.array([.38,.53,.75])*(.12+.88*day)
 zenith=np.array([.07,.22,.52])*(.12+.88*day)
 dark=(np.array([.012,.023,.052])*(1-day)+np.array([.34,.43,.61])*day)*(1-dusk*.65)+np.array([.24,.18,.31])*dusk*.65
 light=(np.array([.07,.11,.20])*(1-day)+np.array([.94,.93,.88])*day)*(1-dusk*.72)+np.array([1.,.56,.29])*dusk*.72
 for i in range(steps):
  t=a+(i+.5)*ds;p=ro+rd*t[...,None]
  live=(b>a)&(trans>=.008)
  counts['main']+=live;counts['iterations']+=live;counts['density_reads']+=2*(readable(p)&live)
  d=density(p,channel)*smooth(.25,2,t)*smooth(0,2,scene-t)
  active=(d>.001)&(trans>=.008)&(b>a)
  counts['nonempty']+=active;counts['light']+=active*lights
  shadow=np.zeros_like(d)
  for j in range(lights):
   shadow+=density(p+sun*[6,22][j],channel)*[12,20][j]
   counts['density_reads']+=2*(readable(p+sun*[6,22][j])&active)
  vis=np.exp(-np.minimum(shadow*.065,12))
  band=.35*smooth(.12,.42,vis)+.65*smooth(.48,.88,vis)
  h=smooth(np.where(p[...,1]<0,-75,42),np.where(p[...,1]<0,-28,115),p[...,1])
  ambient=dark*(1-(.12+h*.12)[...,None])+zenith*(.12+h*.12)[...,None]
  lum=ambient*(.65+h*.22)[...,None]+light*((.22+.78*(vis*.7+band*.3))*(.45+.22*phase))[...,None]
  fog=smooth(100,300,t)*.82
  lum=lum*(1-fog[...,None])+horizon*fog[...,None]
  tr=np.where(active,np.exp(-np.minimum(d*.065*ds,12)),1)
  scatter+=trans[...,None]*(1-tr[...,None])*lum;trans*=tr
 if stats is not None:stats.update(counts)
 return scatter,1-trans,horizon,zenith

def checks():
 # Godot-compatible inverse projection consumes window depth 0..1.
 # Test perspective and orthographic reconstruction without ever dividing at cleared far.
 def reconstruct(inv,uv,raw):
  if not np.isfinite(raw) or raw<0 or raw>1:return None
  if raw>=.999999:return 600.
  near=inv@np.array([*uv,0,1]);point=inv@np.array([*uv,raw,1])
  if not abs(near[3])>1e-6 or not abs(point[3])>1e-6:return None
  a=near[:3]/near[3];b=point[:3]/point[3]
  if not np.isfinite([a,b]).all():return None
  return np.clip(np.linalg.norm(b-a),0,600)
 n,f=.1,600.
 projection=np.array([[1.1,0,0,0],[0,1.7,0,0],[0,0,f/(n-f),f*n/(n-f)],[0,0,-1,0.]])
 orthographic=np.array([[.1,0,0,0],[0,.1,0,0],[0,0,1/(n-f),n/(n-f)],[0,0,0,1.]])
 for mat in [projection,orthographic]:
  inv=np.linalg.inv(mat)
  for raw in list(np.linspace(0,1,1001))+[float(np.float16(.9999)),1.0]:
   distance=reconstruct(inv,[.7,-.3],raw);assert distance is not None and np.isfinite(distance) and 0<=distance<=600
  for raw in [float('nan'),float('inf'),-1,1.1]:assert reconstruct(inv,[0,0],raw) is None
 assert reconstruct(np.zeros((4,4)),[0,0],.5) is None
 print('PASS perspective/orthographic depth, clear far, simulated half rounding, NaN/Inf and zero-w rejection')
 ys=np.linspace(-96,160,96)
 assert not V[:,(ys>-8)&(ys<30)].any(),'empty playable-height gap must remain valid'
 cases=[([0,0,0],[0,1,0],160),([0,200,0],[0,-1,0],296),([0,-120,0],[0,1,0],280),([0,60,0],[1,0,0],320),([320,0,0],[0,1,0],160),([321,0,0],[0,1,0],-1),([0,200,0],[0,1,0],-1),([0,18,0],[1,0,0],-1)]
 for o,d,end in cases:
  a,b=interval(np.array(o),np.array(d));assert np.isfinite([a,b]).all() and b==end,(o,d,a,b)
 rng=np.random.default_rng(811);o=rng.uniform([-450,-140,-450],[450,210,450],(4000,3));d=rng.normal(size=(4000,3));d/=np.linalg.norm(d,axis=1)[:,None]
 s,alpha,_,_=march(o,d)
 assert np.isfinite(s).all() and np.isfinite(alpha).all() and np.min(alpha)>=0 and np.max(alpha)<=1
 s0,a0,_,_=march(o,d,scene=0);assert not a0.any() and not s0.any()
 # Camera inside, above/below, along volume faces and scene clipping; randomized rays included.
 for k in range(289):
  elev=math.sin((k/12-6)/12*math.pi);day=float(smooth(-.1,.35,elev));dusk=math.exp(-((elev-.02)/.14)**2)
  s,alpha,_,_=march(o[:12],d[:12],day=day,dusk=dusk)
  assert np.isfinite(s).all() and (s>=0).all() and (s<=2).all()
 print('PASS quantized volume bounds, parallel/on-face/inside/outside rays, foreground clipping, 4000 seeded rays, 289 lighting times')

def render():
 w,h=480,270;canvas=Image.new('RGB',(w*2,(h+24)*2))
 cameras=[([0,18,0],[-43,75,55],'ground -> near cumulus'),([0,155,0],[-43,65,55],'above -> near cumulus'),([0,-100,0],[50,-40,-120],'below -> lower sea'),([-43,65,55],[60,80,50],'inside volume -> across')]
 for index,(origin,target,label) in enumerate(cameras):
  ro=np.array(origin,float);forward=np.array(target)-ro;forward/=np.linalg.norm(forward)
  right=np.cross(forward,[0,1,0]);right/=np.linalg.norm(right);up=np.cross(right,forward)
  y,x=np.mgrid[0:h,0:w];rd=forward+right*((x+.5-w/2)/h)[...,None]+up*((h/2-y-.5)/h)[...,None];rd/=np.linalg.norm(rd,axis=2)[...,None]
  s,a,horizon,zenith=march(ro,rd)
  sky=horizon+(zenith-horizon)*np.clip(rd[...,1],0,1)[...,None]**.4
  color=np.clip(s+sky*(1-a[...,None]),0,1)
  srgb=np.where(color<=.0031308,12.92*color,1.055*color**(1/2.4)-.055)
  tile=Image.fromarray(np.rint(srgb*255).astype(np.uint8))
  ox,oy=(index%2)*w,(index//2)*(h+24);canvas.paste(tile,(ox,oy+24));ImageDraw.Draw(canvas).text((ox+6,oy+5),'CPU SAME DENSITY / '+label,fill='white')
 canvas.save(ROOT/'validation/sky-fx/density-r1-preview.png')
 print('CPU preview written; no Web/GPU claim')

if __name__=='__main__':checks();render()
