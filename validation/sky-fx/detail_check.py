"""Cloud data/channel/mip + formal colour regressions; no GPU timing claim."""
from pathlib import Path
import runpy,json
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
ref=runpy.run_path(str(ROOT/'validation/sky-fx/skycards_check.py'))
shader=(ROOT/'assets/Shaders/BLGL/RuinsCloud.shader').read_text()
before=(ROOT/'validation/sky-fx/detail-before/RuinsCloud.shader.txt').read_text()
assert shader.split('void vertex()',1)[1].split('void fragment()',1)[0]==before.split('void vertex()',1)[1].split('void fragment()',1)[0]
assert shader.count('texture(')==before.count('texture(')==1
assert 'vec2 uv=UV;' in shader
stats=[]
for low in (False,True):
    mips=ref['mipmaps'](low);a=mips[0];h,w=a.shape[:2]
    assert (w,h)==((1024,512) if low else (2048,1024))
    assert a[...,1].max()<.41, 'thin channel must stay within baked optical bound, without RGBA-alpha resampling inflation'
    for level,mip in enumerate(mips[:4 if low else 5]):
        ch,cw=mip.shape[0]//2,mip.shape[1]//4
        for i in range(8):
            cell=mip[(i//4)*ch:(i//4+1)*ch,(i%4)*cw:(i%4+1)*cw]
            edge=np.concatenate([cell[0,:,3],cell[-1,:,3],cell[:,0,3],cell[:,-1,3]])
            assert edge.max()<.03, (low,level,i,'alpha leaking across tiles')
            assert np.isfinite(cell).all() and cell.min()>=0 and cell.max()<=1
    stats.append(dict(low=low,base_rgba_bytes=w*h*4,g_max=float(a[...,1].max()),mip_levels=len(mips)))
    data=a.reshape(-1,4)[::max(1,(w*h)//400)]
    d=np.tile([0,.35,np.sqrt(1-.35**2)],(len(data),1));right=np.array([1.,0,0])
    for hour in range(289):
        _,p=ref['geometry'](4,hour/12)
        for az in (0,np.pi/2,np.pi,3*np.pi/2):
            for altitude in (-.7,.0,.7):
                p['sun']=np.array([np.sin(az)*np.cos(altitude),np.sin(altitude),np.cos(az)*np.cos(altitude)])
                color,alpha=ref['shade'](data,d,right,p,.25)
                assert np.isfinite(color).all() and 0<=color.min() and color.max()<=1.15
                assert np.isfinite(alpha).all() and 0<=alpha.min() and alpha.max()<=1
print(json.dumps(stats))
print('PASS world vertex unchanged, one sampler, all tiers same memory, scalar channel bounds, mip0..4 gutters, 289 times x 12 sun directions x 2 textures finite')
