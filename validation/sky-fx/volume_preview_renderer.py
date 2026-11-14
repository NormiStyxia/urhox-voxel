"""CPU rasterizer for actual Lua meshes, interpolated gradient normals, no engine rendering."""
import numpy as np
import math

def norm(v):
    v=np.asarray(v,dtype=float);return v/np.maximum(np.linalg.norm(v,axis=-1,keepdims=True),1e-12)
def smooth(a,b,x):
    t=np.clip((x-a)/(b-a),0,1);return t*t*(3-2*t)
def sky(w,h):
    t=np.linspace(0,1,h)[:,None,None]**.8
    return np.repeat(np.array([.30,.43,.66])[None,None,:]*(1-t)+np.array([.73,.71,.78])[None,None,:]*t,w,axis=1)
def mesh(s):
    vs=s['vertices'];ids=s['indices']
    p=np.array([[v['x'],v['y'],v['z']] for _,v in sorted(vs.items())])
    n=np.array([[v['nx'],v['ny'],v['nz']] for _,v in sorted(vs.items())])
    c=np.array([[v['thickness'],v['height'],v['ao']] for _,v in sorted(vs.items())])
    f=np.array([ids[i]-1 for i in range(1,len(ids)+1)],dtype=int).reshape(-1,3)
    return p,n,c,f

def render(canvas,s,view,center,scale,fog=0,yaw=0,stretch=(1,1,1)):
    p,n,c,faces=mesh(s);p=p*np.array(stretch);n=n/np.array(stretch)
    cs,sn=math.cos(yaw),math.sin(yaw);rot=np.array([[cs,0,sn],[0,1,0],[-sn,0,cs]])
    p=p@rot.T;n=norm(n@rot.T)
    v=norm(view);right=norm((v[2],0,-v[0]));up=np.cross(v,right)
    screen=np.stack([center[0]+p@right*scale,center[1]-p@up*scale,p@v],axis=1)
    H,W=canvas.shape[:2]
    # Ideal CPU back-to-front blending, explicitly not proof of engine's batch ordering.
    faces=faces[np.argsort(screen[faces,2].mean(axis=1))]
    light=norm((-.45,.83,.33))
    for ix in faces:
        q=screen[ix];a,b,d=q[:,:2]
        face=np.cross(p[ix[1]]-p[ix[0]],p[ix[2]]-p[ix[0]])
        if face@v<=0:continue
        xmin=max(0,int(np.floor(q[:,0].min())));xmax=min(W-1,int(np.ceil(q[:,0].max())))
        ymin=max(0,int(np.floor(q[:,1].min())));ymax=min(H-1,int(np.ceil(q[:,1].max())))
        if xmin>xmax or ymin>ymax:continue
        den=(b[1]-d[1])*(a[0]-d[0])+(d[0]-b[0])*(a[1]-d[1])
        if abs(den)<1e-8:continue
        xx,yy=np.meshgrid(np.arange(xmin,xmax+1)+.5,np.arange(ymin,ymax+1)+.5)
        wa=((b[1]-d[1])*(xx-d[0])+(d[0]-b[0])*(yy-d[1]))/den
        wb=((d[1]-a[1])*(xx-d[0])+(a[0]-d[0])*(yy-d[1]))/den;wc=1-wa-wb
        weights=np.stack([wa,wb,wc],axis=-1)
        z=weights@q[:,2];area=(slice(ymin,ymax+1),slice(xmin,xmax+1))
        mask=weights.min(axis=-1)>=-1e-8
        if not mask.any():continue
        ns=norm(weights@n[ix]);attrs=weights@c[ix]
        lit=ns@light;wrap=np.clip((lit+.45)/1.45,0,1)
        stepped=.35*smooth(.12,.36,wrap)+.65*smooth(.48,.76,wrap)
        bands=.24+.76*(.55*wrap+.45*stepped)
        bands*=.68+.32*smooth(-.50,.50,ns[:,:,1])
        dark=np.array([.54,.60,.76]);bright=np.array([.99,.98,.94])
        col=(dark+(bright-dark)*bands[:,:,None])*(.92+.08*attrs[:,:,2,None])
        facing=np.clip(ns@v,0,1);rim=(1-facing)**3
        col+=rim[:,:,None]*np.array([.11,.12,.14])
        col=col*(1-fog)+np.array([.69,.70,.79])*fog
        al=.98*smooth(0,.62,facing)*(1-fog*.35)
        canvas[area][mask]=canvas[area][mask]*(1-al[mask,None])+col[mask]*al[mask,None]
