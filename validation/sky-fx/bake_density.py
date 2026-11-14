"""Offline scalar 3D density; PNG stores slices, never a billboard.
R/G/B = high/medium/low fields. Fixed recipes and seed, metres, no engine needed.
"""
import json, math, time
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
N, H, COLS = 256, 96, 16
LO = np.array([-320., -96., -320.])
HI = np.array([320., 160., 320.])
LOBES = json.loads((ROOT/'validation/sky-fx/density-lobes.json').read_text())

def placements(count):
    result=[]
    for layer in range(1,4):
        amount=count//3 + int(layer<=count%3)
        if count==4: amount=4 if layer==2 else 0
        if count==24: amount+= -2 if layer==1 else (2 if layer==2 else 0)
        for i in range(1,amount+1):
            a=(i/amount+layer*.19)*math.tau
            near=layer==1 and i<=max(2,amount//3)
            r=103+i*6 if layer==3 else (232+i%3*13 if layer==2 else (70 if near else 118+i*5))
            y=-40-i*2 if layer==3 else (48+i%3*6 if layer==2 else (48 if near else 67+i%3*7))
            size=[32 if layer==2 else (20 if near else 16+i%3*2),7 if layer==2 else (13 if layer==3 else (20 if near else 16)),22 if layer==2 else (26 if layer==3 else 18+i%2*3)]
            result.append(dict(center=[math.cos(a)*r,y,math.sin(a)*r],scale=size,yaw=i*1.73+layer*.8,variant=(i+layer)%6,layer=layer))
    return result

def bake(count):
    z,y,x=np.meshgrid(np.linspace(LO[2],HI[2],N),np.linspace(LO[1],HI[1],H),np.linspace(LO[0],HI[0],N),indexing='ij')
    field=np.zeros(x.shape,dtype=np.float32)
    for cloud in placements(count):
        cx,cy,cz=cloud['center'];sx,sy,sz=cloud['scale'];yaw=cloud['yaw']
        px=((x-cx)*math.cos(yaw)-(z-cz)*math.sin(yaw))/sx
        py=(y-cy)/sy
        pz=((x-cx)*math.sin(yaw)+(z-cz)*math.cos(yaw))/sz
        d=np.full(x.shape,100.,dtype=np.float32)
        for bx,by,bz,rx,ry,rz in LOBES[cloud['variant']]:
            q=(np.sqrt(((px-bx)/rx)**2+((py-by)/ry)**2+((pz-bz)/rz)**2)-1)*min(rx,ry,rz)
            h=np.maximum(.10-np.abs(d-q),0)/.10
            d=np.minimum(d,q)-h*h*.025
        # Fixed spatial erosion, no screen-space noise and no runtime regeneration.
        noise=(np.sin(px*3.1+np.sin(pz*2.7))*np.sin(py*3.4+1.1)+.40*np.sin(px*8.7+pz*4.3)*np.sin(py*7.1))/1.4
        d+=noise*.075
        # 2m-ish boundary at near-cloud scale, instead of the old ~6m haze ramp.
        den=np.clip((.025-d)/.10,0,1)
        den=den*den*(3-2*den)
        field=np.maximum(field,den*(.65 if cloud['layer']==2 else .92))
    assert not np.any(field[[0,-1]]) and not np.any(field[:,[0,-1]]) and not np.any(field[:,:,[0,-1]])
    return field

def main():
    start=time.perf_counter()
    atlas=np.zeros((H*(N//COLS),N*COLS,3),dtype=np.uint8)
    occupancy=np.zeros((128,256,3),dtype=np.uint8)
    for channel,count in enumerate([24,12,4]):
        field=bake(count)
        quantized=np.rint(field*255).astype(np.uint8)
        # Conservative max over every source voxel that can contribute by trilinear
        # interpolation anywhere in this 20x8x20m cell. Never average occupancy.
        for z in range(32):
            zz=slice(math.floor(z*(N-1)/32),math.ceil((z+1)*(N-1)/32)+1)
            for y in range(32):
                yy=slice(math.floor(y*(H-1)/32),math.ceil((y+1)*(H-1)/32)+1)
                for x in range(32):
                    xx=slice(math.floor(x*(N-1)/32),math.ceil((x+1)*(N-1)/32)+1)
                    occupancy[(z//8)*32+y,(z%8)*32+x,channel]=255 if quantized[zz,yy,xx].any() else 0
        for z in range(N):
            atlas[(z//COLS)*H:(z//COLS+1)*H,(z%COLS)*N:(z%COLS+1)*N,channel]=quantized[z]
        if channel==2:
            from scipy.ndimage import zoom
            low=zoom(field,(.5,1/3,.5),order=1,prefilter=False)
            small=np.zeros((256,2048,3),dtype=np.uint8)
            for z in range(128):
                small[(z//16)*32:(z//16+1)*32,(z%16)*128:(z%16+1)*128,:]=np.rint(low[z]*255).astype(np.uint8)[:,:,None]
            Image.fromarray(small).save(ROOT/'assets/Textures/Sky/cloud_density_low.png')
        print('tier',count,'occupied',int(np.count_nonzero(field)),'max',float(field.max()))
    dest=ROOT/'assets/Textures/Sky/cloud_density.png'
    Image.fromarray(atlas).save(dest)
    Image.fromarray(occupancy).save(ROOT/'assets/Textures/Sky/cloud_occupancy.png')
    print('density bake seconds',time.perf_counter()-start,'PNG bytes',dest.stat().st_size,'GPU RGB/RGBA bytes',atlas.size,atlas.shape[0]*atlas.shape[1]*4)

if __name__=='__main__': main()
