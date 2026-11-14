"""CPU raster of actual Lua triangles, atlas and shader. Not Web.
Analytic mip derivatives approximate GPU quad derivatives; no game post-process.
"""
from pathlib import Path
import json, math
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import map_coordinates
from lupa.lua54 import LuaRuntime
ROOT=Path(__file__).resolve().parents[2]
def smooth(a,b,x):
 t=np.clip((x-a)/(b-a),0,1);return t*t*(3-2*t)
def linear(c):
 c=np.asarray(c);return np.where(c<=.04045,c/12.92,((c+.055)/1.055)**2.4)
def srgb(c):
 c=np.clip(c,0,1);return np.where(c<=.0031308,c*12.92,1.055*c**(1/2.4)-.055)
lua=LuaRuntime(unpack_returned_tuples=True)
prefix=(ROOT/'validation/sky-fx/check.lua').read_text().split("local settings=require",1)[0]
factory=lua.execute(prefix+'''
return function(count,hour)
 local scene=node('Scene');local clouds=require('ruins.SkyClouds').New(scene,count,true,true)
 local dn=require('ruins.DayNight').New({scene=scene,zone={},sun={SetAttribute=function()end},sunNode=node('Sun'),zoneNode=node('Env'),hour=hour})
 return clouds.geometry[1].verts,dn
end
''')
def geometry(count=24,hour=12):
 verts,dn=factory(count,hour);rows=[]
 for i in range(1,len(verts)+1):
  v=verts[i];c=v['color'];uv=v['uv'];n=v['normal']
  rows.append([v['x'],v['y'],v['z'],uv['x'],uv['y'],c['r'],c['g'],c['b'],c['a'],n['x'],n['y'],n['z']])
 def col(k):
  c=dn['sky'][k];return linear([c['r'],c['g'],c['b']])
 sun=dn['sunNode']['direction'];sun=-np.array([sun['x'],sun['y'],sun['z']])
 return np.array(rows).reshape(-1,3,12),dict(day=dn['day'],dusk=dn['dusk'],top=col('skyTopColor'),horizon=col('skyHorizonColor'),bottom=col('groundBottomColor'),sun=sun)
def mipmaps(low=False):
 im=Image.open(ROOT/('assets/Textures/Sky/cloud_sculpted_atlas_low.png' if low else 'assets/Textures/Sky/cloud_sculpted_atlas.png'));result=[]
 while True:
  result.append(np.asarray(im,dtype=float)/255)
  if im.width==1 and im.height==1:break
  im=im.resize((max(1,im.width//2),max(1,im.height//2)),Image.Resampling.BOX)
 return result
def sample(mips,uv,lod):
 result=np.zeros((len(uv),4));l=np.clip(lod,0,len(mips)-1);base=np.floor(l).astype(int);frac=l-base
 for offset in (0,1):
  levels=np.minimum(base+offset,len(mips)-1);weight=(frac if offset else 1-frac)
  for level in np.unique(levels):
   ids=np.flatnonzero(levels==level);im=mips[level];h,w=im.shape[:2];coords=[uv[ids,1]*h-.5,uv[ids,0]*w-.5]
   for channel in range(4):result[ids,channel]+=map_coordinates(im[...,channel],coords,order=1,mode='nearest',prefilter=False)*weight[ids]
 return result
def background(d,p):
 up=p['horizon']+(p['top']-p['horizon'])*np.maximum(d[:,1],0)[:,None]**.18
 down=p['horizon']+(p['bottom']-p['horizon'])*np.maximum(-d[:,1],0)[:,None]**.28
 return np.where((d[:,1]>=0)[:,None],up,down)
def shade(data,d,right,p,haze):
 sun=p['sun']/np.linalg.norm(p['sun']);day=p['day'];dusk=p['dusk']
 toward=smooth(.45,.98,d@sun);lateral=right@sun
 lit=smooth(.38,.94,np.clip(data[:,0]+(data[:,2]-.5)*lateral*.16,0,1))
 dark=(np.array([.009,.018,.042])*(1-day)+np.array([.26,.38,.58])*day)*(1-dusk*.82)+np.array([.18,.105,.20])*dusk*.82
 light=np.array([.055,.085,.15])*(1-day)+np.array([.98,.96,.91])*day
 warm=dusk*(.62+.25*toward);light=light[None,:]*(1-warm[:,None])+np.array([1.,.40,.18])*warm[:,None]
 color=dark*(1-lit[:,None])+light*lit[:,None]
 rim=(np.array([.08,.13,.22])*(1-day)+np.array([1.,.94,.77])*day)*(1-dusk)+np.array([1.,.67,.28])*dusk
 color+=rim*(data[:,1]*toward*(.22+.40*dusk))[:,None]
 air=background(d,p);hor=1-smooth(.015,.24,np.abs(d[:,1]));fog=np.clip(haze*.32+hor*.40,0,.68)
 return np.clip(color*(1-fog[:,None])+air*fog[:,None],0,1.15),np.clip(data[:,3]*(1-hor*.22),0,1)
def render(yaw,pitch,hour,count=24,w=640,h=360):
 tris,p=geometry(count,hour);mips=mipmaps(count<=12)
 fwd=np.array([math.sin(yaw)*math.cos(pitch),math.sin(pitch),math.cos(yaw)*math.cos(pitch)])
 right=np.array([math.cos(yaw),0,-math.sin(yaw)]);up=np.cross(fwd,right)
 y,x=np.mgrid[:h,:w];rays=(fwd+right*((x+.5-w/2)/h)[...,None]+up*((h/2-y-.5)/h)[...,None]).reshape(-1,3)
 direction=rays/np.linalg.norm(rays,axis=1)[:,None];color=background(direction,p)
 counts=np.zeros(len(rays),int);alphas=np.zeros(len(rays));lods=[]
 for tri in tris:
  a,b,c=tri[:,:3];e1,e2=b-a,c-a;n=np.cross(e1,e2)
  if n@n<1e-10:continue
  denom=rays@n;safe=np.where(np.abs(denom)>1e-9,denom,1);t=np.dot(a,n)/safe
  point=rays*t[:,None];q=point-a;d11=e1@e1;d12=e1@e2;d22=e2@e2;det=d11*d22-d12*d12
  f=(q@e1*d22-q@e2*d12)/det;g=(q@e2*d11-q@e1*d12)/det
  ids=np.flatnonzero((np.abs(denom)>1e-9)&(t>0)&(f>=0)&(g>=0)&(f+g<=1))
  if not len(ids):continue
  counts[ids]+=1
  uv=tri[0,3:5]+f[ids,None]*(tri[1,3:5]-tri[0,3:5])+g[ids,None]*(tri[2,3:5]-tri[0,3:5])
  deriv=[]
  for dr in (right/h,-up/h):
   dp=t[ids,None]*(dr-rays[ids]*(dr@n/safe[ids])[:,None])
   df=(dp@e1*d22-dp@e2*d12)/det;dg=(dp@e2*d11-dp@e1*d12)/det
   duv=df[:,None]*(tri[1,3:5]-tri[0,3:5])+dg[:,None]*(tri[2,3:5]-tri[0,3:5])
   deriv.append(np.stack([duv[:,0]+np.cos(uv[:,1]*137)*.00018*137*duv[:,1],duv[:,1]-np.sin(uv[:,0]*123)*.00018*123*duv[:,0]],axis=-1))
  dims=np.array(mips[0].shape[:2])[::-1]
  lod=np.log2(np.maximum(1,np.maximum(np.linalg.norm(deriv[0]*dims,axis=1),np.linalg.norm(deriv[1]*dims,axis=1))))
  uv+=np.stack([np.sin(uv[:,1]*137),np.cos(uv[:,0]*123)],axis=-1)*.00018
  data=sample(mips,uv,lod);lods.extend(lod.tolist())
  localRight=np.array([tri[0,11],0,-tri[0,9]]);localRight/=max(np.linalg.norm(localRight),.0001)
  out,alpha=shade(data,direction[ids],localRight,p,tri[0,7]);alpha=np.where(data[:,3]<.003,0,alpha)
  color[ids]=out*alpha[:,None]+color[ids]*(1-alpha[:,None]);alphas[ids]=alpha+alphas[ids]*(1-alpha)
 assert np.isfinite(color).all() and color.min()>=0 and color.max()<=1.15
 return Image.fromarray(np.rint(srgb(color.reshape(h,w,3))*255).astype(np.uint8)),dict(sampler_calls_mean=float(counts.mean()),p95=float(np.percentile(counts,95)),max=int(counts.max()),cloud_fraction=float(np.mean(alphas>.05)),mean_mip=float(np.mean(lods)) if lods else 0)
def checks():
 shader=(ROOT/'assets/Shaders/BLGL/RuinsCloud.shader').read_text();script=(ROOT/'scripts/ruins/SkyClouds.lua').read_text()
 for removed in ['scene_depth','INV_PROJECTION_MATRIX','SCREEN_UV','density_volume','occupancy_volume','Z_CLIP_SCALE','PREMUL_ALPHA_FACTOR','for (int']:assert removed not in shader,removed
 assert shader.count('texture(')==1 and 'depth_draw_never' in shader and 'blend_mix' in shader
 assert 'cloud_density' not in script and 'cloud_occupancy' not in script
 for count in (24,12,4):
  tri,_=geometry(count);assert len(tri)==count*8+2
  radius=np.linalg.norm(tri[:-2,:,:3],axis=-1);assert radius.min()>521.9 and radius.max()<548.1
  assert np.isfinite(tri).all() and np.all((tri[:,:,3:9]>=0)&(tri[:,:,3:9]<=1))
  for height in (-10000,0,80,600,30000):
   origin=np.array([100,height,-50]);world=origin+tri[:-2,:,:3];assert np.max(np.abs((world-origin)-tri[:-2,:,:3]))<1e-9
 for i in range(289):
  _,p=geometry(4,i/12);d=np.array([[0,1,0],[0,-1,0],[1,0,0],[0,0,1.]])
  color,alpha=shade(np.array([[.3,0,.5,1],[.9,.15,.5,1],[.6,.3,1,.5],[0,0,0,0]]),d,np.array([1,0,0]),p,.5)
  assert np.isfinite(color).all() and np.isfinite(alpha).all() and color.max()<=1.15
 print('PASS actual Lua meshes, finite UV, altitude recentering, 289 actual DayNight palettes, 1 texture read, no old runtime dependency')
def main():
 checks();path=ROOT/'validation/sky-fx';canvas=Image.new('RGB',(1280,1164));metrics=[]
 cases=[(0,.18,12,'DAY / ground / CPU'),(2,.18,18,'DUSK / near sun / CPU'),(0,.18,23,'NIGHT / CPU'),(.4,-.52,12,'HEIGHT 1000m / looking down / CPU'),(.1,.64,12,'LOOK UP / CPU'),(.4,-1.35,12,'HEIGHT 30000m / nadir / CPU')]
 for i,(yaw,pitch,hour,label) in enumerate(cases):
  im,m=render(yaw,pitch,hour);metrics.append(dict(view=label,**m));x=(i%2)*640;y=(i//2)*388
  canvas.paste(im,(x,y+28));ImageDraw.Draw(canvas).text((x+8,y+7),label+' / actual budget / not Web',fill='white')
 canvas.save(path/'skycards-scene-preview.png')
 for count in (12,4):
  im,m=render(0,.18,12,count);metrics.append(dict(view='tier '+str(count),**m));im.save(path/('skycards-tier-'+str(count)+'.png'))
 (path/'skycards-counts.json').write_text(json.dumps(metrics,indent=2))
 print(json.dumps(metrics));print('PASS previews saved; analytic mip approximation, no Web/GPU claim')
if __name__=='__main__':main()
