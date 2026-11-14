"""CPU mirror of RuinsCloud integration, not a Web screenshot or shader compiler.
Samples the shipped quantized voxels; same bounds, interpolation, lighting and steps.
"""
from pathlib import Path
import math, json
import numpy as np
from scipy.ndimage import map_coordinates
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[2]
im=np.asarray(Image.open(ROOT/'assets/Textures/Sky/cloud_density.png')).astype(float)/255
V=np.stack([im[(z//16)*96:(z//16+1)*96,(z%16)*256:(z%16+1)*256] for z in range(256)])
low=np.asarray(Image.open(ROOT/'assets/Textures/Sky/cloud_density_low.png')).astype(float)/255
VLOW=np.stack([low[(z//16)*32:(z//16+1)*32,(z%16)*128:(z%16+1)*128,0] for z in range(128)])
occ=np.asarray(Image.open(ROOT/'assets/Textures/Sky/cloud_occupancy.png')).astype(float)/255
O=np.stack([occ[(z//8)*32:(z//8+1)*32,(z%8)*32:(z%8+1)*32] for z in range(32)])
assert V.shape==(256,96,256,3) and np.isfinite(V).all()
assert V.min()==0 and 0.6<V.max()<1
assert not V[[0,-1]].any() and not V[:,[0,-1]].any() and not V[:,:,[0,-1]].any()
LO=np.array([-320.,-96.,-320.]);HI=np.array([320.,160.,320.])
def smooth(a,b,v):
 t=np.clip((v-a)/(b-a),0,1);return t*t*(3-2*t)
def density(p,channel=0):
 volume=VLOW if channel==2 else V[:,:,:,channel]
 dims=np.array(volume.shape)[[2,1,0]]-1
 q=(p-LO)/(HI-LO)*dims
 return map_coordinates(volume,q[..., [2,1,0]].reshape(-1,3).T,order=1,mode='constant',cval=0,prefilter=False).reshape(p.shape[:-1])
def readable(p):
 return np.all((p>=LO)&(p<=HI),axis=-1)&~((p[...,1]>-8)&(p[...,1]<30))
def occupied(p,channel=0):
 cell=np.floor((p-LO)/[20,8,20]).astype(int)
 valid=np.all((cell>=0)&(cell<32),axis=-1);c=np.clip(cell,0,31)
 return np.where(valid,O[c[...,2],c[...,1],c[...,0],channel],0),valid
def cell_exit(p,rd):
 cell=np.floor((p-LO)/[20,8,20]);face=LO+(cell+(rd>0))*[20,8,20]
 delta=(face-p)/np.where(np.abs(rd)<1e-6,1,rd)
 return np.min(np.where(np.abs(rd)<1e-6,100000,np.maximum(delta,0)),axis=-1)
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
def march(ro,rd,channel=0,day=1.,dusk=0.,scene=600.,stats=None,sun_direction=None,budget_override=None):
 shape=rd.shape[:-1];rays=rd.reshape(-1,3);origins=np.broadcast_to(ro,rd.shape).reshape(-1,3)
 a,b=interval(origins,rays,lower=channel!=2);b=np.minimum(b,scene)
 steps=[64,24,16][channel];limit=[96,80,16][channel];lights=0 if channel==2 else 1
 if budget_override is not None:steps,limit=budget_override # validation-only tail-loss check, never used for previews
 fixed=np.maximum(0,b-a)/steps;t=a.copy();trans=np.ones(len(a));scatter=np.zeros_like(rays)
 counts={k:np.zeros(len(a),dtype=int) for k in ['iterations','main','nonempty','light','density_reads','occupancy_reads','exhausted']}
 sun=np.array([-.6,.7,-.35] if sun_direction is None else sun_direction,dtype=float);sun/=np.linalg.norm(sun)
 mu=np.clip(rays@sun,-1,1);phase=.7975/np.maximum(1.2025-.9*mu,.3)**1.5
 horizon=np.array([.38,.53,.75])*(.12+.88*day);zenith=np.array([.07,.22,.52])*(.12+.88*day)
 dark=(np.array([.012,.023,.052])*(1-day)+np.array([.13,.21,.36])*day)*(1-dusk*.65)+np.array([.24,.18,.31])*dusk*.65
 light=(np.array([.07,.11,.20])*(1-day)+np.array([.94,.93,.88])*day)*(1-dusk*.72)+np.array([1.,.56,.29])*dusk*.72
 for i in range(limit):
  ids=np.flatnonzero((b>a)&(t<b)&(trans>=.008)&(counts['main']<steps))
  if not len(ids):break
  counts['iterations'][ids]+=1
  ds=fixed[ids]
  if channel!=2:
   probe=origins[ids]+rays[ids]*(t[ids]+.002)[:,None]
   mask,valid=occupied(probe,channel);counts['occupancy_reads'][ids]+=valid
   edge=cell_exit(probe,rays[ids])+.004
   empty=mask<.5;t[ids[empty]]+=np.maximum(edge[empty],.004)
   ids=ids[~empty];edge=edge[~empty]
   fine=np.clip(1.25+t[ids]*.004,1.25,2.6) if channel==0 else np.clip(3+t[ids]*.008,3,5.5)
   ds=np.minimum(fine,edge)
  if not len(ids):continue
  ds=np.minimum(ds,b[ids]-t[ids]);sample=t[ids]+.5*ds;p=origins[ids]+rays[ids]*sample[:,None]
  counts['main'][ids]+=1;counts['density_reads'][ids]+=2*readable(p)
  d=density(p,channel)*smooth(.25,2,sample)*smooth(0,2,scene-sample)
  active=d>.001;hit=ids[active];p=p[active];dist=sample[active];den=d[active];width=ds[active]
  counts['nonempty'][hit]+=1
  shadow=np.zeros(len(hit))
  if lights:
   shadow=density(p+sun*8,channel)*28
   counts['light'][hit]+=1;counts['density_reads'][hit]+=2*readable(p+sun*8)
  vis=np.exp(-np.minimum(shadow*.11,12));band=.35*smooth(.12,.42,vis)+.65*smooth(.48,.88,vis)
  h=smooth(np.where(p[:,1]<0,-75,42),np.where(p[:,1]<0,-28,115),p[:,1])
  ambient=dark*(1-(.12+h*.12)[:,None])+zenith*(.12+h*.12)[:,None]
  lum=ambient*(.48+h*.12)[:,None]+light*((.08+.92*(vis*.7+band*.3))*(.72+.22*phase[hit]))[:,None]
  fog=smooth(100,300,dist)*.55;lum=lum*(1-fog[:,None])+horizon*fog[:,None]
  tr=np.exp(-np.minimum(den*.11*width,12))
  scatter[hit]+=trans[hit,None]*(1-tr[:,None])*lum;trans[hit]*=tr
  t[ids]+=np.maximum(ds,.004)
 counts['exhausted']=((b>a)&(t<b-.005)&(trans>=.008)).astype(int)
 if stats is not None:stats.update({k:v.reshape(shape) for k,v in counts.items()})
 return scatter.reshape(rd.shape),(1-trans).reshape(shape),horizon,zenith

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
 points=rng.uniform(LO,HI,(40000,3))
 for tier in (0,1):
  dens=density(points,tier);mask,_=occupied(points,tier)
  assert np.all(mask[dens>0]>0),'occupancy must never hide trilinear density'
  for z in range(32):
   zz=slice(math.floor(z*255/32),math.ceil((z+1)*255/32)+1)
   for y in range(32):
    yy=slice(math.floor(y*95/32),math.ceil((y+1)*95/32)+1)
    for x in range(32):
     xx=slice(math.floor(x*255/32),math.ceil((x+1)*255/32)+1)
     assert O[z,y,x,tier]>0 or not V[zz,yy,xx,tier].any()
 for sign in (-1,1):
  rays=np.tile([sign,0.,0.],(40000,1));exit=cell_exit(points,rays)
  assert np.isfinite(exit).all() and (exit>=0).all()
 print('PASS 40000 points x 2 tiers conservative occupancy, parallel/boundary DDA finite')
 s,alpha,_,_=march(o,d)
 assert np.isfinite(s).all() and np.isfinite(alpha).all() and np.min(alpha)>=0 and np.max(alpha)<=1
 assert (s<=alpha[...,None]*2.1+1e-9).all(),'premultiplied radiance must vanish with zero opacity'
 s0,a0,_,_=march(o,d,scene=0);assert not a0.any() and not s0.any()
 # Camera inside, above/below, along volume faces and scene clipping; randomized rays included.
 for k in range(289):
  elev=math.sin((k/12-6)/12*math.pi);day=float(smooth(-.1,.35,elev));dusk=math.exp(-((elev-.02)/.14)**2)
  angle=k/288*math.tau
  s,alpha,_,_=march(o[:12],d[:12],day=day,dusk=dusk,sun_direction=[math.cos(angle),math.sin(angle),.35])
  assert np.isfinite(s).all() and (s>=0).all() and (s<=2).all()
 print('PASS quantized volume bounds, parallel/on-face/inside/outside rays, foreground clipping, 4000 seeded rays, 289 lighting times')

CAMERAS=[([0,18,0],[-43,75,55],'ground -> near cumulus'),([0,155,0],[-43,65,55],'above -> near cumulus'),([0,-100,0],[50,-40,-120],'below -> lower sea'),([-43,65,55],[60,80,50],'inside volume -> across')]
def camera(origin,target,w=480,h=270):
 ro=np.array(origin,float);forward=np.array(target)-ro;forward/=np.linalg.norm(forward)
 right=np.cross(forward,[0,1,0]);right/=np.linalg.norm(right);up=np.cross(right,forward)
 y,x=np.mgrid[0:h,0:w];rd=forward+right*((x+.5-w/2)/h)[...,None]+up*((h/2-y-.5)/h)[...,None];rd/=np.linalg.norm(rd,axis=2)[...,None]
 return ro,rd

def display(result,rd):
 s,a,horizon,zenith=result
 sky=horizon+(zenith-horizon)*np.clip(rd[...,1],0,1)[...,None]**.4
 color=np.clip(s+sky*(1-a[...,None]),0,1)
 srgb=np.where(color<=.0031308,12.92*color,1.055*color**(1/2.4)-.055)
 return Image.fromarray(np.rint(srgb*255).astype(np.uint8))

def render():
 import density_r1_reference as before
 w,h=480,270;canvas=Image.new('RGB',(w*2,(h+24)*4));current=Image.new('RGB',(w*2,(h+24)*2))
 metrics=[];totals={}
 for tier in range(3):
  for index,(origin,target,label) in enumerate(CAMERAS):
   ro,rd=camera(origin,target,w,h)
   for revision,fn in [('r1',before.march),('r2',march)]:
    stats={};result=fn(ro,rd,channel=tier,stats=stats)
    stats['total_reads']=stats['density_reads']+stats['occupancy_reads']
    if revision=='r2':assert stats['total_reads'].max()<=[352,176,32][tier]
    metric={'tier':['high','medium','low'][tier],'revision':revision,'view':label,'pixels':w*h}
    for key,value in stats.items():
     metric[key]={'mean':float(np.mean(value)),'p95':float(np.percentile(value,95)),'max':int(np.max(value))}
     totals.setdefault((tier,revision,key),[]).append(value.ravel())
    metric['visible_fraction']=float(np.mean(result[1]>.05));metrics.append(metric)
    if tier==0:
     tile=display(result,rd);ox=0 if revision=='r1' else w;oy=index*(h+24)
     canvas.paste(tile,(ox,oy+24));ImageDraw.Draw(canvas).text((ox+6,oy+5),revision.upper()+' CPU / '+label,fill='white')
     if revision=='r2':
      xx,yy=(index%2)*w,(index//2)*(h+24);current.paste(tile,(xx,yy+24));ImageDraw.Draw(current).text((xx+6,yy+5),'R2 CPU / '+label,fill='white')
 aggregates={}
 for (tier,revision,key),arrays in totals.items():
  value=np.concatenate(arrays);aggregates.setdefault(str(tier)+'_'+revision,{})[key]={'mean':float(value.mean()),'p95':float(np.percentile(value,95)),'max':int(value.max())}
 path=ROOT/'validation/sky-fx'
 canvas.save(path/'density-r2-comparison.png');current.save(path/'density-raymarch-preview.png')
 ro,rd=camera([-10,49,5],[-43,62,55],720,480)
 tile=display(march(ro,rd),rd);ImageDraw.Draw(tile).text((8,8),'R2 CPU / close cloud / no sharpening / dynamic sun sample',fill='white');tile.save(path/'density-r2-close.png')
 (path/'density-r2-counts.json').write_text(json.dumps({'meaning':'CPU branch-matched sampling-count proxy, NOT GPU timing; drift=0; sky background; all pixels denominator','views':metrics,'aggregate':aggregates},indent=2))
 for key,data in aggregates.items():print(key,'main',data['main'],'light',data['light'],'reads',data['total_reads'],'budget_exhausted',data['exhausted'])
 print('CPU before/after and close preview written; no Web/GPU claim')

def tail_check():
 results=[]
 for tier in (0,1):
  for origin,target,label in CAMERAS:
   ro,rd=camera(origin,target,160,90)
   limited=march(ro,rd,channel=tier)
   full=march(ro,rd,channel=tier,budget_override=(192,256))
   sky=limited[2]+(limited[3]-limited[2])*np.clip(rd[...,1],0,1)[...,None]**.4
   a=limited[0]+sky*(1-limited[1][...,None]);b=full[0]+sky*(1-full[1][...,None])
   error=np.max(np.abs(a-b),axis=-1)
   results.append({'tier':tier,'view':label,'linear_rgb_mean_error':float(error.mean()),'linear_rgb_p95_error':float(np.percentile(error,95)),'max_error':float(error.max()),'pixels_over_0.02':float(np.mean(error>.02))})
 (ROOT/'validation/sky-fx/density-r2-tail-loss.json').write_text(json.dumps(results,indent=2))
 print('PASS tail-loss proxy compared to same algorithm with 192 density / 256 traversal budget; see density-r2-tail-loss.json')

if __name__=='__main__':checks();render();tail_check()
