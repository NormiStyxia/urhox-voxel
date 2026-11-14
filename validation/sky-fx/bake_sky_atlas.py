"""Original hierarchical cloud sculpture -> orthographic multichannel sky atlas.
No third-party pixels/meshes. Offline density/light bake, NOT a runtime volume.
R: diffuse/ambient shape, G: thin edge, B: horizontal normal, A: coverage.
"""
from pathlib import Path
import json, math, time
import numpy as np
from scipy.ndimage import gaussian_filter, distance_transform_edt, map_coordinates, zoom, shift
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[2]
SIZE=512
RECIPES=json.loads((ROOT/'validation/sky-fx/density-lobes.json').read_text())

def sculpture(index):
    rng=np.random.default_rng(9461+index)
    roots=np.array(RECIPES[index%6],float)
    balls=roots.tolist()
    # Two scales of budding growth, always smaller than their parent.
    parents=roots[1:]
    for generation in range(2):
        children=[]
        for x,y,z,rx,ry,rz in parents:
            for k in range(9 if generation==0 else 5):
                # Spend the first detail tier on the visible hemisphere. Random
                # rear buds were hidden by the large parent lobes in the bake.
                az=rng.uniform(.05,math.pi-.05) if generation==0 else rng.uniform(0,math.tau)
                up=rng.uniform(-.12,.97)
                radial=math.sqrt(1-up*up); ratio=rng.uniform(.18,.30)
                nx,ny,nz=radial*math.cos(az),up,radial*math.sin(az)
                child=[x+rx*nx,y+ry*ny,z+rz*nz,rx*ratio,ry*ratio,rz*ratio]
                children.append(child)
        balls.extend(children);parents=children
    balls=np.array(balls)
    if index>=6: # top-view cloud sea, not the profile used on the horizon
        balls=balls[:,[0,2,1,3,5,4]]
    return balls

def bake_cell(index):
    # Retained first prototype for research only; main() uses bake_volume_cell.
    balls=sculpture(index)
    lo=np.min(balls[:,:2]-balls[:,3:5],axis=0);hi=np.max(balls[:,:2]+balls[:,3:5],axis=0)
    center=(lo+hi)/2;span=max(hi-lo)*1.18
    axis=(np.arange(SIZE)+.5)/SIZE-.5
    yy,xx=np.meshgrid(center[1]-axis*span,center[0]+axis*span,indexing='ij')
    front=np.full((SIZE,SIZE),-10.);back=np.full_like(front,10.);mask=np.zeros_like(front,dtype=bool)
    for x,y,z,rx,ry,rz in balls:
        x0=max(0,int((x-rx-center[0])/span*SIZE+SIZE/2)-2);x1=min(SIZE,int((x+rx-center[0])/span*SIZE+SIZE/2)+3)
        y0=max(0,int((center[1]-y-ry)/span*SIZE+SIZE/2)-2);y1=min(SIZE,int((center[1]-y+ry)/span*SIZE+SIZE/2)+3)
        if x1<=x0 or y1<=y0:continue
        sl=np.s_[y0:y1,x0:x1];q=1-((xx[sl]-x)/rx)**2-((yy[sl]-y)/ry)**2
        inside=q>0;depth=rz*np.sqrt(np.maximum(q,0))
        f=np.where(inside,z+depth,-10);b=np.where(inside,z-depth,10)
        old=front[sl];h=np.maximum(.035-np.abs(old-f),0)/.035
        front[sl]=np.maximum(old,f)+h*h*.00875
        back[sl]=np.minimum(back[sl],b);mask[sl]|=inside
    # Extend nearest surface across the alpha edge before derivatives/filtering.
    indices=distance_transform_edt(~mask,return_distances=False,return_indices=True)
    z=front[tuple(indices)];z=gaussian_filter(z,.7)
    gy,gx=np.gradient(z,span/SIZE);normal=np.stack([-gx,gy,np.ones_like(z)],axis=-1)
    normal/=np.linalg.norm(normal,axis=-1)[...,None]
    # Baked upper hemisphere ambient/direct shape; moving sun adds lateral wrap.
    key=np.array([-.38,.68,.63]);key/=np.linalg.norm(key)
    direct=np.maximum(0,normal@key)
    # Soft self-occlusion evaluated against the independent high-res sculpture.
    gridy,gridx=np.mgrid[:SIZE,:SIZE];shadow=np.zeros_like(z)
    for dist in np.linspace(.045,.62,14):
        target=map_coordinates(z,[gridy-key[1]*dist/(span/SIZE),gridx+key[0]*dist/(span/SIZE)],order=1,mode='nearest')
        shadow+=np.clip((target-z-key[2]*dist)/.10,0,1)/14
    cavity=np.clip((gaussian_filter(z,6)-z)/.10,0,1)
    light=np.clip(.30+.68*direct-.28*shadow-.12*cavity,0,1)
    # Smooth narrow bands, retain fine sculpture information instead of hard posterization.
    light=.72*light+.28*(.30+.70*np.clip((light-.36)/.52,0,1))
    signed=distance_transform_edt(mask)-distance_transform_edt(~mask)
    alpha=np.clip(.5+signed/2.2,0,1)
    thickness=np.maximum(0,front-back)
    thin=np.exp(-thickness*4.2)*mask
    thin=np.maximum(thin,np.exp(-np.maximum(signed,0)/2.2)*.42*mask)
    # Data channels in transparent gutter remain valid, preventing dark fringes.
    data=np.stack([light,np.clip(thin,0,1),normal[...,0]*.5+.5,alpha],axis=-1)
    assert alpha[:20].max()==0 and alpha[-20:].max()==0 and alpha[:,:20].max()==0 and alpha[:,-20:].max()==0
    return np.rint(np.clip(data,0,1)*255).astype(np.uint8),len(balls)

def resize_channels(data,size):
    # These are independent scalar fields, NOT colour RGB. PIL RGBA resize
    # premultiplies/unpremultiplies RGB with A, corrupting small mask values.
    return np.stack([np.asarray(Image.fromarray(data[...,i].astype(np.float32))
        .resize(size,Image.Resampling.LANCZOS)) for i in range(4)],axis=-1)

def bake_volume_cell(index):
    # High-quality OFFLINE integration; the runtime only samples the baked channels.
    balls=sculpture(index);n,nz=512,160
    lo=np.min(balls[:,:3]-balls[:,3:],axis=0);hi=np.max(balls[:,:3]+balls[:,3:],axis=0)
    center=(lo+hi)*.5;span=max((hi-lo)[:2])*1.22;depth=(hi[2]-lo[2])*1.15
    axis=(np.arange(n)+.5)/n-.5;az=(np.arange(nz)+.5)/nz-.5
    xs=center[0]+axis*span;ys=center[1]-axis*span;zs=center[2]+az*depth
    sdf=np.full((nz,n,n),10.,dtype=np.float32)
    for bx,by,bz,rx,ry,rz in balls:
        ix=np.flatnonzero(np.abs(xs-bx)<rx+.15);iy=np.flatnonzero(np.abs(ys-by)<ry+.15);iz=np.flatnonzero(np.abs(zs-bz)<rz+.15)
        if not len(ix)*len(iy)*len(iz):continue
        sl=np.s_[iz[0]:iz[-1]+1,iy[0]:iy[-1]+1,ix[0]:ix[-1]+1]
        q=(np.sqrt(((zs[iz,None,None]-bz)/rz)**2+((ys[None,iy,None]-by)/ry)**2+((xs[None,None,ix]-bx)/rx)**2)-1)*min(rx,ry,rz)
        old=sdf[sl];h=np.maximum(.055-np.abs(old-q),0)/.055
        sdf[sl]=np.minimum(old,q)-h*h*.01375
    rng=np.random.default_rng(115+index)
    for cells,amp in [(12,.05),(28,.025),(56,.008)]:
        noise=zoom(rng.uniform(-1,1,(max(4,cells//3),cells,cells)).astype(np.float32),(nz/max(4,cells//3),n/cells,n/cells),order=1,prefilter=False)
        sdf+=noise*amp
    density=np.clip((.02-sdf)/.04,0,1);density=density*density*(3-2*density)
    del sdf
    # Directional single scattering baked for the artist's upper-left key; runtime
    # adds broad dynamic direction colour/wrap. This is not dynamic 3D self-shadow.
    sun=np.array([-.48,.72,.50]);sun/=np.linalg.norm(sun)
    tau=np.zeros_like(density)
    ds=.045
    for step in range(1,25):
        offset=sun*ds*step
        tau+=shift(density,[-offset[2]/(depth/nz),offset[1]/(span/n),-offset[0]/(span/n)],order=1,mode='constant',cval=0,prefilter=False)*ds*3.5
    visibility=np.exp(-tau);del tau
    trans=np.ones((n,n));radiance=np.zeros((n,n));depthsum=np.zeros((n,n));mass=np.zeros((n,n))
    dz=depth/nz
    for z in range(nz-1,-1,-1):
        a=1-np.exp(-density[z]*dz*8.0);weight=trans*a
        lit=.32+.68*visibility[z]**.8
        radiance+=weight*lit;depthsum+=weight*zs[z];mass+=density[z]*dz
        trans*=1-a
    alpha=1-trans
    light=radiance/np.maximum(alpha,1e-8)
    front=depthsum/np.maximum(alpha,1e-8);mask=alpha>.02
    indices=distance_transform_edt(~mask,return_distances=False,return_indices=True)
    front=gaussian_filter(front[tuple(indices)],1.2)
    _,gx=np.gradient(front,span/n);nx=-gx/np.sqrt(1+gx*gx)
    thin=np.exp(-mass*3.8)*alpha
    # Keep a thin upper/side shoulder, not an equally bright full outline.
    ay,ax=np.gradient(gaussian_filter(alpha,1.0))
    edge_facing=np.clip((-ax*sun[0]+ay*sun[1])/np.maximum(np.hypot(ax,ay),.0001),0,1)
    thin*=.2+.8*edge_facing
    light=light[tuple(indices)]
    # Authored coverage is separate from radiance: a crisp body with a short AA edge,
    # rather than displaying the whole low-density halo as pale fog.
    coverage=np.clip((alpha-.12)/.76,0,1);coverage=coverage*coverage*(3-2*coverage)
    channels=np.stack([light,thin,nx*.5+.5,coverage],axis=-1)
    out=np.rint(np.clip(resize_channels(channels,(SIZE,SIZE)),0,1)*255).astype(np.uint8)
    return out,len(balls)

def main():
    start=time.perf_counter();atlas=np.zeros((1024,2048,4),dtype=np.uint8)
    for i in range(8):
        cell,count=bake_volume_cell(i);atlas[(i//4)*SIZE:(i//4+1)*SIZE,(i%4)*SIZE:(i%4+1)*SIZE]=cell
        print('shape',i+1,'sculpture lobes',count,'coverage',int(np.sum(cell[...,3]>127)))
    path=ROOT/'assets/Textures/Sky/cloud_sculpted_atlas.png'
    Image.fromarray(atlas).save(path)
    small=np.rint(np.clip(resize_channels(atlas.astype(float)/255,(1024,512)),0,1)*255).astype(np.uint8)
    Image.fromarray(small).save(path.with_name('cloud_sculpted_atlas_low.png'))
    # Neutral shader-like colour preview, explicitly an asset view rather than Web.
    t=atlas.astype(float)/255;a=t[...,3,None];light=t[...,0,None]
    color=np.array([.26,.38,.58])*(1-light)+np.array([1.,.97,.90])*light
    color=color*a+np.array([.15,.32,.55])*(1-a)
    srgb=np.where(color<=.0031308,color*12.92,1.055*color**(1/2.4)-.055)
    im=Image.fromarray(np.rint(np.clip(srgb,0,1)*255).astype(np.uint8));im.thumbnail((1280,640))
    ImageDraw.Draw(im).text((8,8),'ORIGINAL OFFLINE SCULPTURE / asset preview / not Web',fill='white')
    im.save(ROOT/'validation/sky-fx/sculpted-atlas-preview.png')
    ch=Image.new('RGB',(1024,1024));cell=Image.fromarray(atlas[:512,:512])
    for i,channel in enumerate(cell.split()):
        ch.paste(channel.convert('RGB'),((i%2)*512,(i//2)*512));ImageDraw.Draw(ch).text(((i%2)*512+8,(i//2)*512+8),['R shape lighting','G thin transmission','B normal X','A coverage'][i],fill='red')
    ch.save(ROOT/'validation/sky-fx/sculpted-channels.png')
    print('seconds',time.perf_counter()-start,'bytes',path.stat().st_size)

if __name__=='__main__':main()
